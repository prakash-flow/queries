set @country_code = 'UGA';
set @month = '202511';

set @last_day = (LAST_DAY(DATE(CONCAT(@month, "01"))));
set @sub_lender_code = 'FSD2';
set @realization_date = (IFNULL((select closure_date from closure_date_records where month = @month and status = 'enabled' and country_code = @country_code), now()));

select @last_day, @realization_date;

# UFSD
# FSD2

select 
  	@month,
    SUM(IF(principal - IFNULL(partial_pay, 0) < 0, 0, principal - IFNULL(partial_pay, 0))) AS over_all_os,
    SUM(IF(DATEDIFF(@last_day, due_date) > 1,   IF(principal - IFNULL(partial_pay, 0) > 0, principal - IFNULL(partial_pay, 0), 0), 0)) AS par_1,
#     SUM(IF(DATEDIFF(@last_day, due_date) > 5,   IF(principal - IFNULL(partial_pay, 0) > 0, principal - IFNULL(partial_pay, 0), 0), 0)) AS par_5,
#     SUM(IF(DATEDIFF(@last_day, due_date) > 10,   IF(principal - IFNULL(partial_pay, 0) > 0, principal - IFNULL(partial_pay, 0), 0), 0)) AS par_10,
#     SUM(IF(DATEDIFF(@last_day, due_date) > 15,   IF(principal - IFNULL(partial_pay, 0) > 0, principal - IFNULL(partial_pay, 0), 0), 0)) AS par_15,
    SUM(IF(DATEDIFF(@last_day, due_date) > 30,  IF(principal - IFNULL(partial_pay, 0) > 0, principal - IFNULL(partial_pay, 0), 0), 0)) AS par_30, 
    SUM(IF(DATEDIFF(@last_day, due_date) > 60,  IF(principal - IFNULL(partial_pay, 0) > 0, principal - IFNULL(partial_pay, 0), 0), 0)) AS par_60, 
    SUM(IF(DATEDIFF(@last_day, due_date) > 90,  IF(principal - IFNULL(partial_pay, 0) > 0, principal - IFNULL(partial_pay, 0), 0), 0)) AS par_90
#     SUM(IF(DATEDIFF(@last_day, due_date) > 120, IF(principal - IFNULL(partial_pay, 0) > 0, principal - IFNULL(partial_pay, 0), 0), 0)) AS par_120, 
#     SUM(IF(DATEDIFF(@last_day, due_date) > 180, IF(principal - IFNULL(partial_pay, 0) > 0, principal - IFNULL(partial_pay, 0), 0), 0)) AS par_180, 
#     SUM(IF(DATEDIFF(@last_day, due_date) > 270, IF(principal - IFNULL(partial_pay, 0) > 0, principal - IFNULL(partial_pay, 0), 0), 0)) AS par_270, 
#     SUM(IF(DATEDIFF(@last_day, due_date) > 360, IF(principal - IFNULL(partial_pay, 0) > 0, principal - IFNULL(partial_pay, 0), 0), 0)) AS par_360
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
    	AND l.sub_lender_code = @sub_lender_code
      and txn_type = 'payment' 
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
#   group  by pri.loan_doc_id having par_loan_principal >0 
  ;









