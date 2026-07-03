with raw as (
  select
    l.cust_id,
    l.loan_doc_id,
    l.due_date,
    (l.loan_principal + l.flow_fee)                                         as expected_amount,
    sum(ifNull(lt.principal, 0) + ifNull(lt.fee, 0))                       as paid_amount,
    sum(
      if(toDate(lt.txn_date) <= addDays(toDate(l.due_date), 1),
        ifNull(lt.principal, 0) + ifNull(lt.fee, 0),
        0)
    )                                                                        as ontime_paid_amount
  from
    loans l
    left join loan_txns lt on l.loan_doc_id = lt.loan_doc_id
      and lt.txn_type = 'payment'
  where
    l.country_code = 'UGA'
    and l.status in ('ongoing', 'due', 'settled', 'overdue')
    and l.loan_purpose = 'float_advance'
  group by l.cust_id, l.loan_doc_id, l.due_date, expected_amount
)
select
  cust_id,
  sum(ontime_paid_amount)                                                    as ontime_repaid_amount,
  sum(expected_amount)                                                       as total_due_amount,
  (sum(ontime_paid_amount) / nullIf(sum(expected_amount), 0)) * 100                 as ontime_repayment_rate
from raw
group by cust_id