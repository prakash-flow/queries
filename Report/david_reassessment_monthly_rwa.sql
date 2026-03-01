SET @month = '202503';
SET @last_day = LAST_DAY(DATE(CONCAT(@month, '01')));
SET @country_code = 'RWA';

SET @prev_month = (
  SELECT DATE_FORMAT(
    DATE_SUB(STR_TO_DATE(CONCAT(@month, '01'), '%Y%m%d'), INTERVAL 1 MONTH),
    '%Y%m'
  )
);

WITH
-- Active Customers
reassessment_accounts AS (
    WITH active_cust AS (
        SELECT DISTINCT l.cust_id
        FROM loans l
        JOIN loan_txns t ON l.loan_doc_id = t.loan_doc_id
        WHERE DATEDIFF(@last_day, t.txn_date) <= 30
          AND DATE(t.txn_date) <= @last_day
          AND l.country_code = @country_code
          AND l.loan_purpose = 'float_advance'
          AND t.txn_type = 'disbursal'
          AND l.product_id NOT IN (43,75,300)
          AND l.status NOT IN ('voided','hold','pending_disbursal','pending_mnl_dsbrsl')
    )
    SELECT 
        @month month,
        a.id account_id,
        a.cust_id,
        a.acc_number,
        a.alt_acc_num,
        a.acc_prvdr_code,
        a.is_primary_acc,
        COALESCE(a.acc_purpose, JSON_ARRAY()) acc_purpose,
        COALESCE(a.cust_score_factors, JSON_ARRAY()) cust_score_factors,
        IFNULL(jt.g_val,0) monthly_comms,
        a.acc_ownership,
        COALESCE(a.conditions, JSON_ARRAY()) conditions
    FROM accounts a
    JOIN active_cust e ON a.cust_id = e.cust_id
    LEFT JOIN JSON_TABLE(
        a.cust_score_factors,
        "$[*]" COLUMNS (
            csf_type VARCHAR(50) PATH "$.csf_type",
            g_val BIGINT PATH "$.g_val"
        )
    ) jt ON jt.csf_type = 'monthly_comms'
    WHERE a.country_code = @country_code
      AND a.acc_prvdr_code = 'RMTN'
      AND a.status = 'enabled'
      AND a.is_removed = 0
      AND EXTRACT(YEAR_MONTH FROM a.created_at) <= @month
),

-- Customers
customers AS (
    SELECT
        b.cust_id,
        b.owner_person_id,
        b.reg_date,
        a.field_1 region
    FROM borrowers b
    LEFT JOIN address_info a ON a.id = b.owner_address_id
    WHERE b.cust_id IN (SELECT cust_id FROM reassessment_accounts)
      AND b.country_code = @country_code
),

customers_with_name AS (
    SELECT
        c.*,
        CONCAT_WS(' ',p.first_name,p.middle_name,p.last_name) customer_name
    FROM customers c
    LEFT JOIN persons p ON p.id = c.owner_person_id
),

-- Commission Data
commission_data AS (
    SELECT
        identifier,
        MAX(CASE WHEN month = @month THEN distributor_code END) distributor_code,
        CAST(IFNULL((
            MAX(IF(month = DATE_FORMAT(DATE_SUB(DATE(CONCAT(@month,'01')),INTERVAL 2 MONTH),'%Y%m'), commission,0)) +
            MAX(IF(month = DATE_FORMAT(DATE_SUB(DATE(CONCAT(@month,'01')),INTERVAL 1 MONTH),'%Y%m'), commission,0)) +
            MAX(IF(month = @month, commission,0))
        )/3,0) AS UNSIGNED) avg_comms
    FROM cust_commissions
    WHERE identifier IN (SELECT acc_number FROM reassessment_accounts)
    GROUP BY identifier
),

account_comms AS (
    SELECT
        r.cust_id,
        r.account_id,
        COALESCE(c.avg_comms, r.monthly_comms, 0) monthly_comms,
        c.distributor_code
    FROM reassessment_accounts r
    LEFT JOIN commission_data c ON c.identifier = r.acc_number
),

-- Account level assessment (RWA slabs)
account_assessment_cte AS (
  SELECT
    cust_id,
    account_id,
    distributor_code,
    monthly_comms,
    CASE
      WHEN monthly_comms < 15000 THEN 0
      WHEN monthly_comms BETWEEN 15000 AND 24999 THEN 70000
      WHEN monthly_comms BETWEEN 25000 AND 34999 THEN 100000
      WHEN monthly_comms BETWEEN 35000 AND 49999 THEN 150000
      WHEN monthly_comms BETWEEN 50000 AND 69999 THEN 200000
      WHEN monthly_comms BETWEEN 70000 AND 89999 THEN 300000
      WHEN monthly_comms BETWEEN 90000 AND 109999 THEN 400000
      WHEN monthly_comms BETWEEN 110000 AND 129999 THEN 500000
      WHEN monthly_comms BETWEEN 130000 AND 149999 THEN 600000
      WHEN monthly_comms BETWEEN 150000 AND 169999 THEN 700000
      WHEN monthly_comms BETWEEN 170000 AND 189999 THEN 800000
      WHEN monthly_comms BETWEEN 190000 AND 209999 THEN 900000
      WHEN monthly_comms BETWEEN 210000 AND 299999 THEN 1000000
      WHEN monthly_comms BETWEEN 300000 AND 399999 THEN 1500000
      WHEN monthly_comms BETWEEN 400000 AND 499999 THEN 2000000
      WHEN monthly_comms BETWEEN 500000 AND 749999 THEN 2500000
      WHEN monthly_comms >= 750000 THEN 3000000
      ELSE 0
    END account_limit
  FROM account_comms
),

