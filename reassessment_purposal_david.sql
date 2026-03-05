SET @month = 202601;
SET @country_code = 'RWA';
SET @last_day = CONCAT(LAST_DAY(DATE(CONCAT(@month,'01'))), ' 23:59:59');

SET @closure_date = (
    SELECT closure_date 
    FROM flow_api.closure_date_records 
    WHERE status = 'enabled' 
      AND month = @month 
      AND country_code = @country_code
);

WITH active_cust AS (
    SELECT DISTINCT
        l.cust_id AS cust_id,
        b.last_assessment_date AS last_assessment
    FROM loans l
    JOIN loan_txns t ON l.loan_doc_id = t.loan_doc_id
    JOIN borrowers b ON b.cust_id = l.cust_id
    LEFT JOIN (
        SELECT DISTINCT r1.record_code
        FROM record_audits r1
        JOIN (
            SELECT record_code, MAX(id) AS id
            FROM record_audits
            WHERE created_at <= @last_day
            GROUP BY record_code
        ) r2 ON r1.id = r2.id
        WHERE JSON_EXTRACT(r1.data_after, '$.status') = 'disabled'
    ) disabled_cust ON l.cust_id = disabled_cust.record_code
    WHERE DATEDIFF(@last_day, t.txn_date) <= 30
      AND t.txn_date <= @last_day
      AND l.country_code = @country_code
      AND t.txn_type = 'disbursal'
      AND l.loan_purpose = 'float_advance'
      AND l.product_id NOT IN (43, 75, 300)
      AND l.status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
      AND disabled_cust.record_code IS NULL
),

loan_principal AS (
    SELECT 
        l.loan_doc_id,
        l.cust_id,
        l.loan_principal
    FROM loans l
    JOIN loan_txns lt ON lt.loan_doc_id = l.loan_doc_id
    WHERE lt.txn_type = 'disbursal'
      AND lt.realization_date <= @closure_date
      AND l.country_code = @country_code
      AND l.loan_purpose = 'float_advance'
      AND DATE(l.disbursal_date) <= @last_day
      AND l.product_id NOT IN (43, 75, 300)
      AND l.status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
      AND l.loan_doc_id NOT IN (
            SELECT loan_doc_id 
            FROM loan_write_off 
            WHERE write_off_date <= @last_day 
              AND write_off_status IN ('approved', 'partially_recovered', 'recovered') 
              AND country_code = @country_code
      )
),

loan_payments AS (
    SELECT 
        loan_doc_id,
        SUM(CASE WHEN txn_type = 'payment' THEN principal ELSE 0 END) AS total_paid_principal
    FROM loan_txns
    WHERE DATE(txn_date) <= @last_day
      AND realization_date <= @closure_date
    GROUP BY loan_doc_id
),

loan_os AS (
    SELECT
        lp.loan_doc_id,
        lp.cust_id,
        GREATEST(lp.loan_principal - COALESCE(p.total_paid_principal,0),0) AS os_principal
    FROM loan_principal lp
    LEFT JOIN loan_payments p ON p.loan_doc_id = lp.loan_doc_id
    WHERE lp.cust_id IN (SELECT cust_id FROM active_cust)
),

customer_os AS (
    SELECT
        c.cust_id,
        c.last_assessment,
        SUM(os.os_principal) AS total_os_principal
    FROM active_cust c
    LEFT JOIN loan_os os ON os.cust_id = c.cust_id
    GROUP BY c.cust_id, c.last_assessment
)

SELECT
    'Last assessment < 3 months' AS assessment_condition,
    COUNT(*) AS customer_count,
    SUM(total_os_principal) AS total_os
FROM customer_os
WHERE last_assessment < DATE_SUB(@last_day, INTERVAL 3 MONTH)

UNION ALL

SELECT
    'Last assessment < 6 months',
    COUNT(*),
    SUM(total_os_principal)
FROM customer_os
WHERE last_assessment < DATE_SUB(@last_day, INTERVAL 6 MONTH)

UNION ALL

SELECT
    'Last assessment 1-2 years',
    COUNT(*),
    SUM(total_os_principal)
FROM customer_os
WHERE last_assessment BETWEEN DATE_SUB(@last_day, INTERVAL 2 YEAR) 
                          AND DATE_SUB(@last_day, INTERVAL 1 YEAR)

UNION ALL

SELECT
    'Last assessment < 2 years',
    COUNT(*),
    SUM(total_os_principal)
FROM customer_os
WHERE last_assessment < DATE_SUB(@last_day, INTERVAL 2 YEAR);

-- https://docs.google.com/spreadsheets/d/1XGwOj08S6nx-JBP-8AmFV8B5BAbIYQOFzh3wa_PGRCU/edit?usp=sharing