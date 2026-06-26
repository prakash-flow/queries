with base_query as (
  select
      l.cust_id,
      l.loan_doc_id,
      l.due_date,
      (ifNull(l.loan_principal, 0) + ifNull(l.flow_fee, 0) + ifNull(l.charges, 0)) as expected_amount,
      sum(ifNull(lt.principal, 0) + ifNull(lt.fee, 0) + ifNull(lt.charges, 0))                                        as paid_amount,
      sum(if(toDate(lt.txn_date) <= addDays(toDate(l.due_date), 1), ifNull(lt.principal, 0) + ifNull(lt.fee, 0) + ifNull(lt.charges, 0), 0))          as ontime_paid_amount,
      sum(if(toDate(lt.txn_date) <= addDays(toDate(l.due_date), 5), ifNull(lt.principal, 0) + ifNull(lt.fee, 0) + ifNull(lt.charges, 0), 0))          as paid_within_5_days_amount
  from
      loans l
      left join loan_txns lt
      on l.loan_doc_id = lt.loan_doc_id and lt.txn_type = 'payment'
  where l.due_date between '2026-01-01 00:00:00' and '2026-01-31 23:59:59'
  and l.country_code = 'RWA' and product_id not in (43,75,300,765,766) 
  and l.status not in ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
  group by l.cust_id, l.loan_doc_id, l.due_date, expected_amount
  ),
  raw as (
  select
      cust_id,
      loan_doc_id,
      count(loan_doc_id)             as loan_count,
      sum(ontime_paid_amount)        as ontime_repaid_amount,
      sum(expected_amount)           as total_due_amount,
      sum(paid_within_5_days_amount) as paid_within_5_days_amount,
      (sum(ontime_paid_amount) / sum(expected_amount) ) * 100  as loan_wise_ontime_repayment,
      sum(if(( ontime_paid_amount >= expected_amount), 1, 0))    as ontime_settle_count
  from base_query group by cust_id, loan_doc_id ) 
  select
        *
  from raw r
            