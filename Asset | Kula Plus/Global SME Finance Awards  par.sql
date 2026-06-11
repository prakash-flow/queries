# MDG
set @country_code = 'MDG';
set @month = '202412';
set @cut_off = '2024-11-30';

set @last_day = (LAST_DAY(DATE(CONCAT(@month, "01"))));
set @realization_date = (IFNULL((select closure_date from closure_date_records where month = @month and status = 'enabled' and country_code = @country_code), now()));

select @last_day, @realization_date;


select 
# 	pri.loan_doc_id,
  sum(
    IF(
      principal - IFNULL(partial_pay, 0) < 0, 
      0, 
      principal - IFNULL(partial_pay, 0)
    )
  ) par_loan_principal, 
#   SUM(
#     IF(
#       principal - IFNULL(partial_pay, 0) < 0, 
#       0, 
#       1
#     )
#   ) par_count,
#   sum(
#     IF(
#       partial_pay > principal, principal, 
#       partial_pay
#     )
#   ) partial_paid ,
#   ,sum(principal),sum(test_amount),
				SUM(IF(DATEDIFF(@last_day, due_date)  > 30,   if(principal - ifnull(partial_pay,0) > 0 , principal - ifnull(partial_pay,0), 0), 0)) AS par_30, 
        SUM(IF(DATEDIFF(@last_day, due_date)  > 60,   if(principal - ifnull(partial_pay,0) > 0 , principal - ifnull(partial_pay,0), 0), 0)) AS par_60,
        SUM(
              IF(
                  DATEDIFF(@last_day, due_date) > 120,
                  IF(principal - IFNULL(partial_pay, 0) > 0, 1, 0),
                  0
              )
          ) AS par_count,
        SUM(IF(DATEDIFF(@last_day, due_date)  > 120,   if(principal - ifnull(partial_pay,0) > 0 , principal - ifnull(partial_pay,0), 0), 0)) AS par_120
from 
  (
    select 
      lt.loan_doc_id, 
#       loan_principal principal,
    	sum(amount) as principal,due_date
    from 
      loans l 
      JOIN loan_txns lt ON lt.loan_doc_id = l.loan_doc_id 
    where 
      lt.txn_type in ('disbursal') 
      and realization_date <= @realization_date 
      and l.country_code = @country_code 
      and date(disbursal_date) <= @last_day 
      and product_id not in (43, 75, 300) 
      and l.status not in (
        'voided', 'hold', 'pending_disbursal', 
        'pending_mnl_dsbrsl'
      ) 
#     	AND l.sub_lender_code = 'UFSD'
      and l.loan_doc_id not in (
        select 
          loan_doc_id 
        from 
          loan_write_off 
        where 
          l.country_code = @country_code 
          and date(write_off_date) <= @cut_off
          and write_off_status in (
            'approved', 'partially_recovered', 
            'recovered'
          )
      ) 
    group by lt.loan_doc_id
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
      and date(txn_date) <= @last_day 
      and txn_type = 'payment' 
#     	AND l.sub_lender_code = 'UFSD'
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
          and date(write_off_date) <= @cut_off
          and write_off_status in (
            'approved', 'partially_recovered', 
            'recovered'
          )
      ) 
    group by 
      l.loan_doc_id
  ) pp on pri.loan_doc_id = pp.loan_doc_id
#   group  by pri.loan_doc_id having par_loan_principal >0 
  ;









