set @country_code = 'UGA';
set @month = '202412';
set @last_day = '2024-12-31';
set @closure_date = (select closure_date from flow_api.closure_date_records where status='enabled' and month = @month and country_code=@country_code);
set @loan_purpose = 'float_advance';

select @country_code, @month, @last_day, @closure_date;

with disbursals as (
  select 
    l.loan_doc_id, 
    loan_principal principal,
    flow_fee fee
  from 
    loans l JOIN loan_txns lt ON lt.loan_doc_id = l.loan_doc_id
  where 
  	lt.txn_type in ('disbursal') 
    and l.loan_purpose = @loan_purpose
  	and l.country_code = @country_code
    and date(disbursal_date) <= @last_day
  	and realization_date <= @closure_date
    and product_id not in (select id from loan_products where product_type = 'float_vending')
    and status not in ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
  	and l.loan_doc_id not in(
      select 
      	loan_doc_id
      from 
      	loan_write_off 
      where country_code = @country_code and write_off_date <= @last_day
      and write_off_status in ('approved','partially_recovered','recovered')
    )
  group by l.loan_doc_id, loan_principal, flow_fee
),
payments as (
  select 
  	l.loan_doc_id, 
  	sum(lt.principal) partial_principal, 
    sum(lt.fee) partial_fee
  from 
  	disbursals l JOIN loan_txns lt ON lt.loan_doc_id = l.loan_doc_id
  where 
    lt.txn_type in ('payment') 
  	and date(txn_date) <= @last_day
  	and realization_date <= @closure_date
 	group by l.loan_doc_id
),
parsedLoans as (
	select
  	pri.loan_doc_id,
  	principal,
    fee,
  	partial_principal,
    partial_fee,
    disbursal_date,
    due_date,
    extract(year_month from due_date) due_month,
  	IF(principal - IFNULL(partial_principal,0) <0, 0, principal - IFNULL(partial_principal,0)) os_principal,
    IF(fee - IFNULL(partial_fee,0) <0, 0, fee - IFNULL(partial_fee,0)) os_fee
  from 
  	disbursals pri 
    left join loans l on l.loan_doc_id = pri.loan_doc_id
  	left join payments pp on pri.loan_doc_id = pp.loan_doc_id
)
select 
 	*
from 
  parsedLoans
where (os_principal > 0 or os_fee > 0) ;