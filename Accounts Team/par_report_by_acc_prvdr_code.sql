set @country_code = 'UGA';
set @month = '202510';

set @last_day = (LAST_DAY(DATE(CONCAT(@month, "01"))));
set @realization_date = (IFNULL((select closure_date from closure_date_records where month = @month and status = 'enabled' and country_code = @country_code), now()));
-- SET @loan_purpose = "float_advance,terminal_financing";
SET @loan_purpose = "adj_float_advance";

select @last_day, @realization_date;


select 
	pri.acc_prvdr_code,
  sum(
    IF(
      principal - IFNULL(partial_pay, 0) < 0, 
      0, 
      principal - IFNULL(partial_pay, 0)
    )
  ) par_loan_principal, 

		SUM(IF(DATEDIFF(@last_day, due_date)  > 1,   if(principal - ifnull(partial_pay,0) > 0 , principal - ifnull(partial_pay,0), 0), 0)) AS par_1,
        SUM(IF(DATEDIFF(@last_day, due_date)  > 5,   if(principal - ifnull(partial_pay,0) > 0 , principal - ifnull(partial_pay,0), 0), 0)) AS par_5,
		SUM(IF(DATEDIFF(@last_day, due_date)  > 30,   if(principal - ifnull(partial_pay,0) > 0 , principal - ifnull(partial_pay,0), 0), 0)) AS par_30, 
        SUM(IF(DATEDIFF(@last_day, due_date)  > 60,   if(principal - ifnull(partial_pay,0) > 0 , principal - ifnull(partial_pay,0), 0), 0)) AS par_60,
        SUM(IF(DATEDIFF(@last_day, due_date)  > 90,   if(principal - ifnull(partial_pay,0) > 0 , principal - ifnull(partial_pay,0), 0), 0)) AS par_90,
        SUM(IF(DATEDIFF(@last_day, due_date)  > 120,   if(principal - ifnull(partial_pay,0) > 0 , principal - ifnull(partial_pay,0), 0), 0)) AS par_120,
        SUM(IF(DATEDIFF(@last_day, due_date)  > 180,   if(principal - ifnull(partial_pay,0) > 0 , principal - ifnull(partial_pay,0), 0), 0)) AS par_180,
        SUM(IF(DATEDIFF(@last_day, due_date)  > 270,   if(principal - ifnull(partial_pay,0) > 0 , principal - ifnull(partial_pay,0), 0), 0)) AS par_270,
        SUM(IF(DATEDIFF(@last_day, due_date)  > 360,   if(principal - ifnull(partial_pay,0) > 0 , principal - ifnull(partial_pay,0), 0), 0)) AS par_360
from 
  (
    select 
    	a.acc_prvdr_code,
      lt.loan_doc_id, 
#       loan_principal principal,
    	sum(amount) as principal,due_date
    from 
      loans l 
      JOIN loan_txns lt ON lt.loan_doc_id = l.loan_doc_id 
      join accounts a ON a.id = lt.from_ac_id
    where 
      lt.txn_type in ('disbursal') 
      and realization_date <= @realization_date 
      AND FIND_IN_SET(l.loan_purpose, @loan_purpose)
      and l.country_code = @country_code 
      and date(disbursal_date) <= @last_day 
      and product_id not in (43, 75, 300) 
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
    group by lt.loan_doc_id,a.acc_prvdr_code
#     ,loan_principal
  ) pri 
  left join (
    select 
    	l.acc_prvdr_code,
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
      AND FIND_IN_SET(l.loan_purpose, @loan_purpose)
      and date(txn_date) <= @last_day 
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
      l.loan_doc_id,l.acc_prvdr_code
  ) pp on pri.loan_doc_id = pp.loan_doc_id
  group  by pri.acc_prvdr_code
#   ,pri.loan_doc_id having par_loan_principal >0 
  ;