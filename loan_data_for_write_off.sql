set
  @month = '202312';

set
  @country_code = 'UGA';

set
  @last_day = (LAST_DAY(DATE(CONCAT(@month, "01"))));

select
  @month,
  @country_code,
  @last_day;

with
  par_loans AS (
    select
      loan_doc_id
    from
      loan_write_off
    where
      write_off_date <= @last_day
      and write_off_status in ('approved', 'partially_recovered', 'recovered')
      and country_code = @country_code
  )
select
  pl.loan_doc_id `Loan Doc ID`,
  l.acc_prvdr_code `Account Provider Code`,
  concat_ws(' ', p.first_name, p.middle_name, p.last_name) `Customer Name`,
  concat_ws(' ', rm.first_name, rm.middle_name, rm.last_name) `RM Name`,
  l.product_name `Product Name`,
  l.disbursal_date `Disbursal Date`,
  l.due_date `Due Date`,
  l.loan_principal `Principal`,
  l.flow_fee `Fee`,
  l.overdue_days `Overdue Days`,
  IFNULL(lt.paid_amount, 0) `Paid Amount`,
  IFNULL(last_payment_date, "") `Last Payment Date`
from
  loans l
  join par_loans pl on l.loan_doc_id = pl.loan_doc_id
  join borrowers b on b.cust_id = l.cust_id
  left join persons p on p.id = b.owner_person_id
  left join persons rm on rm.id = b.flow_rel_mgr_id
  left join (
    select
      lt.loan_doc_id loan_doc_id,
    	sum(amount) paid_amount,
    	MAX(txn_date) last_payment_date
    from
      loan_txns lt
      left join par_loans p on p.loan_doc_id = lt.loan_doc_id
    where
      date(txn_date) <= @last_day
      and country_code = @country_code
    	and txn_type = 'payment'
    group by lt.loan_doc_id
  ) lt on lt.loan_doc_id = l.loan_doc_id;