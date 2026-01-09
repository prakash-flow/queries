-- =========================
-- CONFIGURATION VARIABLES
-- =========================
SET @report_date = '2024-12-31';
SET @month = '202412';
SET @country_code = 'RWA';

-- =========================
-- DATES & CLOSURE REFERENCE
-- =========================
SET @last_day = LAST_DAY(DATE(CONCAT(@month, '01')));
SET @realization_date = (
  SELECT closure_date 
  FROM closure_date_records 
  WHERE country_code = @country_code 
    AND month = @month 
    AND status = 'enabled'
);

-- =========================
-- PORTFOLIO CATEGORY CONTROL
-- =========================

-- SET @having_condition = 'BETWEEN 1 AND 89';    -- Watch
-- SET @having_condition = 'BETWEEN 90 AND 179';  -- Substandard
-- SET @having_condition = 'BETWEEN 180 AND 359'; -- Doubtful
SET @having_condition = 'BETWEEN 360 AND 719';    -- Loss

-- =========================
-- DEBUG CHECK
-- =========================
SELECT 
  @last_day AS last_day, 
  @realization_date AS realization_date, 
  @country_code AS country_code, 
  @month AS month, 
  @report_date AS report_date, 
  @having_condition AS having_condition;

-- =========================
-- MAIN QUERY CONSTRUCTION
-- =========================
SET @query = CONCAT("
WITH disbursals AS (
  SELECT
    lt.loan_doc_id,
    l.cust_id,
    l.acc_prvdr_code,
    l.acc_number,
    l.cust_name,
    l.cust_mobile_num,
    l.flow_rel_mgr_name,
    l.product_name,
    l.disbursal_date,
    l.due_date,
    l.overdue_days,
    l.status,
    l.paid_date,
    SUM(lt.amount) AS loan_principal,
    l.flow_fee AS fee
  FROM loans l
  JOIN loan_txns lt ON lt.loan_doc_id = l.loan_doc_id
  WHERE lt.txn_type = 'disbursal'
    AND lt.realization_date <= '", @realization_date, "'
    AND l.country_code = '", @country_code, "'
    AND DATE(l.disbursal_date) <= '", @last_day, "'
    AND l.product_id NOT IN (43, 75, 300)
    AND l.status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
    AND l.loan_doc_id NOT IN (
      SELECT loan_doc_id
      FROM loan_write_off
      WHERE country_code = '", @country_code, "'
        AND DATE(write_off_date) <= '", @last_day, "'
        AND write_off_status IN ('approved', 'partially_recovered', 'recovered')
    )
  GROUP BY lt.loan_doc_id
),

payments AS (
  SELECT
    l.loan_doc_id,
    SUM(t.orincipal) AS partial_pay
  FROM loans l
  JOIN loan_txns t ON l.loan_doc_id = t.loan_doc_id
  WHERE t.txn_type = 'payment'
    AND t.realization_date <= '", @realization_date, "'
    AND DATE(t.txn_date) <= '", @last_day, "'
    AND l.country_code = '", @country_code, "'
    AND DATE(l.disbursal_date) <= '", @last_day, "'
    AND l.product_id NOT IN (43, 75, 300)
    AND l.status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
    AND l.loan_doc_id NOT IN (
      SELECT loan_doc_id
      FROM loan_write_off
      WHERE country_code = '", @country_code, "'
        AND DATE(write_off_date) <= '", @last_day, "'
        AND write_off_status IN ('approved', 'partially_recovered', 'recovered')
    )
  GROUP BY l.loan_doc_id
),

cust_info AS (
  SELECT
    b.cust_id,
    p.gender,
    p.dob,
    a.field_2,
    a.field_3,
    a.field_4,
    a.field_5
  FROM borrowers b
  JOIN persons p ON p.id = b.owner_person_id
  JOIN address_info a ON a.id = b.owner_address_id
),

prev_loan_due AS (
  SELECT
    loan_doc_id,
    cust_id,
    disbursal_date,
    due_date AS current_due_date,
    LAG(loan_doc_id) OVER (PARTITION BY cust_id ORDER BY disbursal_date) AS prev_loan_doc_id,
    LAG(due_date) OVER (PARTITION BY cust_id ORDER BY disbursal_date) AS prev_due_date,
    LAG(paid_date) OVER (PARTITION BY cust_id ORDER BY disbursal_date) AS prev_paid_date
  FROM disbursals
),

is_ontime AS (
  SELECT
    loan_doc_id,
    CASE
      WHEN prev_due_date IS NULL AND prev_paid_date IS NULL THEN 'yes'
      WHEN prev_paid_date IS NOT NULL AND DATEDIFF(prev_paid_date, prev_due_date) = 0 THEN 'yes'
      ELSE 'no'
    END AS is_ontime_repaid,
    current_due_date
  FROM prev_loan_due
)

SELECT
  d.cust_name,
  d.cust_id,
  d.cust_mobile_num,
  COALESCE(ci.gender, '') AS gender,
  TIMESTAMPDIFF(YEAR, ci.dob, '", @last_day, "') AS age,
  'Customer' AS relationship,
  '' AS marital_status,
  COALESCE(io.is_ontime_repaid, 'no') AS is_ontime_repaid,
  'Growing Mobile Money Business' AS purpose_of_loan,
  '' AS branch_name,
  '' AS collateral_type,
  '' AS collateral_amt,
  ci.field_2 AS district,
  ci.field_3 AS sector,
  ci.field_4 AS cell,
  ci.field_5 AS village,
  '' AS annual_interest,
  'Flat' AS interest_rate,
  d.flow_rel_mgr_name,
  d.loan_principal AS principal,
  d.disbursal_date,
  d.due_date,
  '' AS empty1,
  '' AS empty2,
  '' AS empty3,
  '' AS empty4,
  DATE_ADD(d.due_date, INTERVAL 1 DAY) AS arrear_start,
  '", @last_day, "' AS report_date,
  '' AS empty5,
  '' AS empty6,
  '' AS empty7,
  COALESCE(p.partial_pay, 0) AS partial_pay,
  GREATEST(d.loan_principal - COALESCE(p.partial_pay, 0), 0) AS par_loan_principal,
  '' AS empty8,
  GREATEST(d.loan_principal - COALESCE(p.partial_pay, 0), 0) AS net_principal,
  CASE WHEN DATEDIFF('", @last_day, "', d.due_date) < 0 THEN 0 ELSE DATEDIFF('", @last_day, "', d.due_date) END AS od_days
FROM disbursals d
LEFT JOIN payments p ON d.loan_doc_id = p.loan_doc_id
LEFT JOIN cust_info ci ON d.cust_id = ci.cust_id
LEFT JOIN is_ontime io ON d.loan_doc_id = io.loan_doc_id
WHERE
  CASE WHEN DATEDIFF('", @last_day, "', d.due_date) < 0 THEN 0 ELSE DATEDIFF('", @last_day, "', d.due_date) END ", @having_condition, "
  AND GREATEST(d.loan_principal - COALESCE(p.partial_pay, 0), 0) > 0;
");

-- =========================
-- EXECUTION
-- =========================
SELECT @query; 

PREPARE stmt FROM @query;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;