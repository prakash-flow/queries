WITH
limit_chain AS (
  SELECT
    crl.id AS current_id,
    crl.cust_id,
    prev.current_limit AS previous_limit,
    crl.current_limit AS current_limit,
    crl.loan_repaid_date AS upgraded_date,
    crl.last_upgraded_amount
  FROM customer_repayment_limits crl
  LEFT JOIN customer_repayment_limits prev
    ON crl.prev_limit_id = prev.id
  WHERE crl.country_code = 'UGA'
    AND crl.is_removed = 0
    AND crl.loan_repaid_date BETWEEN '2025-08-01 00:00:00' AND '2025-08-31 23:59:59'
    AND crl.prev_limit_id IS NOT NULL
),

/* Loans that actually utilized the upgrade (amount > previous_limit) */
utilized_loans AS (
  SELECT
    lc.cust_id,
    l.id AS loan_id,
    l.disbursal_date,
    l.loan_principal,
    l.flow_rel_mgr_id,
    ROW_NUMBER() OVER (
      PARTITION BY lc.cust_id
      ORDER BY l.disbursal_date ASC, l.id ASC
    ) AS rn
  FROM limit_chain lc
  JOIN loans l
    ON l.cust_id = lc.cust_id
   AND l.disbursal_date >= lc.upgraded_date
   AND l.loan_principal > lc.previous_limit
),

/* First (earliest) utilized loan per customer */
first_utilized AS (
  SELECT
    ul.cust_id,
    ul.loan_id,
    ul.disbursal_date AS first_utilization_date,
    ul.flow_rel_mgr_id
  FROM utilized_loans ul
  WHERE ul.rn = 1
),

/* Latest loan overall (for current FA amount) */
latest_loan AS (
  SELECT
    l.cust_id,
    l.loan_principal AS last_loan_amount,
    l.disbursal_date AS last_loan_disbursal_date,
    l.flow_rel_mgr_id,
    ROW_NUMBER() OVER (
      PARTITION BY l.cust_id
      ORDER BY l.disbursal_date DESC, l.id DESC
    ) AS rn
  FROM loans l
),

final_data AS (
  SELECT
    lc.cust_id,
    CONCAT_WS(' ', p.first_name, p.middle_name, p.last_name) AS customer_name,
    /* Registered + Alternate numbers from persons */
    p.mobile_num AS registered_contact_number,
    p.alt_biz_mobile_num_1 AS alternate_contact_number,

    /* Pick RM from first utilized loan; else from latest post-upgrade loan */
    CONCAT_WS(
      ' ',
      rm.first_name,
      rm.middle_name,
      rm.last_name
    ) AS rm_name,

    lc.previous_limit,
    lc.current_limit,
    ll.last_loan_amount AS current_fa_amount,      -- latest loan amount overall
    lc.last_upgraded_amount AS upgraded_amount,
    lc.upgraded_date AS date_of_upgrade_eligibility,
    fu.first_utilization_date AS date_of_upgrade_utilization,
    CASE WHEN fu.first_utilization_date IS NOT NULL THEN 'YES' ELSE 'NO' END AS utilized
  FROM limit_chain lc
  JOIN borrowers b            ON lc.cust_id = b.cust_id
  JOIN persons   p            ON b.owner_person_id = p.id
  LEFT JOIN latest_loan ll    ON lc.cust_id = ll.cust_id AND ll.rn = 1
  LEFT JOIN first_utilized fu ON lc.cust_id = fu.cust_id
  LEFT JOIN persons rm   ON ll.flow_rel_mgr_id = rm.id 
)

/* ---- Sheet 1: Utilized ---- */
SELECT
  customer_name           AS `Customer Name`,
  cust_id                 AS `Customer ID`,
  rm_name                 AS `RM Name`,
  registered_contact_number AS `Registered Contact`,
  alternate_contact_number  AS `Alternate Contact`,
  previous_limit          AS `Previous Limit`,
  current_limit           AS `Current Limit`,
  current_fa_amount       AS `Current FA Amount`,
  upgraded_amount         AS `Upgraded Amount`,
  date_of_upgrade_eligibility AS `Date of Upgrade Eligibility`,
  date_of_upgrade_utilization AS `Date of Upgrade Utilization`,
  utilized                AS `Utilized`
FROM final_data
WHERE utilized = 'YES';

/* ---- Sheet 2: Not Utilized ---- */
SELECT
  customer_name           AS `Customer Name`,
  cust_id                 AS `Customer ID`,
  rm_name                 AS `RM Name`,
  registered_contact_number AS `Registered Contact`,
  alternate_contact_number  AS `Alternate Contact`,
  previous_limit          AS `Previous Limit`,
  current_limit           AS `Current Limit`,
  current_fa_amount       AS `Current FA Amount`,
  upgraded_amount         AS `Upgraded Amount`,
  date_of_upgrade_eligibility AS `Date of Upgrade Eligibility`,
  utilized                AS `Utilized`
FROM final_data
WHERE utilized = 'NO';