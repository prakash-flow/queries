set @country_code = 'UGA';
set @month = '202501';
SET @pre_month = (SELECT DATE_FORMAT(DATE_SUB(STR_TO_DATE(CONCAT(@month, '01'), '%Y%m%d'), INTERVAL 1 MONTH), '%Y%m'));
SET @start_date = DATE(CONCAT(@month, '01'));
set @last_day = (LAST_DAY(DATE(CONCAT(@month, "01"))));
set @realization_date = (IFNULL((select closure_date from closure_date_records where month = @month and status = 'enabled' and country_code = @country_code), CONCAT(@last_day, ' 23:59:59')));
set @pre_realization_date = ((select closure_date from closure_date_records where month = @pre_month and status = 'enabled' and country_code = @country_code));

select @start_date,@last_day,@realization_date,@pre_realization_date,@pre_month;



select l.loan_doc_id as `Loan ID`,l.loan_purpose as `Loan Purpose`,lw.write_off_date as `Loan Write Off Date`,a.acc_prvdr_code `Account Provider Code`,a.acc_number `Account Number`,stmt_txn_id `Transaction Id`,
      stmt_txn_date as `Transaction Date`,
      t.amount As `Recovery Amount`,
      t.principal As `Recovery Principal `,t.fee as `Recovery Fee`,t.penalty as `Paid Penalty`,t.charges `Paid Charges`,t.excess `Paid Excess`,lw.type as `Write Off Type`

from loans l 
Join loan_txns t on l.loan_doc_id = t.loan_doc_id 
Join account_stmts a on a.stmt_txn_id = t.txn_id
Join loan_write_off 
  lw on lw.loan_doc_id = l.loan_doc_id
where
    txn_type = 'payment' and acc_txn_type ='payment'
    and write_off_date < date(txn_date)
    and (
(   extract(year_month from stmt_txn_date) = @month  and a.realization_date <= @realization_date  )
or 
(   extract(year_month from stmt_txn_date) < @month and a.realization_date > @pre_realization_date and a.realization_date <= @realization_date   )
)
and date(txn_date) <= @last_day and l.country_code = @country_code
-- group by l.loan_purpose









