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

last_payment AS (
    SELECT loan_doc_id, amount, txn_date
    FROM (
        SELECT 
            lt.loan_doc_id,
            lt.amount,
            lt.txn_date,
            ROW_NUMBER() OVER (
                PARTITION BY lt.loan_doc_id
                ORDER BY lt.txn_date DESC
            ) rn
        FROM loan_txns lt
        JOIN os_query os ON os.loan_doc_id = lt.loan_doc_id
        WHERE lt.txn_type = 'payment'
          AND lt.country_code = @country_code
          AND lt.txn_date <= @last_date_with_time
    ) x
    WHERE rn = 1
),

last_visit AS (
    SELECT *
    FROM (
        SELECT 
            fv.cust_id,
            fv.visitor_id,
            fv.visit_end_time,
            fv.type,
            fv.remarks,
            ROW_NUMBER() OVER (
                PARTITION BY fv.cust_id
                ORDER BY fv.visit_start_time DESC
            ) rn
        FROM field_visits fv
        WHERE fv.sch_status = 'checked_out'
          AND fv.country_code = @country_code
    ) t
    WHERE rn = 1
)

-- latest_calls AS (
--     SELECT *
--     FROM (
--         SELECT 
--             c.cust_id,
--             c.call_logger_id,
--             c.call_logger_name,
--             c.call_purpose,
--             c.remarks AS log_remarks,
--             c.call_end_time,
--             l.flow_rel_mgr_id,
--             CASE 
--                 WHEN c.call_logger_id = l.flow_rel_mgr_id THEN 'RM'
--                 ELSE 'OTHER'
--             END AS caller_type,
--             ROW_NUMBER() OVER (
--                 PARTITION BY c.cust_id
--                 ORDER BY c.created_at DESC
--             ) rn
--         FROM call_logs c
--         JOIN loans l ON l.cust_id = c.cust_id
--     ) x
--     WHERE rn = 1
-- ),

-- rm_call_logs as (
--   select * from latest_calls where caller_type =' RM'
-- ),
-- other_call_logs as ( select * from latest_calls where caller_type =' OTHER')

SELECT 
    p.full_name AS `Customer Name`,
    l.cust_id AS `Customer ID`,
    a.field_2 AS `District`,
    a.field_8 AS `Location`,
    os.loan_doc_id AS `Loan Doc ID`,
    os.loan_purpose AS `Loan Purpose`,
    p.national_id AS `Client National ID`,
    p.mobile_num AS `Client Primary Mobile No`,
    os.disbursal_date AS `Disbursal Date`,
    os.loan_principal AS `Disbursal Amount`,
    os.flow_fee AS `Fees`,
    os.due_date AS `Due Date`,
    lp.txn_date AS `Last Paid Date`,
    lp.amount AS `Last Paid Amount`,
    os.principal_os AS `Principal OS`,
    os.fee_os AS `Fee OS`,
    IF(os.dpd <= 0,0,os.dpd) AS `Overdue Days`,
    CASE when dpd = 1 THen '1 day'
          When dpd between 2 and 5 Then '2-5 days'
          When dpd between 6 and 15 Then '6-15 days'
          When dpd between 16 and 30 Then '16-30 days'
          When dpd between 31 and 90 Then '31-90 days'
          When dpd > 90 Then 'above 90 days' 
      END AS `Arrear Bucket`,
    l.status AS `Status`,
    rm.full_name AS `RM Name`,
    rm.id AS `RM ID`,
    IFNULL(tm.full_name,rm.full_name) AS `TM Name`,
    lv.visit_end_time AS `Last RM Visit Date`,
    lv.type AS `Last RM Visit Type`,
    lv.remarks AS `Last RM Visit Remarks`,
    lw.appr_date AS `Write Off Approved`,
    lw.write_off_date AS `Write Off Date`
    -- rc.call_logger_name  AS `RMS Call Person`,
    -- rc.call_end_time  AS `Last RMS Call Date`,
    -- rc.call_purpose  AS `RMS Call Reason`,
    -- rc.log_remarks  AS `RMS Call Remarks`,
    -- oc.call_logger_name  AS `Other Call Person`,
    -- oc.call_end_time  AS `Last Other Call Date`,
    -- oc.call_purpose  AS `Other Call Reason`,
    -- oc.log_remarks  AS `Other Call Remarks`

FROM os_query os
JOIN loans l ON l.loan_doc_id = os.loan_doc_id
JOIN borrowers b ON b.cust_id = l.cust_id
LEFT JOIN loan_write_off lw ON lw.loan_doc_id = os.loan_doc_id
LEFT JOIN address_info a ON b.owner_address_id = a.id
LEFT JOIN persons p ON b.owner_person_id = p.id
LEFT JOIN persons rm ON rm.id = os.flow_rel_mgr_id
LEFT JOIN persons tm ON tm.id = rm.report_to
LEFT JOIN last_payment lp ON lp.loan_doc_id = os.loan_doc_id
LEFT JOIN last_visit lv ON lv.cust_id = l.cust_id
-- LEFT JOIN rm_call_logs rc ON rc.cust_id = l.cust_id
-- LEFT JOIN other_call_logs oc ON rc.cust_id = l.cust_id

ORDER BY os.dpd DESC;