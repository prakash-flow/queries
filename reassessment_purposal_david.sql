SET @month = 202601;
SET @country_code = 'UGA';

SELECT IF(@country_code = 'UGA', 'UGX', 'RWF') INTO @currency;

SET @last_day = CONCAT(LAST_DAY(DATE(CONCAT(@month, '01'))), ' 23:59:59');

SET @closure_date = (
    SELECT closure_date 
    FROM flow_api.closure_date_records 
    WHERE status = 'enabled' 
      AND month = @month 
      AND country_code = @country_code
);

SELECT @currency, @month, @prev_month, @last_day, @closure_date;

WITH acc_last_assess AS (
    SELECT 
        cust_id,
        MAX(last_assessment_date) AS acc_last_assessment_date
    FROM accounts
    WHERE country_code = @country_code
      AND created_at <= @last_day
      AND is_removed = 0
    GROUP BY cust_id
),

active_cust AS (
    SELECT DISTINCT
        l.cust_id AS cust_id,
        COALESCE(
            b.last_assessment_date,
            a.acc_last_assessment_date
        ) AS effective_last_assessment_date
    FROM loans l
    JOIN loan_txns t 
        ON l.loan_doc_id = t.loan_doc_id
    JOIN borrowers b 
        ON b.cust_id = l.cust_id
    LEFT JOIN acc_last_assess a 
        ON a.cust_id = l.cust_id
    LEFT JOIN (
        SELECT DISTINCT
            r1.record_code
        FROM record_audits r1
        JOIN (
            SELECT
                record_code,
                MAX(id) AS id
            FROM record_audits
            WHERE created_at <= @last_day
            GROUP BY record_code
        ) r2 ON r1.id = r2.id
        WHERE JSON_EXTRACT(r1.data_after, '$.status') = 'disabled'
    ) disabled_cust 
        ON l.cust_id = disabled_cust.record_code
    WHERE
        DATEDIFF(@last_day, t.txn_date) <= 30
        AND t.txn_date <= @last_day
        AND l.country_code = @country_code
        AND t.txn_type = 'disbursal'
        AND l.loan_purpose = 'float_advance'
        AND l.product_id NOT IN (43, 75, 300)
        AND l.status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
        AND disabled_cust.record_code IS NULL

        -- Assessment logic
        AND COALESCE(b.last_assessment_date, a.acc_last_assessment_date)
            < DATE_SUB(@last_day, INTERVAL 3 MONTH)

        -- AND COALESCE(b.last_assessment_date, a.acc_last_assessment_date)
        --     < DATE_SUB(@last_day, INTERVAL 6 MONTH)

        -- AND COALESCE(b.last_assessment_date, a.acc_last_assessment_date)
        --     BETWEEN DATE_SUB(@last_day, INTERVAL 2 YEAR)
        --         AND DATE_SUB(@last_day, INTERVAL 1 YEAR)

        -- AND COALESCE(b.last_assessment_date, a.acc_last_assessment_date)
        --     < DATE_SUB(@last_day, INTERVAL 2 YEAR)
)

SELECT * FROM active_cust;

-- https://docs.google.com/spreadsheets/d/1XGwOj08S6nx-JBP-8AmFV8B5BAbIYQOFzh3wa_PGRCU/edit?usp=sharing