set @country_code = 'RWA';
Set @start_month = '202401';
set @end_month = '202412';

select @country_code, @start_month, @end_month;

SELECT 
	count(distinct l.loan_doc_id) count,
  sum(amount) value, 
  gender 
FROM 
  loans l, 
  loan_txns t, 
  persons p, 
  borrowers b 
WHERE 
  l.loan_doc_id = t.loan_doc_id 
  and b.cust_id = l.cust_id 
  and p.id = b.owner_person_id 
  and l.status not in (
    'voided', 'hold', 'pending_disbursal', 
    'pending_mnl_dsbrsl'
  ) 
  and product_id not in (
    select 
      id 
    from 
      loan_products 
    where 
      product_type = 'float_vending'
  ) 
  and l.country_code = @country_code 
  and txn_type = 'disbursal' 
  and extract(year_month from disbursal_date) between @start_month 
  and @end_month
GROUP BY 
  gender;