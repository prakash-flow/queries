set @country_code = 'UGA';
set @cur_month = '202404';

set @prev_month = (SELECT DATE_FORMAT(DATE_SUB(STR_TO_DATE(CONCAT(@cur_month, '01'), '%Y%m%d'), INTERVAL 1 MONTH), '%Y%m'));
set @prev_closure_date = (select closure_date from closure_date_records where country_code = @country_code and status = 'enabled' and month = @prev_month);
set @cur_closure_date = (IFNULL((select closure_date from closure_date_records where country_code = @country_code and status = 'enabled' and month = @cur_month), now()));
set @first_day = (select DATE(CONCAT(@cur_month, '01')));
set @last_day = (select LAST_DAY(@first_day));

select @country_code, @prev_month, @cur_month, @prev_closure_date, @cur_closure_date, @first_day, @last_day;

with sales AS (
  select 
    sales_doc_id, 
    sum(
      if(txn_type = 'float_in', 1, 0)
    ) float_in, 
    sum(
      if(txn_type = 'float_out', 1, 0)
    ) float_out 
  from 
    sales_txns 
  where 
    country_code = @country_code 
    and (
      (
        date(txn_date) >= @first_day 
        and date(txn_date) <= @last_day 
        and realization_date <= @cur_closure_date
      ) 
      or (
        date(txn_date) < @first_day 
        and realization_date > @prev_closure_date 
        and realization_date <= @cur_closure_date
      )
    ) 
  group by 
    sales_doc_id
  having
  	float_in > 0 and float_out > 0
) 
select 
  sum(float_in) float_in, 
  sum(float_out) float_out, 
  sum(float_in) = sum(float_out) is_perfect 
from 
  sales;
select * from sales where float_in != float_out;