SET @month = 202512;
SET @country_code = 'RWA';

SET @prev_month = DATE_FORMAT(DATE_SUB(DATE(CONCAT(@month,'01')), INTERVAL 1 MONTH),'%Y%m');

SET @last_day = LAST_DAY(DATE(CONCAT(@month,'01')));

SET @closure_date = (
    SELECT closure_date
    FROM flow_api.closure_date_records
    WHERE status='enabled'
      AND month=@month
      AND country_code=@country_code
);

SET @prev_closure_date = (
    SELECT closure_date
    FROM flow_api.closure_date_records
    WHERE status='enabled'
      AND month=@prev_month
      AND country_code=@country_code
);

SELECT
    l.loan_purpose,
    COUNT(DISTINCT l.cust_id) `New Customer Acquires`
FROM loans l
JOIN loan_txns t 
    ON l.loan_doc_id = t.loan_doc_id
WHERE 
    l.status NOT IN ('voided','hold','pending_disbursal','pending_mnl_dsbrsl')
    AND l.product_id NOT IN (43,75,300)
    AND t.txn_type IN ('disbursal','af_disbursal')
    AND (
        (EXTRACT(YEAR_MONTH FROM t.txn_date) = @month
            AND t.realization_date <= @closure_date)
        OR 
        (EXTRACT(YEAR_MONTH FROM t.txn_date) < @month
            AND t.realization_date > @prev_closure_date
            AND t.realization_date <= @closure_date)
    )
    AND l.country_code = @country_code

    -- exclude customers who had any loan before this month
    AND NOT EXISTS (
        SELECT 1
        FROM loans l2
        JOIN loan_txns t2 
            ON l2.loan_doc_id = t2.loan_doc_id
        WHERE l2.cust_id = l.cust_id
          AND l2.status NOT IN ('voided','hold','pending_disbursal','pending_mnl_dsbrsl')
          AND t2.txn_type IN ('disbursal','af_disbursal')
          AND EXTRACT(YEAR_MONTH FROM t2.txn_date) < @month
    )

GROUP BY l.loan_purpose;