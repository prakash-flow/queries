select 
  b.biz_name `Biz Name`,
  p.mobile_num `Contact Number`,
  concat_ws(' ', p.first_name, p.middle_name, p.last_name) `Contact Name`,
  li.principal_due `Principal due`,
  li.fee_due `Fee due`,
  li.principal_due + li.fee_due `Total due`,
  li.principal_paid + li.fee_paid `Collected`,
  date(li.due_date) `Due Date`,
  li.loan_doc_id,
  li.status `Status`
from 
  loan_installments li 
  left join loans l on l.loan_doc_id = li.loan_doc_id
  left join borrowers b on b.cust_id = l.cust_id
  left join persons p on b.owner_person_id = p.id
where 
  li.country_code = 'UGA' 
  and date(li.due_date) between '2026-01-01' and '2026-01-31';