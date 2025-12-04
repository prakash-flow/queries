SET @cur_date      = '2025-11-05';
SET @last_day      = @cur_date;      
SET @country_code  = 'RWA';

WITH base AS (
  SELECT 
    a.cust_id,
    p.full_name AS borrower_name,
    p.mobile_num,
    b.reg_date,
    b.category,
    COALESCE(ai.field_2, b.district) AS district,
    a.acc_number,
    a.distributor_code,
    a.acc_prvdr_code,
    r.full_name AS rm_name,
    b.activity_status
  FROM borrowers b
  JOIN accounts a 
    ON a.cust_id = b.cust_id 
   AND a.is_primary_acc = 1
  LEFT JOIN address_info ai 
    ON ai.id = b.owner_address_id
  LEFT JOIN persons p 
    ON b.owner_person_id = p.id
  LEFT JOIN persons r 
    ON r.id = b.flow_rel_mgr_id
  WHERE b.country_code = @country_code
),

limit_cte AS (
  SELECT 
    acc.cust_id,
    MAX(j.limit_value) AS limit_value
  FROM accounts acc,
  JSON_TABLE(
    acc.conditions,
    '$[*]' COLUMNS (
      type VARCHAR(100) PATH '$.type',
      limit_value DECIMAL(15) PATH '$.limit'
    )
  ) AS j
  WHERE j.type = 'commission_based_limits'
  AND status = 'enabled'
  GROUP BY cust_id
),

ontime_cte AS (
  SELECT
    l.cust_id,
    ROUND(
      100 * SUM(
        CASE WHEN t.max_txn_date <= DATE_ADD(l.due_date, INTERVAL 1 DAY) THEN 1 ELSE 0 END
      ) / COUNT(l.loan_doc_id),
      2
    ) AS ontime_repayment_rate,
    SUM(
      CASE WHEN t.max_txn_date <= DATE_ADD(l.due_date, INTERVAL 1 DAY) THEN 1 ELSE 0 END
    ) AS ontime_settle_count
  FROM loans l
  JOIN (
      SELECT loan_doc_id, MAX(txn_date) AS max_txn_date
      FROM loan_txns
      WHERE txn_type = 'payment'
      GROUP BY loan_doc_id
  ) t ON l.loan_doc_id = t.loan_doc_id
  WHERE l.status = 'settled'
    AND l.paid_date <= CONCAT(@cur_date, ' 23:59:59')
    AND l.product_id NOT IN (43, 75, 300)
    AND l.status NOT IN ('voided','hold','pending_disbursal','pending_mnl_dsbrsl')
    AND l.country_code = @country_code
  GROUP BY l.cust_id
),

latest_txn AS (
  SELECT 
      l.cust_id,
      MAX(t.txn_date) AS last_txn_date
  FROM loans l
  JOIN loan_txns t 
    ON l.loan_doc_id = t.loan_doc_id
  LEFT JOIN (
      SELECT DISTINCT r1.record_code
      FROM record_audits r1
      JOIN (
          SELECT record_code, MAX(id) AS id
          FROM record_audits
          WHERE DATE(created_at) <= @last_day
          GROUP BY record_code
      ) r2 ON r1.id = r2.id
      WHERE JSON_EXTRACT(r1.data_after, '$.status') = 'disabled'
  ) disabled_cust 
    ON l.cust_id = disabled_cust.record_code
  WHERE DATE(t.txn_date) <= @last_day
    AND l.country_code = @country_code
    AND t.txn_type = 'disbursal'
    AND l.product_id NOT IN (43, 75, 300)
    AND l.status NOT IN ('voided','hold','pending_disbursal','pending_mnl_dsbrsl')
    AND disabled_cust.record_code IS NULL
  GROUP BY l.cust_id
),

activity_cte AS (
  SELECT
      lt.cust_id,
      CASE
          WHEN DATEDIFF(@last_day, lt.last_txn_date) <= 30 THEN 'Active'
          ELSE 'Inactive'
      END AS activity_category
  FROM latest_txn lt
),

loan_principal AS (
  SELECT 
      l1.cust_id,
      l1.loan_principal AS first_principal,
      l2.loan_principal AS last_principal,
      lc.loan_count,
      lc.last_date
  FROM (
      SELECT 
          cust_id, 
          MIN(disbursal_date) AS first_date, 
          MAX(disbursal_date) AS last_date,
          COUNT(*) AS loan_count
      FROM loans
      WHERE 
          DATE(disbursal_date) <= CONCAT(@cur_date, ' 23:59:59')
          AND product_id NOT IN (43, 75, 300)
          AND status NOT IN ('voided','hold','pending_disbursal','pending_mnl_dsbrsl')
      GROUP BY cust_id
  ) lc
  JOIN loans l1 
      ON l1.cust_id = lc.cust_id AND l1.disbursal_date = lc.first_date
  JOIN loans l2 
      ON l2.cust_id = lc.cust_id AND l2.disbursal_date = lc.last_date
),

