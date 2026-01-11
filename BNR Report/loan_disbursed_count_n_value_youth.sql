set @country_code = 'RWA';
Set @start_month = '202501';
set @end_month = '202512';

set @last_day = (LAST_DAY(DATE(CONCAT(@month, "01"))));
select @country_code, @start_month, @end_month, @last_day;

SELECT 
  count(loan_doc_id) count,
  sum(loan_principal) value
FROM 
  (
    SELECT 
      l.loan_doc_id, 
      loan_principal, 
      TIMESTAMPDIFF(YEAR, p.dob, @last_day) age 
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
      and l.country_code = 'RWA' 
      and txn_type = 'disbursal' 
      and extract(year_month from  disbursal_date) between @start_month 
      and @end_month
    having age <= 35
  ) as T;
  