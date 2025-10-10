use flow_api;

set @year = 2024;
set @country_code = 'UGA';

set @first_date = (SELECT DATE(CONCAT(@year, '-01-01')));
set @last_date = (SELECT DATE(CONCAT(@year, '-12-31')));
set @start_month = (select CONCAT(@year - 1, "12"));
set @end_month = (select CONCAT(@year, "12"));

set
  @closure_date = (
    select
      closure_date
    from
      closure_date_records
    where
      country_code = @country_code
      and status = 'enabled'
      and month = @end_month
  );

set
  @prev_closure_date = (
    select
      closure_date
    from
      closure_date_records
    where
      country_code = @country_code
      and status = 'enabled'
      and month = @start_month
  );

select @first_date, @last_date, @country_code, @closure_date, @prev_closure_date, @year;

select 
	sub_lender_code `Sub Lender Code`,
  loan_purpose `Loan Purpose`,
  loan_principal `Loan Principal`,
  flow_fee `Flow Fee`,
  duration,
  COUNT(pri.loan_doc_id) `Disbursal Count`,
  SUM(IF(principal - ifnull(partial_pay, 0) < 0 , 1, 0)) `Repaid Count`
from 
  (
    select 
      l.loan_doc_id, 
    	l.loan_principal, l.flow_fee, l.loan_purpose, l.sub_lender_code, l.duration,
      loan_principal principal 
    from 
      loans l 
      JOIN loan_txns lt ON lt.loan_doc_id = l.loan_doc_id 
    where 
      lt.txn_type in ('disbursal') 
      and (
        (
          year(txn_date) = @year
          AND realization_date <= @closure_date
        )
        OR (
          year(txn_date) < @year
          AND realization_date > @prev_closure_date
          AND realization_date <= @closure_date
        )
      )
      and l.country_code = @country_code 
      and date(disbursal_date) <= @last_date 
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
          and date(write_off_date) <= @last_date 
          and write_off_status in (
            'approved', 'partially_recovered', 
            'recovered'
          )
      )
  ) pri 
  left join (
    select 
      l.loan_doc_id, 
      sum(amount) partial_pay 
    from 
      loans l 
      join loan_txns t ON l.loan_doc_id = t.loan_doc_id 
    where 
      l.country_code = @country_code 
      and date(disbursal_Date) <= @last_date 
      and product_id not in (43, 75, 300) 
      and (
        (
          year(txn_date) = @year
          AND realization_date <= @closure_date
        )
        OR (
          year(txn_date) < @year
          AND realization_date > @prev_closure_date
          AND realization_date <= @closure_date
        )
      )
      and date(txn_date) <= @last_date 
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
          and date(write_off_date) <= @last_date
          and write_off_status in (
            'approved', 'partially_recovered', 
            'recovered'
          )
      ) 
    group by 
      l.loan_doc_id
  ) pp on pri.loan_doc_id = pp.loan_doc_id
  GROUP BY
  sub_lender_code,
  loan_purpose,
  loan_principal,
  flow_fee,
  duration;