with current_month_due as (
  select
      l.cust_id,
      l.loan_doc_id,
      l.due_date,
      (ifNull(l.loan_principal, 0) + ifNull(l.flow_fee, 0) + ifNull(l.charges, 0)) as expected_amount,
      0    as paid_amount,
      0    as ontime_paid_amount
  from loans l
  where l.due_date between '2026-01-01 00:00:00' and '2026-01-31 23:59:59'
  and l.country_code = 'RWA' and product_id not in (43,75,300,765,766) 
  and l.status not in ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
  ),
  received_amounts as (
  select
      l.cust_id,
      l.loan_doc_id,
      l.due_date,
      0                                            as expected_amount,
      sum(ifNull(lt.principal, 0) + ifNull(lt.fee, 0) + ifNull(lt.charges, 0))                              as paid_amount,
      sum(if(toDate(lt.txn_date) <= addDays(toDate(l.due_date), 1), ifNull(lt.principal, 0) + ifNull(lt.fee, 0) + ifNull(lt.charges, 0), 0)) as ontime_paid_amount
  from loan_txns lt
  join loans l on lt.loan_doc_id = l.loan_doc_id
  where lt.txn_date between '2026-01-01 00:00:00' and '2026-01-31 23:59:59'
  and lt.txn_type = 'payment'
  and l.country_code = 'RWA' and product_id not in (43,75,300,765,766) 
  and l.status not in ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
  group by l.cust_id, l.loan_doc_id, l.due_date
  ),
  base_query as (
  select * from current_month_due
  union all
  select * from received_amounts
  ),
  aggregated as (
  select
      cust_id,
      loan_doc_id,
      sum(expected_amount)           as total_due_amount,
      sum(paid_amount)               as total_received,
      sum(ontime_paid_amount)        as ontime_repaid_amount,
      max(due_date)                  as max_due_date
  from base_query group by cust_id, loan_doc_id
  ),
  raw as (
  select
      cust_id,
      loan_doc_id,
      total_due_amount as expected_amount,
      total_received as total_collected_amount,
      ontime_repaid_amount as ontime_collected_amount,
        total_received /total_due_amount as Monthly_collection_rate
  from aggregated ) 
  select
      *
  from raw r








