SET @country_code = 'UGA';
SET @month = '202601';

SET @pre_month = DATE_FORMAT(
    DATE_SUB(STR_TO_DATE(CONCAT(@month, '01'), '%Y%m%d'), INTERVAL 1 MONTH),
    '%Y%m'
);

SET @start_date     = CONCAT(@month, '01 00:00:00');
SET @last_day       = CONCAT(LAST_DAY(CONCAT(@month, '01')), ' 23:59:59');

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

SELECT
    l.loan_purpose,
    COUNT(DISTINCT b.cust_id) AS active_cust_count
FROM borrowers b
JOIN loans l     ON b.cust_id = l.cust_id
JOIN loan_txns t ON l.loan_doc_id = t.loan_doc_id
WHERE b.country_code = @country_code
  AND t.txn_type IN ('disbursal','af_disbursal')
  and l.disbursal_date <= @last_day
  and l.due_date >= @last_day  
  AND l.product_id NOT IN (43,75,300)
  AND l.status NOT IN ('voided','hold','pending_disbursal','pending_mnl_dsbrsl')
  AND l.loan_purpose in ('growth_financing','asset_financing')
 
GROUP BY l.loan_purpose;
