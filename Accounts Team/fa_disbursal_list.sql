SET @month = '202510';
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
  a.acc_number AS `Account Number`, 
  t.txn_id AS `Tranaction ID`, 
  t.txn_date AS `Tranaction Date`, 
  a.realization_date AS `Realization Date`, 
  t.amount AS `Disbursal Amount`, 
  l.flow_fee AS `Applicable Fee`, 
  l.provisional_penalty AS `Initial Penalty`, 
  l.due_date AS `Due Date`, 
  l.duration as `No of days (Loan Duration)`, 
  l.paid_date as `paid date`, 
  l.paid_excess AS `Paid Excess`, 
  l.penalty_collected `Penalty Collected`, 
  l.penalty_waived as `penalty waived`, 
  l.fee_waived as `fee waived`, 
  CASE WHEN l.status NOT IN ('ongoing', 'due', 'settled') THEN DATEDIFF(NOW(), l.due_date) ELSE NULL END AS Par, 
  l.status AS loan_status 
from 
  loans l 
  Join loan_txns t on l.loan_doc_id = t.loan_doc_id 
  Join account_stmts a on a.stmt_txn_id = t.txn_id 
where 
  l.status NOT IN (
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
  AND l.country_code = 'UGA' 
  and txn_type = 'disbursal' 
  and acc_txn_type = 'disbursal' 
  AND FIND_IN_SET(l.loan_purpose, @loan_purpose)