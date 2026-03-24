set @country_code = 'UGA';
set @month = '202602';

set @last_day = (LAST_DAY(DATE(CONCAT(@month, "01"))));

set @realization_date = (IFNULL((select closure_date from closure_date_records where month = @month and status = 'enabled' and country_code = @country_code), now()));
set @sub_lender_code = 'FSD2';
select @last_day, @realization_date;

# UFSD
# FSD2

select
 		pri.loan_doc_id, 
    pri.cust_id,  
    IF(principal + flow_fee - IFNULL(partial_pay, 0) < 0, 0, principal + flow_fee - IFNULL(partial_pay, 0)) AS total_due,  
    IF(principal - IFNULL(partial_pay, 0) < 0, 0, principal - IFNULL(partial_pay, 0)) AS outstanding_amount,
    DATEDIFF(@last_day, DATE(pri.due_date)) AS overdue_days
from 
  (
    select 
      lt.loan_doc_id, 
        l.cust_id, 
#         l.status, 
        sum(l.flow_fee) as flow_fee, 
        max(l.due_date) as due_date,
    	sum(amount) as principal
    from 
      loans l 
      JOIN loan_txns lt ON lt.loan_doc_id = l.loan_doc_id 
    where 
      lt.txn_type in ('disbursal') 
      and realization_date <= @realization_date 
      and l.country_code = @country_code 
      and date(disbursal_date) <= @last_day 
      and product_id not in (43, 75, 300) 
    	AND l.sub_lender_code = @sub_lender_code
      and l.status not in (
        'voided', 'hold', 'pending_disbursal', 
        'pending_mnl_dsbrsl'
      ) 
    	AND DATEDIFF(@last_day, due_date) > 1
      and l.loan_doc_id not in (
        select 
          loan_doc_id 
        from 
          loan_write_off 
        where 
          l.country_code = @country_code 
          and date(write_off_date) <= @last_day 
          and write_off_status in (
            'approved', 'partially_recovered', 
            'recovered'
          )
      ) 
    group by lt.loan_doc_id,l.cust_id
#     ,loan_principal
  ) pri 
  left join (
    select 
      l.loan_doc_id, 
      sum(principal) partial_pay 
    from 
      loans l 
      join loan_txns t ON l.loan_doc_id = t.loan_doc_id 
    where 
      l.country_code = @country_code 
      and date(disbursal_Date) <= @last_day 
      and product_id not in (43, 75, 300) 
      and realization_date <= @realization_date 
    	AND DATEDIFF(@last_day, due_date) > 1
      and date(txn_date) <= @last_day 
      and txn_type = 'payment' 
    	AND l.sub_lender_code = @sub_lender_code
      and l.status not in (
        'voided', 'hold', 'pending_disbursal', 
        'pending_mnl_dsbrsl'
      ) 
      and l.loan_doc_id not in (
        select 
          loan_doc_id 
        from 
          loan_write_off 
        where 
          l.country_code = @country_code 
          and date(write_off_date) <= @last_day
          and write_off_status in (
            'approved', 'partially_recovered', 
            'recovered'
          )
      ) 
    group by 
      l.loan_doc_id
  ) pp on pri.loan_doc_id = pp.loan_doc_id
  having outstanding_amount > 0
  ;