WITH
    'RWA' AS p_country_code,
    202507 AS p_month,

    -- month start
    toDateTime(toStartOfMonth(toDate(concat(toString(p_month), '01')))) AS start_dt,

    -- month end
    addSeconds(addMonths(start_dt, 1), -1) AS end_dt,

    -- current closure
    (
        SELECT closure_date
        FROM closure_date_records
        WHERE country_code = p_country_code
          AND status = 'enabled'
          AND month = p_month
        LIMIT 1
    ) AS closure_dt,

    -- previous closure
    (
        SELECT closure_date
        FROM closure_date_records
        WHERE country_code = p_country_code
          AND status = 'enabled'
          AND month = toYYYYMM(addMonths(start_dt, -1))
        LIMIT 1
    ) AS prev_closure_dt,

    base_transaction AS (
        SELECT
            a.id,
            a.loan_doc_id
        FROM account_stmts a
        INNER JOIN loan_txns lt ON a.stmt_txn_id = lt.txn_id
        WHERE a.country_code = p_country_code
          AND lt.country_code = p_country_code
          AND a.stmt_txn_date >= start_dt
          AND a.stmt_txn_date <= end_dt
          AND a.realization_date <= closure_dt
          AND a.acc_txn_type IN (
                'excess_reversal',
                'disbursal',
                'payment',
                'af_disbursal',
                'af_payment',
                'duplicate_disbursal'
          )
          AND lt.txn_type = a.acc_txn_type
    )

SELECT
    acc.acc_number AS "Account",

    coalesce(a.loan_doc_id, linked.loan_doc_id) AS "Loan ID",

  CASE
      WHEN l.loan_purpose = 'float_advance' THEN 'Float Advance'
      WHEN l.loan_purpose = 'adj_float_advance' THEN 'Kula'
      WHEN l.loan_purpose = 'growth_financing' THEN 'Kula Plus'
      WHEN l.loan_purpose = 'asset_financing' THEN 'Kula Asset'
      ELSE l.loan_purpose
  END AS "Loan Type",
    l.cust_id AS "Customer ID",
    a.stmt_txn_id AS "Transaction ID",
    DATE(a.stmt_txn_date) AS "Transaction Date",
    a.acc_prvdr_code AS "Account Provider Code",

    if(a.acc_txn_type = 'charges', a.dr_amt, a.charges) AS "Amount"

FROM account_stmts a

INNER JOIN accounts acc
    ON a.account_id = acc.id

LEFT JOIN account_stmts linked
    ON toUInt32OrNull(a.link_id) = linked.id

LEFT JOIN loans l
    ON coalesce(a.loan_doc_id, linked.loan_doc_id) = l.loan_doc_id

WHERE a.country_code = p_country_code
  AND (
        (
            a.stmt_txn_date >= start_dt
            AND a.stmt_txn_date <= end_dt
            AND a.realization_date <= closure_dt
        )
        OR (
            a.stmt_txn_date < start_dt
            AND a.realization_date > prev_closure_dt
            AND a.realization_date <= closure_dt
        )
  )
  AND a.stmt_txn_date <= end_dt
  AND (
        a.link_id IN (SELECT id FROM base_transaction)
        OR a.loan_doc_id IN (SELECT loan_doc_id FROM base_transaction)
  )
  AND (
        a.acc_txn_type = 'charges'
        OR a.charges > 0
  )

ORDER BY
    coalesce(a.loan_doc_id, linked.loan_doc_id),
    a.stmt_txn_date