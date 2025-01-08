set @country_code = 'RWA';
set @cur_month = '202401';

set @prev_month = (SELECT DATE_FORMAT(DATE_SUB(STR_TO_DATE(CONCAT(@cur_month, '01'), '%Y%m%d'), INTERVAL 1 MONTH), '%Y%m'));
set @prev_closure_date = (select closure_date from closure_date_records where country_code = @country_code and status = 'enabled' and month = @prev_month);
set @cur_closure_date = (IFNULL((select closure_date from closure_date_records where country_code = @country_code and status = 'enabled' and month = @cur_month), now()));
set @first_day = (select DATE(CONCAT(@cur_month, '01')));
set @last_day = (select LAST_DAY(@first_day));

select @country_code, @prev_month, @cur_month, @prev_closure_date, @cur_closure_date, @first_day, @last_day;

select 
  loan_doc_id, 
  txn_id, 
  txn_date, 
  amount, 
  principal, 
  fee, 
  charges, 
  penalty, 
  excess, 
  (
    principal + fee + charges + penalty + excess
  ) breakdown, 
  amount paid_amount 
from 
  loan_txns 
where 
  country_code = @country_code 
  and (
    (
      extract(
        year_month 
        from 
          txn_date
      ) = @month 
      and realization_date <= @cur_closure_date
    ) 
    or (
      extract(
        year_month 
        from 
          txn_date
      ) < @month 
      and realization_date > @prev_closure_date 
      and realization_date <= @cur_closure_date
    )
  ) 
having 
  paid_amount != breakdown;