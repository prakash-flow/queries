--Impact Monitoring
set @range_end = '2026-06-30';


--1. Number of people with improved income = Number of enabled customers (break down by gender)

WITH latest_record_audits AS (
      SELECT r1.entity_id,
             current_status AS status
      FROM status_audit_logs r1
      JOIN (
          SELECT entity_id, MAX(id) AS id
          FROM status_audit_logs
          WHERE date(modified_time) <= @range_end
          GROUP BY entity_id
      ) r2 ON r1.id = r2.id
  )
  
  SELECT
      count(b.cust_id) enabled_cust_count ,
  			count(if(p.gender='female',b.cust_id, null)) female,
  			count(if(p.gender='female',null, b.cust_id)) male
      
  FROM borrowers b
  Join persons p  ON b.owner_person_id = p.id
  WHERE 
    date(b.reg_date) <=  @range_end
    AND NOT EXISTS (
          SELECT 1
          FROM latest_record_audits ra
          WHERE ra.entity_id = b.cust_id
            AND ra.status = 'disabled'
    )
  -- GROUP BY l.loan_purpose
    ;
-- FYI, using MySQL variables reduces query performance, in this query there was significant drop in performance. So if time is of the essence, use literals.



--2. Enterprises Benefitted
set @range_end = '2025-12-31';
SELECT count(*) 
FROM borrowers
WHERE date(reg_date) <= @range_end;

--4.1.2 - Total loans disbursed
-- Run for each country and add up

set @country = 'MDG';
set @closure_date = (select closure_date from closure_date_records where month = DATE_FORMAT(@range_end, '%Y%m') and country_code = @country and status = 'enabled');

select count(distinct l.loan_doc_id) from loans l join loan_txns t on l.loan_doc_id = t.loan_doc_id where 
txn_type = 'disbursal'  
-- and realization_date <= @closure_date
and date(txn_date) <= @range_end 
and l.loan_purpose in ('adj_float_advance','float_advance','terminal_financing')
and date(disbursal_date)<= @range_end and 
status not in ('voided','hold','pending_disbursal','pending_mnl_dsbrsl') 
and product_id not in (43, 75)
and l.country_code = @country; 

-- 4.1.2 - Amount of Total Loans disbursed

-- Run for each country, convert to USD and add up

set @country = 'MDG';
set @closure_date = (select closure_date from closure_date_records where month = DATE_FORMAT(@range_end, '%Y%m') and country_code = @country and status = 'enabled');

select sum(amount) from loans l join loan_txns t on l.loan_doc_id = t.loan_doc_id where 
txn_type = 'disbursal'  
-- and realization_date <= @closure_date
and date(txn_date) <= @range_end
and l.loan_purpose in ('adj_float_advance','float_advance','terminal_financing')
and date(disbursal_date)<= @range_end and 
status not in ('voided','hold','pending_disbursal','pending_mnl_dsbrsl') 
and product_id not in (43, 75)
and l.country_code = @country; 



-- KPI REPORTING

-- Interest Rate
select
	avg(flow_fee / (duration + 0.5) / loan_principal * 298)
from
  loans
where
  extract(
    year_month
    from
      disbursal_date
  ) between 202407 and 202412 and status not in ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl') 
and product_id not in (43, 75)
  and flow_fee is not null 
  and duration is not null
  and loan_principal is not null;