post_upgrade_cte AS (
  SELECT
      l.cust_id,
      COUNT(*) AS loans_after_upgrade,
      SUM(
        CASE 
          WHEN t.max_txn_date <= DATE_ADD(l.due_date, INTERVAL 1 DAY) THEN 1 ELSE 0 END
      ) AS ontime_after_upgrade
  FROM loans l
  JOIN (
      SELECT loan_doc_id, MAX(txn_date) AS max_txn_date
      FROM loan_txns
      WHERE txn_type = 'payment'
      GROUP BY loan_doc_id
  ) t ON l.loan_doc_id = t.loan_doc_id
  JOIN customer_repayment_limits cr 
      ON cr.cust_id = l.cust_id AND cr.status = 'enabled'
  WHERE 
      l.disbursal_date > cr.loan_repaid_date 
      AND l.status = 'settled'
      AND l.product_id NOT IN (43, 75, 300)
      AND l.status NOT IN ('voided','hold','pending_disbursal','pending_mnl_dsbrsl')
  GROUP BY l.cust_id
),

last5_loans_cte AS (
  SELECT
      x.cust_id,
      ROUND(
        100 * SUM(
          CASE WHEN x.max_txn_date <= DATE_ADD(x.due_date, INTERVAL 1 DAY) THEN 1 ELSE 0 END
        ) / COUNT(*), 2
      ) AS last5_ontime_rate
  FROM (
    SELECT 
        l.cust_id,
        l.loan_doc_id,
        l.due_date,
        t.max_txn_date,
        ROW_NUMBER() OVER (PARTITION BY l.cust_id ORDER BY l.disbursal_date DESC) AS rn
    FROM loans l
    JOIN (
        SELECT loan_doc_id, MAX(txn_date) AS max_txn_date
        FROM loan_txns
        WHERE txn_type = 'payment'
        GROUP BY loan_doc_id
    ) t ON t.loan_doc_id = l.loan_doc_id
    JOIN customer_repayment_limits cr 
        ON cr.cust_id = l.cust_id AND cr.status = 'enabled'
    WHERE 
        l.disbursal_date > cr.loan_repaid_date 
        AND l.status = 'settled'
        AND l.product_id NOT IN (43, 75, 300)
        AND l.status NOT IN ('voided','hold','pending_disbursal','pending_mnl_dsbrsl')
  ) x
  WHERE x.rn <= 5
  GROUP BY x.cust_id
)

SELECT 
  b.cust_id               AS `Customer ID`,
  b.borrower_name         AS `Customer Name`,
  b.mobile_num            AS `Customer Number`,
  b.reg_date              AS `Registration Date`,
  b.category              AS `Category`,
  b.acc_number            AS `Account Number`,
  b.distributor_code      AS `Franchisee`,
  b.acc_prvdr_code        AS `Account Provider`,
  UPPER(b.district)       AS `District`,
  b.rm_name               AS `Relationship Manager`,
  l.limit_value           AS `Commission Limit`,
  last_date               AS `Last Loan Date`,
  COALESCE(a.activity_category, "Inactive") AS `Active/Inactive`,
  CONCAT(COALESCE(o.ontime_repayment_rate, '0.00'), ' %') AS `On-time Repayment %`,
  lp.last_principal       AS `Current FA Amount (Last Loan Amount)`,
  lp.loan_count           AS `Total Loans Taken`,
  cr.last_upgraded_amount  AS `Last Upgraded Amount`,
  cr.loan_repaid_date     AS `Last Upgraded Date`,
  COALESCE(pu.loans_after_upgrade, 0) AS `Loans After Upgrade`,
  COALESCE(pu.ontime_after_upgrade, 0) AS `On-time Paid After Upgrade`,
  COALESCE(CONCAT(last5.last5_ontime_rate, ' %'), '0.00 %') AS `On-time % (Last 5 Loans After Upgrade)`
FROM base b
LEFT JOIN limit_cte l ON l.cust_id = b.cust_id
LEFT JOIN ontime_cte o ON o.cust_id = b.cust_id
LEFT JOIN activity_cte a ON a.cust_id = b.cust_id
LEFT JOIN loan_principal lp ON lp.cust_id = b.cust_id
LEFT JOIN customer_repayment_limits cr ON cr.cust_id = b.cust_id AND cr.status = 'enabled'
LEFT JOIN post_upgrade_cte pu ON pu.cust_id = b.cust_id
LEFT JOIN last5_loans_cte last5 ON last5.cust_id = b.cust_id
HAVING l.limit_value > 0;