SET @month = 202411;
SET @country_code = 'UGA';

SET @prev_month = DATE_FORMAT(DATE_SUB(DATE(CONCAT(@month, '01')), INTERVAL 1 MONTH), '%Y%m');
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
	@month,
    p.gender,
    l.country_code,
    SUM(CASE WHEN lw.loan_doc_id IS NULL THEN t.fee ELSE 0 END) AS fee_received,  
    SUM(CASE WHEN lw.loan_doc_id IS NOT NULL THEN t.fee ELSE 0 END) AS fee_recovered 
FROM 
    loans l
JOIN loan_txns t ON l.loan_doc_id = t.loan_doc_id
JOIN borrowers b ON l.cust_id = b.cust_id
JOIN persons p ON b.owner_person_id = p.id
LEFT JOIN (
    SELECT DISTINCT loan_doc_id
    FROM loan_write_off
    WHERE DATE_FORMAT(write_off_date, '%Y%m') < @month
) lw ON lw.loan_doc_id = l.loan_doc_id
WHERE 
    l.country_code = @country_code
    AND b.country_code = @country_code
    AND p.country_code = @country_code
    AND DATE_FORMAT(t.txn_date, '%Y%m') = @month
    AND (
        (DATE_FORMAT(t.txn_date, '%Y%m') = @month AND t.realization_date <= @closure_date) OR 
        (DATE_FORMAT(t.txn_date, '%Y%m') < @month AND t.realization_date > @prev_closure_date AND t.realization_date <= @closure_date)
    )
    AND t.txn_type = 'payment'
GROUP BY 
    p.gender,
    l.country_code
ORDER BY 
		p.gender;