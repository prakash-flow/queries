SET @month = '202602';
SET @country_code = 'UGA';

SET @last_day = LAST_DAY(STR_TO_DATE(CONCAT(@month,'01'),'%Y%m%d'));
SET @last_date_with_time = CONCAT(@last_day,' 23:59:59');

SET @realization_date = (
    SELECT COALESCE(MAX(closure_date), @last_date_with_time)
    FROM closure_date_records
    WHERE month = @month
      AND status = 'enabled'
      AND country_code = @country_code
);

WITH base_loans AS (
    SELECT 
        l.loan_doc_id,
        l.loan_purpose,
        l.due_date,
        l.loan_principal,
        l.flow_fee,
        l.cust_id,
        l.flow_rel_mgr_id,
        l.disbursal_date
    FROM loans l
    WHERE l.country_code = @country_code
      AND l.status NOT IN ('voided','hold','pending_disbursal','pending_mnl_dsbrsl')
      AND EXISTS (
            SELECT 1
            FROM loan_txns lt
            WHERE lt.loan_doc_id = l.loan_doc_id
              AND lt.txn_type = 'disbursal'
              AND lt.txn_date <= @last_date_with_time
              AND lt.realization_date <= @realization_date
      )
      AND NOT EXISTS (
            SELECT 1
            FROM loan_products lp
            WHERE lp.id = l.product_id
              AND lp.product_type = 'float_vending'
      )
),

payments AS (
    SELECT 
        loan_doc_id,
        SUM(CASE WHEN txn_type = 'payment' THEN principal ELSE 0 END) AS principal_paid,
        SUM(CASE WHEN txn_type IN ('payment','fee_waiver') THEN fee ELSE 0 END) AS fee_paid
    FROM loan_txns
    WHERE country_code = @country_code
      AND txn_date <= @last_date_with_time
      AND realization_date <= @realization_date
      AND txn_type IN ('payment','fee_waiver')
    GROUP BY loan_doc_id
),

os_query AS (
    SELECT 
        b.*,
        GREATEST(b.loan_principal - IFNULL(p.principal_paid,0),0) AS principal_os,
        GREATEST(b.flow_fee - IFNULL(p.fee_paid,0),0) AS fee_os,
        DATEDIFF(@last_day, b.due_date) AS dpd
    FROM base_loans b
    LEFT JOIN payments p ON p.loan_doc_id = b.loan_doc_id
    WHERE (b.loan_principal - IFNULL(p.principal_paid,0) > 0
        OR b.flow_fee - IFNULL(p.fee_paid,0) > 0)
),

latest_calls AS (
    SELECT *
    FROM (
        SELECT 
            c.cust_id,
            c.call_logger_id,
            c.call_logger_name,
            c.call_purpose,
            c.remarks AS log_remarks,
            c.call_end_time,
            ROW_NUMBER() OVER (
                PARTITION BY c.cust_id
                ORDER BY c.created_at DESC
            ) rn
        FROM os_query os
        join call_logs c on os.cust_id = c.cust_id and c.call_logger_id != os.flow_rel_mgr_id
 
    ) x
    WHERE rn = 1
)

select * from latest_calls








