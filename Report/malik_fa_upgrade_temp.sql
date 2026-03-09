WITH
  reassessment AS (
    SELECT
      cust_id
    FROM
      reassessment_results
    WHERE
      type = 'batch_reassessment'
      AND country_code = 'RWA'
      AND DATE(created_at) = '2026-02-12'
  ),
  current_limit AS (
    SELECT
      a.cust_id,
      MAX(j.`limit`) AS cur_limit
    FROM
      accounts a
      JOIN JSON_TABLE(
        a.conditions,
        '$[*]' COLUMNS (
          type VARCHAR(50) PATH '$.type',
          `limit` DECIMAL(12) PATH '$.limit'
        )
      ) AS j
    WHERE
      a.is_removed = 0
      AND a.status = 'enabled'
      AND a.cust_id IN (
        SELECT
          cust_id
        FROM
          reassessment
      )
    GROUP BY
      a.cust_id
  ),
  customer_repayment AS (
    SELECT
      cust_id,
      loan_repaid_date,
      current_limit
    FROM
      customer_repayment_limits
    WHERE
      cust_id IN (
        SELECT
          cust_id
        FROM
          reassessment
      )
      AND status = 'enabled'
  ),
  loan AS (
    SELECT
      t.cust_id,
      t.loan_doc_id,
      t.loan_principal,
      t.disbursal_date,
      t.due_date,
      t.paid_date,
      t.is_ontime
    FROM
      (
        SELECT
          l.cust_id,
          l.loan_doc_id,
          l.loan_principal,
          l.disbursal_date,
          l.due_date,
          l.paid_date,
          CASE
            WHEN DATEDIFF(l.paid_date, l.due_date) <= 1 THEN 1
            ELSE 0
          END AS is_ontime,
          ROW_NUMBER() OVER (
            PARTITION BY
              l.cust_id
            ORDER BY
              l.disbursal_date DESC
          ) AS rn
        FROM
          loans l
          JOIN customer_repayment cr ON cr.cust_id = l.cust_id
        WHERE
          l.disbursal_date > cr.loan_repaid_date
          AND (
            l.paid_date IS NOT NULL
            OR l.due_date <= (CURDATE() - INTERVAL 1 DAY)
          )
          AND l.loan_purpose = 'float_advance'
          AND l.status NOT IN(
            'voided',
            'hold',
            'pending_disbursal',
            'pending_mnl_dsbrsl'
          )
          AND l.product_id NOT IN(
            SELECT
              id
            FROM
              loan_products
            WHERE
              product_type = 'float_vending'
          )
      ) AS t
    WHERE
      t.rn <= 5
  ),
  loan_summary AS (
    SELECT
      c.cust_id,
      COUNT(l.cust_id) AS total_loans,
      COALESCE(MIN(l.loan_principal), c.cur_limit) AS min_loan_principal,
      COALESCE(SUM(l.is_ontime), 0) AS ontime_loans,
      COALESCE(5 - COALESCE(SUM(l.is_ontime), 0), 0) AS loans_needed_for_upgrade
    FROM
      current_limit c
      LEFT JOIN loan l ON l.cust_id = c.cust_id
    GROUP BY
      c.cust_id,
      c.cur_limit
  ),
  loan_stats AS (
    SELECT
      l.cust_id,
      COUNT(*) AS total_loans_all,
      MAX(l.disbursal_date) AS last_disbursal_date
    FROM
      loans l
      JOIN reassessment r ON r.cust_id = l.cust_id
    WHERE
      l.status NOT IN(
        'voided',
        'hold',
        'pending_disbursal',
        'pending_mnl_dsbrsl'
      )
      AND l.product_id NOT IN(
        SELECT
          id
        FROM
          loan_products
        WHERE
          product_type = 'float_vending'
      )
    GROUP BY
      l.cust_id
  ),
  last_loan AS (
    SELECT
      l.cust_id,
      l.loan_principal AS last_loan_amount,
      ls.last_disbursal_date
    FROM
      loans l
      JOIN loan_stats ls ON ls.cust_id = l.cust_id
      AND ls.last_disbursal_date = l.disbursal_date
  ),
  max_product_loan_taken AS (
    SELECT
      x.cust_id,
      COUNT(*) AS max_loans_taken
    FROM
      (
        SELECT
          l.cust_id,
          l.loan_principal,
          COALESCE(LEAST(cl.cur_limit, cr.current_limit), 0) AS max_fa_limit,
          l.disbursal_date,
          ROW_NUMBER() OVER (
            PARTITION BY
              l.cust_id
            ORDER BY
              l.disbursal_date DESC
          ) AS rn
        FROM
          loans l
          JOIN customer_repayment cr ON cr.cust_id = l.cust_id
          JOIN reassessment r ON r.cust_id = l.cust_id
          JOIN current_limit cl ON cl.cust_id = l.cust_id
        WHERE
          l.disbursal_date > cr.loan_repaid_date
          AND l.loan_purpose = 'float_advance'
          AND l.status NOT IN(
            'voided',
            'hold',
            'pending_disbursal',
            'pending_mnl_dsbrsl'
          )
          AND l.product_id NOT IN(
            SELECT
              id
            FROM
              loan_products
            WHERE
              product_type = 'float_vending'
          )
      ) x
    WHERE
      x.rn <= 5
      AND x.loan_principal = x.max_fa_limit
    GROUP BY
      x.cust_id
  )
