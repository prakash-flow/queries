WITH
    '202510' AS v_month,
    'RWA' AS v_country_code,
    toDate(concat(v_month,'01')) AS first_day,
    toLastDayOfMonth(first_day) AS last_day,

    (
        SELECT closure_date
        FROM closure_date_records
        WHERE country_code = v_country_code
          AND month = v_month
          AND status = 'enabled'
        LIMIT 1
    ) AS realization_date

SELECT
    t.`Customer ID`,
    t.`FA ID`,
    t.`Date of FA`,
    t.`No. of FAs taken till that date`,
    t.`Due Date`,
    t.`Payment Date`,
    t.`FA Amount`,
    t.`Fee Amount`,
    t.`Payment Amount`,
    t.`Paid on-time or not`,
    t.`Overdue Days (if paid late)`,

    if(
      ifNull(
          arrayMax(
              arrayFilter(
                  x -> x <= t.`Last Upgraded Amount`,
                  [70000,100000,150000,200000,300000,400000,500000,600000,700000,800000,900000,1000000,1500000,2000000,2500000,3000000]
              )
          ),
          0
      ) = 0,
      t.`Last Upgraded Amount`,
      arrayMax(
          arrayFilter(
              x -> x <= t.`Last Upgraded Amount`,
              [70000,100000,150000,200000,300000,400000,500000,600000,700000,800000,900000,1000000,1500000,2000000,2500000,3000000]
          )
      )
  ) AS `FA limit at the time of FA`

FROM
(
    SELECT
        l.cust_id AS `Customer ID`,
        l.loan_doc_id AS `FA ID`,
        toDate(l.disbursal_date) AS `Date of FA`,
        l.loan_principal AS `FA Amount`,
        l.flow_fee AS `Fee Amount`,
        toDate(l.due_date) AS `Due Date`,

        -- Correct Payment Amount: pre-aggregate to avoid duplication
        coalesce(p.total_payment, 0) AS `Payment Amount`,

        if(l.status = 'settled', toDate(l.paid_date), NULL) AS `Payment Date`,

        if(l.status = 'settled' AND dateDiff('day', l.due_date, l.paid_date) <= 1, 1, 0)
            AS `Paid on-time or not`,

        if(
            l.status = 'overdue'
            OR (l.status = 'settled' AND dateDiff('day', l.due_date, l.paid_date) > 1),
            dateDiff('day', l.due_date, today()),
            NULL
        ) AS `Overdue Days (if paid late)`,

        count() OVER (
            PARTITION BY l.cust_id
            ORDER BY l.disbursal_date
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS `No. of FAs taken till that date`,

        greatest(
            toFloat64(l.loan_principal),
            ifNull(
                argMaxIf(
                    toFloat64(crl.last_upgraded_amount),
                    crl.created_at,
                    crl.created_at <= l.disbursal_date
                ),
                0
            )
        ) AS `Last Upgraded Amount`

    FROM loans l

    LEFT JOIN loan_txns lt
        ON lt.loan_doc_id = l.loan_doc_id
       AND lt.txn_type = 'disbursal'

    -- Pre-aggregate payments to avoid double counting
    LEFT JOIN (
        SELECT loan_doc_id, sum(ifNull(principal, 0) + ifNull(fee, 0)) AS total_payment
        FROM loan_txns
        WHERE txn_type = 'payment'
        GROUP BY loan_doc_id
    ) p
        ON p.loan_doc_id = l.loan_doc_id

    LEFT JOIN customer_repayment_limits crl
        ON crl.cust_id = l.cust_id

    WHERE l.country_code = v_country_code
      AND l.loan_purpose = 'float_advance'
      AND lt.realization_date IS NOT NULL
      AND lt.realization_date <= realization_date

    GROUP BY
        l.cust_id,
        l.loan_doc_id,
        l.disbursal_date,
        l.loan_principal,
        l.flow_fee,
        l.due_date,
        l.status,
        l.paid_date,
        p.total_payment
) t

WHERE t.`Date of FA` BETWEEN first_day AND last_day

ORDER BY
    t.`Customer ID`,
    t.`Date of FA`;