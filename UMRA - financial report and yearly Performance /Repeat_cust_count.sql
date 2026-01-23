
SET @country_code = 'RWA';
SET @month = '202510';

SET @pre_month = DATE_FORMAT(
    DATE_SUB(STR_TO_DATE(CONCAT(@month, '01'), '%Y%m%d'), INTERVAL 1 MONTH),
    '%Y%m'
);

SET @start_date     = CONCAT(@month, '01 00:00:00');
SET @last_day       = CONCAT(LAST_DAY(CONCAT(@month, '01')), ' 23:59:59');

SET @pre_start_date = CONCAT(@pre_month, '01 00:00:00');
SET @pre_last_day   = CONCAT(LAST_DAY(CONCAT(@pre_month, '01')), ' 23:59:59');

SET @realization_date = IFNULL(
    (
        SELECT closure_date
        FROM closure_date_records
        WHERE month = @month
          AND status = 'enabled'
          AND country_code = @country_code
        LIMIT 1
    ),
    @last_day
);

SET @pre_realization_date = (
    SELECT closure_date
    FROM closure_date_records
    WHERE month = @pre_month
      AND status = 'enabled'
      AND country_code = @country_code
    LIMIT 1
);

SET @loan_purpose = 'growth_financing'


WITH latest_record_audits AS (
    SELECT r1.record_code,
           JSON_UNQUOTE(JSON_EXTRACT(r1.data_after, '$.status')) AS status
    FROM record_audits r1
    JOIN (
        SELECT record_code, MAX(id) AS id
        FROM record_audits
        WHERE created_at <= @last_day
        GROUP BY record_code
    ) r2 ON r1.id = r2.id
),
par_latest_record_audits AS (
    SELECT r1.record_code,
           JSON_UNQUOTE(JSON_EXTRACT(r1.data_after, '$.status')) AS status
    FROM record_audits r1
    JOIN (
        SELECT record_code, MAX(id) AS id
        FROM record_audits
        WHERE created_at <= @pre_last_day
        GROUP BY record_code
    ) r2 ON r1.id = r2.id
),

pre_active_customers AS (
    SELECT DISTINCT b.cust_id
    FROM borrowers b
    JOIN loans l       ON b.cust_id = l.cust_id
    JOIN loan_txns t   ON l.loan_doc_id = t.loan_doc_id
    WHERE b.country_code = @country_code
      AND t.txn_type IN ('disbursal','af_disbursal')
      AND t.txn_date BETWEEN DATE_SUB(@pre_last_day, INTERVAL 30 DAY) AND @pre_last_day
      AND l.product_id NOT IN (43,75,300)
      AND l.status NOT IN ('voided','hold','pending_disbursal','pending_mnl_dsbrsl')
      AND l.loan_purpose in (@loan_purpose)
      AND NOT EXISTS (
            SELECT 1
            FROM par_latest_record_audits ra
            WHERE ra.record_code = b.cust_id
              AND ra.status = 'disabled'
      )
)

SELECT
    l.loan_purpose,
    COUNT(DISTINCT b.cust_id) AS repeat_cust_count
FROM borrowers b
JOIN loans l     ON b.cust_id = l.cust_id
JOIN loan_txns t ON l.loan_doc_id = t.loan_doc_id
WHERE b.country_code = @country_code
  AND t.txn_type IN ('disbursal','af_disbursal')
  AND t.txn_date BETWEEN DATE_SUB(@last_day, INTERVAL 30 DAY) AND @last_day
  AND l.product_id NOT IN (43,75,300)
  AND l.status NOT IN ('voided','hold','pending_disbursal','pending_mnl_dsbrsl')
  AND l.loan_purpose in (@loan_purpose)
  AND EXISTS (
        SELECT 1
        FROM pre_active_customers p
        WHERE p.cust_id = b.cust_id
  )
  AND NOT EXISTS (
        SELECT 1
        FROM latest_record_audits ra
        WHERE ra.record_code = b.cust_id
          AND ra.status = 'disabled'
  )
GROUP BY l.loan_purpose;




//year query

-- select l.loan_purpose, count(distinct b.cust_id) from borrowers b join loans l on l.cust_id = b.cust_id where 
--   -- reg_date > '2024-12-31'
--   -- and 
--   reg_date <= '2024-12-31'
--   and l.country_code = 'UGA' AND l.product_id NOT IN (43,75,300)
--   and l.cust_id in (select distinct b.cust_id from borrowers b join loans l on l.cust_id = b.cust_id where reg_date <= '2024-12-31' and l.loan_purpose = 'adj_float_advance' and l.country_code = 'UGA' AND l.product_id NOT IN (43,75,300)
-- AND l.status NOT IN ('voided','hold','pending_disbursal','pending_mnl_dsbrsl') and date(disbursal_date) <= '2024-12-31') 
-- AND l.status NOT IN ('voided','hold','pending_disbursal','pending_mnl_dsbrsl') and date(disbursal_date) <= '2025-12-31' and date(disbursal_date) > '2024-12-31' and l.loan_purpose = 'adj_float_advance' group by l.loan_purpose ;