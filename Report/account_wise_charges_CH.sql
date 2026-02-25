WITH
    'RWA' AS p_country_code,
    202508 AS p_month,

    toDateTime(toStartOfMonth(toDate(concat(toString(p_month), '01')))) AS start_dt,
    addSeconds(addMonths(start_dt, 1), -1) AS end_dt,

    (
        SELECT closure_date
        FROM closure_date_records
        WHERE country_code = p_country_code
          AND status = 'enabled'
          AND month = p_month
        LIMIT 1
    ) AS closure_dt,

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
    acc.acc_number,
    SUM(if(a.acc_txn_type = 'charges', a.dr_amt, a.charges)) AS total_amount

FROM account_stmts a
INNER JOIN accounts acc ON a.account_id = acc.id
LEFT JOIN loans l ON a.loan_doc_id = l.loan_doc_id

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

GROUP BY acc.acc_number
ORDER BY acc.acc_number