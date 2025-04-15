set @country_code = 'UGA';
set @month = '202503';
set @first_day = '2025-01-01';
set @last_day = '2025-03-31';
set @prev_month = '202412';

set @closure_date = (select closure_date from flow_api.closure_date_records where status='enabled' and month = @month and country_code=@country_code);
set @prev_closure_date = (select closure_date from flow_api.closure_date_records where status='enabled' and month = @prev_month and country_code=@country_code);

SELECT
  COUNT(DISTINCT l.loan_doc_id) Repaid_loan_amt
FROM
  loans l,
  loan_txns t
WHERE
  l.loan_doc_id = t.loan_doc_id
  and l.status NOT IN(
    'voided',
    'hold',
    'pending_disbursal',
    'pending_mnl_dsbrsl'
  )
  AND l.product_id NOT IN(43, 75, 300)
  and txn_type = 'disbursal'
  AND l.country_code = 'UGA'
  and
  (
      (
        date(txn_date) >= @first_day and date(txn_date) <= @last_day
        and realization_date <= @closure_date
      ) or (
        date(txn_date) <= @first_day
        and realization_date > @prev_closure_date and realization_date <= @closure_date
      )
    )
  and product_id not in(
    select
      id
    from
      loan_products
    where
      product_type = 'float_vending'
  )
GROUP BY
  l.country_code;