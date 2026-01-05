set @country_code = 'RWA';
set @month = '202501';
set @last_day = (select LAST_DAY(DATE(CONCAT(@month, '01'))));
set @closure_date = (select closure_date from flow_api.closure_date_records where status='enabled' and month = @month and country_code = @country_code);
SET @loan_purpose = "float_advance,adj_float_advance,terminal_financing";

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
    and FIND_IN_SET(l.loan_purpose, @loan_purpose)
  	and l.country_code = @country_code
    and date(disbursal_date) <= @last_day
  	and realization_date <= @closure_date
    and product_id not in (select id from loan_products where product_type = 'float_vending')
    and status not in ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
  	and l.loan_doc_id not in (
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
    lt.txn_type in ('payment', 'fee_waiver') 
  	and date(txn_date) <= @last_day
  	and realization_date <= @closure_date
 	group by l.loan_doc_id
),
parsedLoans as (
	select
    l.country_code,
  	pri.loan_doc_id,
    l.acc_prvdr_code,
    l.loan_purpose,
  	IF(principal - IFNULL(partial_principal,0) <0, 0, principal - IFNULL(partial_principal,0)) os_principal,
    IF(fee - (IFNULL(partial_fee,0))  <0, 0, fee - (IFNULL(partial_fee,0)) ) os_fee,
    IF(principal - IFNULL(partial_principal,0) <0, 0, principal - IFNULL(partial_principal,0)) + IF(fee - (IFNULL(partial_fee,0))  <0, 0, fee - (IFNULL(partial_fee,0))) write_off_amount,
    @last_day `write_off_date`,
    '11192' req_by,
    '11192' appr_by,
    'regular' type,
    if(DATEDIFF(@last_day, due_date) > 0, DATEDIFF(@last_day, due_date), 0) as par_days
  from 
  	disbursals pri 
    left join loans l on l.loan_doc_id = pri.loan_doc_id
  	left join payments pp on pri.loan_doc_id = pp.loan_doc_id
)
select 
 	*
from 
  parsedLoans
where (os_principal > 0 or os_fee > 0) and par_days > 120;