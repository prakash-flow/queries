with adjLoans as (
	select
  	cust_id `Customer Id`,
  	loan_doc_id `Loan Doc Id`,
  	format(loan_principal, 0) `Loan Principal`,
  	format(flow_fee, 0) `Loan Fee`,
  	format(paid_amount, 0) `Settled Amount`,
  	disbursal_date `Disbursal date`,
  	due_date `Due date`,
  	paid_date `Paid date`,
    cust_acc_id `Customer Account ID`,
    `acc_number` `Account Number`,
    biz_name `Biz Name`,
  	lead(l.disbursal_date) over (partition by l.cust_id order by l.disbursal_date) `Next loan date`,
  	lead(l.id) over (partition by l.cust_id order by l.id) `next_loan_id`
  from
  	loans l
  where
  	loan_purpose = 'adj_float_advance'
  	and country_code = 'UGA'
  	and product_id not in (select id from loan_products where product_type = 'float_vending')
    and status not in ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
)
select
	a.*,
  nl.status `Next Loan Status`,
  concat_ws(' ', p.first_name, p.middle_name, p.last_name) `Customer name`,
  p.mobile_num `Customer mobile`,
  
  datediff(`Paid date`, `Due date`),
  (datediff(`Paid date`, `Due date`) <= 1) paid_on_time
from
	adjLoans a 
  left join loans nl on nl.id = next_loan_id
  left join borrowers b on b.cust_id = a.`Customer Id`
  left join persons p on b.owner_person_id = p.id
where
  `Due date` between '2025-05-01 23:59:59' and '2025-05-31 23:59:59'
having paid_on_time = 1;