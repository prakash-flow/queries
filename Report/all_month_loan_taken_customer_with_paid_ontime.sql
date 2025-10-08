SET @country_code = 'UGA';
SET @start_month = 202501; -- Jan 2025
SET @end_month   = 202509; -- Sep 2025

WITH monthly_loans AS (
  SELECT
    cust_id,
    EXTRACT(YEAR_MONTH FROM disbursal_date) AS loan_month
  FROM loans
  WHERE loan_purpose = 'float_advance'
    AND product_id NOT IN (43, 75, 300)
    AND status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
    AND country_code = @country_code
    AND EXTRACT(YEAR_MONTH FROM disbursal_date) BETWEEN @start_month AND @end_month
  GROUP BY cust_id, loan_month
),
all_month_customers AS (
  SELECT cust_id
  FROM monthly_loans
  GROUP BY cust_id
  HAVING COUNT(DISTINCT loan_month) = (@end_month - @start_month + 1)
),
ontime_repayments AS (
  SELECT
    l.cust_id,
    ROUND(
      100 * SUM(
        CASE
          WHEN t.max_txn_date <= DATE_ADD(l.due_date, INTERVAL 1 DAY) THEN 1
          ELSE 0
        END
      ) / COUNT(l.loan_doc_id),
      2
    ) AS ontime_repayment_rate,
    SUM(
      CASE
        WHEN t.max_txn_date <= DATE_ADD(l.due_date, INTERVAL 1 DAY) THEN 1
        ELSE 0
      END
    ) AS ontime_settle_count,
    COUNT(l.loan_doc_id) AS total_loan_taken
  FROM loans l
  JOIN (
    SELECT
      loan_doc_id,
      MAX(txn_date) AS max_txn_date
    FROM loan_txns
    WHERE txn_type = 'payment'
      AND DATE(txn_date) <= STR_TO_DATE(CONCAT(@end_month, '30'), '%Y%m%d')
      AND DATE(realization_date) <= STR_TO_DATE(CONCAT(@end_month, '30'), '%Y%m%d')
    GROUP BY loan_doc_id
  ) t ON l.loan_doc_id = t.loan_doc_id
  WHERE
    l.status = 'settled'
    AND l.loan_purpose = 'float_advance'
    AND DATE(l.paid_date) <= STR_TO_DATE(CONCAT(@end_month, '30'), '%Y%m%d')
    AND EXTRACT(YEAR_MONTH FROM l.disbursal_date) BETWEEN @start_month AND @end_month
    AND l.product_id NOT IN (43, 75, 300)
    AND l.status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
    AND l.country_code = @country_code
  GROUP BY l.cust_id
)
SELECT
    o.cust_id `Customer ID`,
    CONCAT_WS(' ', p_cust.first_name, p_cust.middle_name, p_cust.last_name) `Customer Name`,
    p_cust.mobile_num `Customer Mobile Number`,
    b.reg_date `Registration Date`,
    CONCAT_WS(' ', p_rm.first_name, p_rm.middle_name, p_rm.last_name) `RM Name`,
    p_rm.mobile_num `RM Number`,
    o.ontime_settle_count `Total Loan Taken`
FROM ontime_repayments o
JOIN all_month_customers a ON o.cust_id = a.cust_id
JOIN borrowers b ON o.cust_id = b.cust_id
LEFT JOIN persons p_cust ON b.owner_person_id = p_cust.id
LEFT JOIN persons p_rm   ON b.flow_rel_mgr_id = p_rm.id
WHERE o.ontime_repayment_rate = 100
ORDER BY o.cust_id;