SELECT
  b.distributor_code AS `Distributor Code`,
  b.cust_id AS `Customer ID`,
  UPPER(
    CONCAT_WS(' ', p.first_name, p.middle_name, p.last_name)
  ) AS `Customer Name`,
  p.mobile_num AS `Customer Mobile Number`,
  b.reg_date AS `Registration Date`,
  CASE
    WHEN b.category = "Referral" THEN "Referral"
    ELSE "Full KYC"
  END AS `Category`,
  COALESCE(ls_all.total_loans_all, 0) AS `Total Loans`,
  COALESCE(cl.cur_limit, 0) AS `Current Limit`,
  COALESCE(LEAST(cl.cur_limit, cr.current_limit), 0) AS `Repayment Based Limit`,
  COALESCE(ll.last_loan_amount, 0) AS `Last Loan Amount`,
  ll.last_disbursal_date AS `Last Loan Date`,
  CASE
    WHEN ll.last_disbursal_date IS NULL
    OR DATEDIFF(CURDATE(), ll.last_disbursal_date) > 30 THEN "Inactive"
    ELSE "Active"
  END AS `Activity Status`,
  CASE
    WHEN COALESCE(cl.cur_limit, 0) = COALESCE(LEAST(cl.cur_limit, cr.current_limit), 0) THEN "Upgraded"
  
    WHEN b.category = "Referral"
    AND COALESCE(cl.cur_limit, 0) > 400000
    AND COALESCE(LEAST(cl.cur_limit, cr.current_limit), 0) = 400000
    AND COALESCE(mlt.max_loans_taken, 0) >= 5
    AND COALESCE(ls.loans_needed_for_upgrade, 0) = 0 THEN "Need Full KYC to Upgrade"

    WHEN b.category = "Referral"
    AND COALESCE(cl.cur_limit, 0) > 400000
    AND COALESCE(LEAST(cl.cur_limit, cr.current_limit), 0) = 400000
    AND COALESCE(mlt.max_loans_taken, 0) >= 5
    AND COALESCE(ls.loans_needed_for_upgrade, 0) = 0 THEN "Need Full KYC to Upgrade"
  
  END AS `Repayment Based Eligibility (Ontime payments required)`,
  cr.loan_repaid_date AS `Last Upgraded Date`,
  UPPER(b.territory) AS `Territory`,
  UPPER(b.district) AS `District`,
  UPPER(b.location) AS `Location`,
  UPPER(
    CONCAT_WS(' ', rm.first_name, rm.middle_name, rm.last_name)
  ) AS `RM Name`,
  rm.mobile_num AS `RM Mobile Number`
FROM
  reassessment r
  JOIN current_limit cl ON cl.cust_id = r.cust_id
  JOIN customer_repayment cr ON cr.cust_id = r.cust_id
  JOIN borrowers b ON b.cust_id = r.cust_id
  JOIN persons p ON p.id = b.owner_person_id
  JOIN persons rm ON rm.id = b.flow_rel_mgr_id
  LEFT JOIN loan_summary ls ON ls.cust_id = r.cust_id
  LEFT JOIN max_product_loan_taken mlt ON mlt.cust_id = r.cust_id
  LEFT JOIN loan_stats ls_all ON ls_all.cust_id = r.cust_id
  LEFT JOIN last_loan ll ON ll.cust_id = r.cust_id;