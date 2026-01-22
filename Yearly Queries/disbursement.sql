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
    loan_purpose,
    COUNT(1) loan_count,
    COUNT(DISTINCT cust_id) customer_count,
    SUM(loan_principal) disbursal_amount,
    MIN(loan_principal) min_loan_principal,
    MAX(loan_principal) max_loan_principal,
    AVG(loan_principal) avg_loan_principal
FROM loans l
JOIN loan_txns t 
    ON l.loan_doc_id = t.loan_doc_id
WHERE 
    l.status NOT IN ('voided','hold','pending_disbursal','pending_mnl_dsbrsl')
    AND l.product_id NOT IN (43,75,300)
    AND t.txn_type in ('disbursal', 'af_disbursal')
    AND (
        (YEAR(t.txn_date) = @year 
            AND t.realization_date <= @closure_date)
        OR 
        (YEAR(t.txn_date) < @year
            AND t.realization_date > @prev_closure_date
            AND t.realization_date <= @closure_date)
    )
    AND l.country_code = @country_code
GROUP BY loan_purpose;