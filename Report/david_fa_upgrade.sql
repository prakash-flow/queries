WITH
  base_customers AS (
    SELECT
      l.cust_id
    FROM
      loans l
    WHERE
      l.due_date BETWEEN '2025-12-15 00:00:00' AND '2026-01-31 23:59:59'
      AND l.country_code = 'UGA'
      AND l.loan_purpose = 'float_advance'
      AND l.status NOT IN(
        'voided',
        'hold',
        'pending_disbursal',
        'pending_mnl_dsbrsl'
      )
    GROUP BY
      l.cust_id
    HAVING
      COUNT(*) > 0
      AND SUM(
        CASE
          WHEN l.paid_date > l.due_date
          OR l.paid_date IS NULL THEN 1
          ELSE 0
        END
      ) = 0
  ),
  festive_loans AS (
    SELECT
      l.cust_id,
      COUNT(
        CASE
          WHEN l.paid_date BETWEEN '2025-12-15 00:00:00' AND '2026-01-31 23:59:59'  THEN 1
        END
      ) AS fas_settled_in_period,
      SUM(
        CASE
          WHEN l.paid_date BETWEEN '2025-12-15 00:00:00' AND '2026-01-31 23:59:59'  THEN l.flow_fee
          ELSE 0
        END
      ) AS total_fee_earned
    FROM
      loans l
      JOIN base_customers bc ON bc.cust_id = l.cust_id
    WHERE
      l.country_code = 'UGA'
      AND l.loan_purpose = 'float_advance'
      AND l.status NOT IN(
        'voided',
        'hold',
        'pending_disbursal',
        'pending_mnl_dsbrsl'
      )
    GROUP BY
      l.cust_id
  ),
  last_upgrade AS (
    SELECT
      crl.cust_id,
      crl.loan_repaid_date AS last_upgraded_date
    FROM
      customer_repayment_limits crl
      JOIN base_customers bc ON bc.cust_id = crl.cust_id
    WHERE
      crl.status = 'enabled'
  ),
  account_assessment AS (
    SELECT
      a.cust_id,
      DATE(MAX(a.last_assessment_date)) AS max_assessment_date
    FROM
      accounts a
      JOIN base_customers bc ON bc.cust_id = a.cust_id
    WHERE
      a.status = 'enabled'
      AND a.is_removed = 0
    GROUP BY
      a.cust_id
  ),
  post_upgrade_loans AS (
    SELECT
      l.cust_id,
      MAX(l.loan_principal) AS max_loan_principal_post_upgrade
    FROM
      loans l
      JOIN base_customers bc ON bc.cust_id = l.cust_id
      JOIN last_upgrade lu ON lu.cust_id = l.cust_id
      JOIN borrowers b ON b.cust_id = l.cust_id
      LEFT JOIN account_assessment aa ON aa.cust_id = l.cust_id
    WHERE
      l.country_code = 'UGA'
      AND l.loan_purpose = 'float_advance'
      AND l.status NOT IN(
        'voided',
        'hold',
        'pending_disbursal',
        'pending_mnl_dsbrsl'
      )
      /* Within festive duration */
      AND (
        (
          l.disbursal_date BETWEEN '2025-12-15 00:00:00' AND '2026-01-31 23:59:59'
        )
        OR (
          l.due_date BETWEEN '2025-12-15 00:00:00' AND '2026-01-31 23:59:59'
        )
      )
    GROUP BY
      l.cust_id
  )
SELECT
  b.cust_id AS `Customer ID`,
  cust_person.full_name AS `Customer Name`,
  rm_person.full_name AS `RM Name`,
  UPPER(ai.field_1) AS `Region`,
  b.tot_loans AS `Total FAs Taken`,
  fl.fas_settled_in_period AS `FAs Settled During the Period`,
  fl.total_fee_earned AS `Total Fee Earned During the Period`,
  b.crnt_fa_limit AS `Actual Eligibility`,
  LEAST(b.last_upgraded_amount, b.crnt_fa_limit) AS `Current FA Limit`,
  CASE
    WHEN IFNULL(pol.max_loan_principal_post_upgrade, 0) < 250000 THEN 250000
    WHEN IFNULL(pol.max_loan_principal_post_upgrade, 0) < 500000 THEN 500000
    WHEN IFNULL(pol.max_loan_principal_post_upgrade, 0) < 750000 THEN 750000
    WHEN IFNULL(pol.max_loan_principal_post_upgrade, 0) < 1000000 THEN 1000000
    WHEN IFNULL(pol.max_loan_principal_post_upgrade, 0) < 1500000 THEN 1500000
    WHEN IFNULL(pol.max_loan_principal_post_upgrade, 0) < 2000000 THEN 2000000
    WHEN IFNULL(pol.max_loan_principal_post_upgrade, 0) < 2500000 THEN 2500000
    WHEN IFNULL(pol.max_loan_principal_post_upgrade, 0) < 3000000 THEN 3000000
    WHEN IFNULL(pol.max_loan_principal_post_upgrade, 0) < 4000000 THEN 4000000
    WHEN IFNULL(pol.max_loan_principal_post_upgrade, 0) < 5000000 THEN 5000000
    ELSE NULL
  END AS `Next FA product (Regardless of Eligibility)`,
  lu.last_upgraded_date,
  COALESCE(b.last_assessment_date, aa.max_assessment_date) AS last_assessment_date,
  IFNULL(pol.max_loan_principal_post_upgrade, 0) AS `Current FA Amount`,
  CASE
    WHEN IFNULL(pol.max_loan_principal_post_upgrade, 0) < LEAST(b.last_upgraded_amount, b.crnt_fa_limit) THEN FALSE
    ELSE TRUE
  END AS `Is Upgraded Utilized`,
  CASE
    WHEN IFNULL(pol.max_loan_principal_post_upgrade, 0) < LEAST(b.last_upgraded_amount, b.crnt_fa_limit) THEN LEAST(b.last_upgraded_amount, b.crnt_fa_limit)
    ELSE 0
  END AS `Not Utilized Amount`
FROM
  base_customers bc
  JOIN festive_loans fl ON fl.cust_id = bc.cust_id
  JOIN borrowers b ON b.cust_id = bc.cust_id
  JOIN persons cust_person ON cust_person.id = b.owner_person_id
  LEFT JOIN persons rm_person ON rm_person.id = b.flow_rel_mgr_id
  LEFT JOIN address_info ai ON ai.id = b.owner_address_id
  LEFT JOIN last_upgrade lu ON lu.cust_id = b.cust_id
  LEFT JOIN post_upgrade_loans pol ON pol.cust_id = b.cust_id
  LEFT JOIN account_assessment aa ON aa.cust_id = b.cust_id
WHERE
  b.tot_loans > 10
  AND b.category NOT IN('Referral');