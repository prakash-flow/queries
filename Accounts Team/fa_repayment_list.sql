SET @month = '202511';
SET @country_code = 'UGA';

SET @month_date = DATE(CONCAT(@month, '01'));
SET @start_date = CONCAT(@month_date, ' 00:00:00');
SET @end_date   = CONCAT(LAST_DAY(@month_date), ' 23:59:59');
-- SET @loan_purpose = "float_advance,terminal_financing";
SET @loan_purpose = "adj_float_advance";

SET @closure_date = (
    SELECT closure_date
    FROM closure_date_records
    WHERE country_code = @country_code
      AND status = 'enabled'
      AND month = @month
);

SET @prev_closure_date = (
    SELECT closure_date
    FROM closure_date_records
    WHERE country_code = @country_code
      AND status = 'enabled'
      AND month = DATE_FORMAT(DATE_SUB(@month_date, INTERVAL 1 MONTH), '%Y%m')
);

select 
  @month AS `Realization_month (report month)`, 
  l.loan_doc_id AS `Unique ID`, 
  t.to_ac_id `To Acc ID`, 
  a.acc_number AS `Account Number`, 
  t.txn_id AS `Transaction ID`, 
  t.txn_date AS `Transaction Date`, 
  a.realization_date AS `Realization Date`, 
  t.principal AS `Paid Amount`, 
  t.fee AS `Paid Fee`, 
  t.excess AS `Paid Excess`, 
  t.penalty AS `Paid Penalty Amount`, 
  l.status AS `Loan Status`, 
  CASE WHEN l.loan_doc_id IN (
    SELECT 
      loan_doc_id 
    FROM 
      loan_write_off 
    WHERE 
      DATE(write_off_date) <= @end_date
  ) THEN 'Recovered' ELSE 'Received' END AS `Transaction Type` 
from 
  loans l 
  Join loan_txns t on l.loan_doc_id = t.loan_doc_id 
  Join account_stmts a on a.stmt_txn_id = t.txn_id 
  and t.txn_type = a.acc_txn_type 
where 
  l.product_id NOT IN (43, 75, 300) 
  AND l.status NOT IN (
    'voided', 'hold', 'pending_disbursal', 
    'pending_mnl_dsbrsl'
  ) 
  AND (
    (
      txn_date >= @start_date 
      AND txn_date <= @end_date 
      AND t.realization_date <= @closure_date
    ) 
    OR (
      txn_date < @start_date 
      AND t.realization_date > @prev_closure_date 
      AND t.realization_date <= @closure_date
    )
  ) 
  AND l.country_code = @country_code
  and txn_type = 'payment' 
  And acc_txn_type = 'payment' 
  AND FIND_IN_SET(l.loan_purpose, @loan_purpose);