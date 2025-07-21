
SET @country_code = 'UGA';
SET @month = '202505';
SET @last_day = LAST_DAY(DATE(CONCAT(@month, '01')));

SET @realization_date = (
  SELECT IFNULL(
    (SELECT closure_date
     FROM closure_date_records
     WHERE month = @month
       AND status = 'enabled'
       AND country_code = @country_code),
    NOW()
  )
);

SELECT @last_day, @realization_date;

SELECT 
    SUM(IF(principal - IFNULL(partial_pay, 0) < 0, 0, principal - IFNULL(partial_pay, 0))) AS od_amount,
    SUM(IF(principal - IFNULL(partial_pay, 0) > 0, 1, 0)) AS od_count
FROM (
  
    SELECT 
        lt.loan_doc_id,
        SUM(lt.amount) AS principal
    FROM loans l
    JOIN loan_txns lt ON lt.loan_doc_id = l.loan_doc_id
    WHERE lt.txn_type = 'disbursal'
      AND DATE(l.disbursal_date) BETWEEN '2018-12-01' AND @last_day
      AND lt.realization_date <= @realization_date
      AND DATEDIFF(@last_day, l.due_date) > 1
      AND l.loan_doc_id NOT IN (
          SELECT loan_doc_id
          FROM loan_write_off
          WHERE country_code = @country_code
            AND write_off_date <= @last_day
            AND write_off_status IN ('approved', 'partially_recovered', 'recovered')
      )
      AND l.product_id NOT IN (43, 75, 300)
      AND l.status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
      AND l.country_code = @country_code
    GROUP BY lt.loan_doc_id
) AS pri
LEFT JOIN (
    SELECT 
        t.loan_doc_id,
        SUM(t.principal) AS partial_pay
    FROM loans l
    JOIN loan_txns t ON t.loan_doc_id = l.loan_doc_id
    WHERE t.txn_type = 'payment'
      AND DATE(l.disbursal_date) BETWEEN '2018-12-01' AND @last_day
      AND DATE(t.txn_date) BETWEEN '2018-12-01' AND @last_day
      AND t.realization_date <= @realization_date
      AND DATEDIFF(@last_day, l.due_date) > 1
      AND l.loan_doc_id NOT IN (
          SELECT loan_doc_id
          FROM loan_write_off
          WHERE country_code = @country_code
            AND write_off_date <= @last_day
            AND write_off_status IN ('approved', 'partially_recovered', 'recovered')
      )
      AND l.product_id NOT IN (43, 75, 300)
      AND l.status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
      AND l.country_code = @country_code
    GROUP BY t.loan_doc_id
) AS pp
ON pri.loan_doc_id = pp.loan_doc_id;