SET @year = 2025;
SET @country_code = 'RWA';

SET @month = CONCAT(@year, '12');

SET @prev_year = @year - 1;
SET @prev_month = CONCAT(@prev_year, '12');

SET @last_day = LAST_DAY(DATE(CONCAT(@month, '01')));

SET @closure_date = (
    SELECT closure_date
    FROM flow_api.closure_date_records
    WHERE status = 'enabled'
      AND month = @month
      AND country_code = @country_code
);

SET @prev_closure_date = (
    SELECT closure_date
    FROM flow_api.closure_date_records
    WHERE status = 'enabled'
      AND month = @prev_month
      AND country_code = @country_code
);

SELECT
    l.loan_purpose,
    COUNT(DISTINCT l.cust_id) customer_count
FROM loans l
JOIN loan_txns t 
    ON l.loan_doc_id = t.loan_doc_id
WHERE 
    l.status NOT IN ('voided','hold','pending_disbursal','pending_mnl_dsbrsl')
    AND l.product_id NOT IN (43,75,300)
    AND t.txn_type IN ('disbursal', 'af_disbursal')
    AND (
        (YEAR(t.txn_date) = @year 
            AND t.realization_date <= @closure_date)
        OR 
        (YEAR(t.txn_date) < @year
            AND t.realization_date > @prev_closure_date
            AND t.realization_date <= @closure_date)
    )
    AND l.country_code = @country_code

    -- exclude customers who had any loan before 2025
    AND NOT EXISTS (
        SELECT 1
        FROM loans l2
        JOIN loan_txns t2 
            ON l2.loan_doc_id = t2.loan_doc_id
        WHERE l2.cust_id = l.cust_id
          AND l2.status NOT IN ('voided','hold','pending_disbursal','pending_mnl_dsbrsl')
          AND t2.txn_type IN ('disbursal', 'af_disbursal')
          AND YEAR(t2.txn_date) < @year
    )

GROUP BY l.loan_purpose;