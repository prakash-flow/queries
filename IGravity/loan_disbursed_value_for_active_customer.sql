set @country_code = 'UGA';
set @month = '202503';
set @first_day = '2025-01-01';
set @last_day = '2025-03-31';
set @prev_month = '202412';

set @closure_date = (select closure_date from flow_api.closure_date_records where status='enabled' and month = @month and country_code=@country_code);
set @prev_closure_date = (select closure_date from flow_api.closure_date_records where status='enabled' and month = @prev_month and country_code=@country_code);

WITH active_cust AS (
    SELECT DISTINCT
        l.cust_id AS cust_id
    FROM
        loans l
    JOIN
        loan_txns t ON l.loan_doc_id = t.loan_doc_id
    LEFT JOIN (
        SELECT DISTINCT
            r1.record_code
        FROM
            record_audits r1
        JOIN (
            SELECT
                record_code,
                MAX(id) AS id
            FROM
                record_audits
            WHERE
                DATE(created_at) <= @last_day
            GROUP BY
                record_code
        ) r2 ON r1.id = r2.id
        WHERE
            JSON_EXTRACT(r1.data_after, '$.status') = 'disabled'
    ) disabled_cust ON l.cust_id = disabled_cust.record_code
    WHERE
        DATEDIFF(@last_day, t.txn_date) <= 30
        AND DATE(t.txn_date) <= @last_day
        AND l.country_code = @country_code
        AND t.txn_type = 'disbursal'
        AND l.product_id NOT IN (43, 75, 300)
        AND l.status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
        AND disabled_cust.record_code IS NULL
)
SELECT
  SUM(l.loan_principal) Repaid_loan_amt
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
  and cust_id in (select cust_id from active_cust)
GROUP BY
  l.country_code;