-- Customer final = MAX account limit + its distributor
assessment_limit_cte AS (
  SELECT
      cust_id,
      SUBSTRING_INDEX(
          GROUP_CONCAT(distributor_code ORDER BY account_limit DESC),
          ',', 1
      ) distributor_code,
      MAX(account_limit) assessment_limit
  FROM account_assessment_cte
  GROUP BY cust_id
),

loan_records AS (
    SELECT *
    FROM (
        SELECT
            l.cust_id,
            l.loan_doc_id,
            l.loan_principal,
            l.status last_loan_status,
            l.disbursal_date,
            l.paid_date,
            l.due_date,
            ROW_NUMBER() OVER(PARTITION BY l.cust_id ORDER BY l.disbursal_date DESC) rn
        FROM loans l
        WHERE DATE(l.disbursal_date) <= @last_day
          AND l.cust_id IN (SELECT cust_id FROM reassessment_accounts)
          AND l.loan_purpose='float_advance'
          AND l.product_id NOT IN (43,75,300)
          AND l.status NOT IN ('voided','hold','pending_disbursal','pending_mnl_dsbrsl')
    ) x WHERE rn=1
),

loan_txn AS (
    SELECT l.loan_doc_id,
           COUNT(CASE WHEN DATEDIFF(lt.txn_date,l.due_date) > 1 THEN 1 END) late_payment_count
    FROM loans l
    JOIN loan_txns lt ON l.loan_doc_id = lt.loan_doc_id
    WHERE lt.txn_type='payment'
      AND DATE(lt.txn_date) <= @last_day
    GROUP BY l.loan_doc_id
),

par_loans AS (
    SELECT cust_id,
           COUNT(*) par_5
    FROM loans
    WHERE DATEDIFF(@last_day, due_date) > 5
      AND (paid_date IS NULL OR DATEDIFF(paid_date,due_date) > 5)
      AND loan_purpose='float_advance'
    GROUP BY cust_id
),

total_loans AS (
    SELECT cust_id, COUNT(*) total_loan
    FROM loans
    WHERE EXTRACT(YEAR_MONTH FROM disbursal_date) <= @month
      AND loan_purpose='float_advance'
    GROUP BY cust_id
),

actual_limit_cte AS (
    SELECT cust_id, MAX(limit_value) actual_limit
    FROM (
        SELECT a.cust_id, jt.limit_value
        FROM accounts a
        JOIN JSON_TABLE(a.conditions,'$[*]' COLUMNS(limit_value INT PATH '$.limit')) jt
        WHERE a.country_code=@country_code
    ) x
    GROUP BY cust_id
),

ontime_repayment AS (
    SELECT
        l.cust_id,
        ROUND(
            100 * SUM(CASE WHEN t.max_txn_date <= DATE_ADD(l.due_date,INTERVAL 1 DAY) THEN 1 ELSE 0 END)
            / COUNT(*),
            2
        ) ontime_repayment_rate
    FROM loans l
    JOIN (
        SELECT loan_doc_id, MAX(txn_date) max_txn_date
        FROM loan_txns
        WHERE txn_type='payment'
        GROUP BY loan_doc_id
    ) t ON l.loan_doc_id=t.loan_doc_id
    WHERE l.status='settled'
      AND DATE(l.paid_date)<=@last_day
      AND l.loan_purpose='float_advance'
      AND l.country_code=@country_code
    GROUP BY l.cust_id
)

SELECT
  c.cust_id AS `Customer ID`,
  c.customer_name AS `Customer Name`,
  c.reg_date AS `Registration Date`,
  COALESCE(tl.total_loan,0) AS `Total Loan Count`,
  IFNULL(alcte.actual_limit,0) AS `Actual Limit`,
  IF(al.assessment_limit=0,'Ineligible',al.assessment_limit) AS `Reassessed Limit`,
  al.distributor_code AS `Distributor Code`,
  lr.loan_principal AS `Last Loan Amount`,
  lr.last_loan_status AS `Last Loan Status`,
  CASE WHEN lr.last_loan_status='overdue' THEN DATEDIFF(@last_day,lr.due_date) ELSE 0 END AS `Overdue Days`,
  COALESCE(lt.late_payment_count,0) AS `Late Repayments`,
  COALESCE(pl.par_5,0) AS `PAR >5 Count`,
  c.region AS `Region`,
  CONCAT(COALESCE(orr.ontime_repayment_rate,'0.00'),' %') AS `Ontime Repayment Rate`
FROM customers_with_name c
LEFT JOIN assessment_limit_cte al ON al.cust_id=c.cust_id
LEFT JOIN actual_limit_cte alcte ON alcte.cust_id=c.cust_id
LEFT JOIN loan_records lr ON lr.cust_id=c.cust_id
LEFT JOIN loan_txn lt ON lt.loan_doc_id=lr.loan_doc_id
LEFT JOIN par_loans pl ON pl.cust_id=c.cust_id
LEFT JOIN total_loans tl ON tl.cust_id=c.cust_id
LEFT JOIN ontime_repayment orr ON orr.cust_id=c.cust_id
ORDER BY c.cust_id;