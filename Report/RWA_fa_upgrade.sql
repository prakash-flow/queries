WITH
  reassessment AS (
    SELECT cust_id, prev_limit
    FROM reassessment_results
    WHERE type = 'batch_reassessment'
      AND country_code = 'RWA'
  ),
  current_limit AS (
    SELECT
      a.cust_id,
      MAX(j.`limit`) AS cur_limit
    FROM accounts a
    JOIN JSON_TABLE(
      a.conditions,
      '$[*]' COLUMNS (
        type VARCHAR(50) PATH '$.type',
        `limit` DECIMAL(12) PATH '$.limit'
      )
    ) AS j
    WHERE a.is_removed = 0
      AND a.status = 'enabled'
      AND a.cust_id IN (SELECT cust_id FROM reassessment)
    GROUP BY a.cust_id
  ),
  customer_repayment AS (
    SELECT cust_id, loan_repaid_date, current_limit
    FROM customer_repayment_limits
    WHERE cust_id IN (SELECT cust_id FROM reassessment)
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
    FROM (
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
          PARTITION BY l.cust_id
          ORDER BY l.disbursal_date DESC
        ) AS rn
      FROM loans l
      JOIN customer_repayment cr
        ON cr.cust_id = l.cust_id
      WHERE l.disbursal_date > cr.loan_repaid_date
        AND (l.paid_date IS NOT NULL OR l.due_date <= (CURDATE() - INTERVAL 1 DAY))
        AND l.status NOT IN ('voided', 'hold', 'pending_disbursal','pending_mnl_dsbrsl') 
        AND l.product_id NOT IN (SELECT id FROM loan_products WHERE product_type = 'float_vending')
    ) AS t
    WHERE t.rn <= 5
  ),
  loan_summary AS (
    SELECT
      c.cust_id cust_id,
      COUNT(l.cust_id) AS total_loans,
    	COALESCE(MIN(loan_principal), c.cur_limit) min_loan_principal,
      COALESCE(SUM(is_ontime), 0) AS ontime_loans,
      GREATEST(5 - COALESCE(SUM(is_ontime), 0), 0) AS loans_needed_for_upgrade
    FROM current_limit c left join loan l on l.cust_id = c.cust_id
    GROUP BY cust_id, c.cur_limit
  ) ,
  repayment_based_limit AS (
    SELECT
      r.cust_id,
      (
        SELECT MAX(lmt)
        FROM (
          SELECT 70000 AS lmt UNION ALL
          SELECT 100000 UNION ALL
          SELECT 150000 UNION ALL
          SELECT 200000 UNION ALL
          SELECT 300000 UNION ALL
          SELECT 400000 UNION ALL
          SELECT 500000 UNION ALL
          SELECT 600000 UNION ALL
          SELECT 700000 UNION ALL
          SELECT 800000 UNION ALL
          SELECT 900000 UNION ALL
          SELECT 1000000 UNION ALL
          SELECT 1500000 UNION ALL
          SELECT 2000000 UNION ALL
          SELECT 2500000 UNION ALL
          SELECT 3000000
        ) AS limits
        WHERE limits.lmt <= LEAST(cl.cur_limit, l.min_loan_principal * 3)
      ) AS repayment_based_limit
    FROM reassessment r
    JOIN current_limit cl ON cl.cust_id = r.cust_id
    JOIN loan_summary l          ON l.cust_id = r.cust_id
    GROUP BY r.cust_id, cl.cur_limit, l.min_loan_principal
  ),
  loan_stats AS (
    SELECT
      l.cust_id,
      COUNT(*) AS total_loans_all,
      MAX(l.disbursal_date) AS last_disbursal_date
    FROM loans l
    JOIN reassessment r ON r.cust_id = l.cust_id
    WHERE l.status NOT IN ('voided', 'hold', 'pending_disbursal','pending_mnl_dsbrsl') 
      AND l.product_id NOT IN (SELECT id FROM loan_products WHERE product_type = 'float_vending')
    GROUP BY l.cust_id
  ),
  last_loan AS (
    SELECT l.cust_id, l.loan_principal AS last_loan_amount, last_disbursal_date
    FROM loans l
    JOIN loan_stats ls ON ls.cust_id = l.cust_id AND ls.last_disbursal_date = l.disbursal_date
  )
SELECT
  b.distributor_code AS `Distributor Code`,
  b.cust_id AS `Customer ID`,
  UPPER(CONCAT_WS(' ', p.first_name, p.middle_name, p.last_name)) AS `Customer Name`,
  p.mobile_num AS `Customer Mobile Number`,
  b.reg_date AS `Registration Date`,
  COALESCE(ls_all.total_loans_all, 0) AS `Total Loans`,
  r.prev_limit AS `Assessed eligibility\n(Previous)`,
  cl.cur_limit AS `Assessed eligibility\n(Upgrade)`,
  COALESCE(ll.last_loan_amount, 0) AS `Last Loan Amount`,
  ll.last_disbursal_date AS `Last Loan Date`,
#   cr.loan_repaid_date `Last Upgraded Date`,
#   COALESCE(ls.total_loans, 0) AS `Last 5 Considered Loans`,
#   COALESCE(ls.ontime_loans, 0) AS `On-time Loans at Last 5`,
  cr.current_limit AS `Repayment based eligibility\n(Current)`,
  rb.repayment_based_limit AS `Repayment Based Eligibility\n(After 5 on-time FAs)`,
  COALESCE(IF(ls.loans_needed_for_upgrade = 0, 5, ls.loans_needed_for_upgrade), 5) AS `Repayment Based Eligibility\n(Ontime payments required)`,
  UPPER(b.territory) AS `Territory`,
  UPPER(b.district) AS `District`,
  UPPER(b.location) AS `Location`,
  UPPER(CONCAT_WS(' ', rm.first_name, rm.middle_name, rm.last_name)) AS `RM Name`,
  rm.mobile_num AS `RM Mobile Number`
FROM reassessment r
JOIN current_limit cl       ON cl.cust_id = r.cust_id
JOIN customer_repayment cr  ON cr.cust_id = r.cust_id
JOIN borrowers b            ON b.cust_id = r.cust_id
JOIN persons p              ON p.id = b.owner_person_id
JOIN persons rm             ON rm.id = b.flow_rel_mgr_id
LEFT JOIN loan_summary ls   ON ls.cust_id = r.cust_id
LEFT JOIN repayment_based_limit rb ON rb.cust_id = r.cust_id
LEFT JOIN loan_stats ls_all ON ls_all.cust_id = r.cust_id
LEFT JOIN last_loan ll      ON ll.cust_id = r.cust_id;