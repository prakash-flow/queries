WITH
    'UGA' AS p_country_code,
    toDate('2026-06-30') AS p_as_on_date,

active_cust AS
(
    SELECT DISTINCT
        l.cust_id
    FROM loans AS l

    INNER JOIN loan_txns AS t
        ON l.loan_doc_id = t.loan_doc_id

    LEFT JOIN
    (
        SELECT DISTINCT
            r1.record_code
        FROM record_audits AS r1

        INNER JOIN
        (
            SELECT
                record_code,
                max(id) AS id
            FROM record_audits
            WHERE toDate(created_at) <= p_as_on_date
            GROUP BY record_code
        ) AS r2
            ON r1.id = r2.id

        WHERE JSONExtractString(r1.data_after, 'status') = 'disabled'
    ) AS disabled_cust
        ON l.cust_id = disabled_cust.record_code

    WHERE
        dateDiff('day', toDate(t.txn_date), p_as_on_date) <= 30
        AND toDate(t.txn_date) <= p_as_on_date
        AND l.country_code = p_country_code
        AND t.txn_type = 'disbursal'
        AND l.loan_purpose = 'float_advance'
        AND l.product_id NOT IN (43, 75, 300)
        AND l.status NOT IN (
            'voided',
            'hold',
            'pending_disbursal',
            'pending_mnl_dsbrsl'
        )
        AND disabled_cust.record_code IS NULL
),
  
loan_summary AS
(
    SELECT
        l.cust_id,
        l.loan_doc_id,
        toDate(l.due_date) AS due_date,

        max(
            ifNull(l.loan_principal, 0)
            + ifNull(l.flow_fee, 0)
            + ifNull(l.charges, 0)
        ) AS due_amount,

        sum(
            if(
                toDate(lt.txn_date) <= addDays(toDate(l.due_date), 1),
                ifNull(lt.principal, 0)
                + ifNull(lt.fee, 0)
                + ifNull(lt.charges, 0),
                0
            )
        ) AS ontime_paid_amount

    FROM loans l

    LEFT JOIN loan_txns lt
        ON l.loan_doc_id = lt.loan_doc_id
       AND lt.txn_type = 'payment'

    WHERE
        l.cust_id IN (SELECT ac.cust_id FROM active_cust ac)
        AND l.disbursal_date <= toDateTime(concat(toString(p_as_on_date), ' 23:59:59'))
        AND l.country_code = p_country_code
        AND l.loan_purpose = 'float_advance'
        AND l.product_id NOT IN (43, 75, 300, 765, 766)
        AND l.status NOT IN (
            'voided',
            'hold',
            'pending_disbursal',
            'pending_mnl_dsbrsl'
        )

    GROUP BY
        l.cust_id,
        l.loan_doc_id,
        due_date
)

SELECT
    cust_id AS `Cust Id`,

    sum(due_amount) AS `Overall Due Amount`,

    sum(ontime_paid_amount) AS `Overall Ontime Paid Amount`,

    round(
        sum(ontime_paid_amount) * 100
        / nullIf(sum(due_amount), 0),
        2
    ) AS `Overall Ontime Repayment Rate`,

    -- Last 3 Months
    sum(
        if(
            due_date >= toStartOfMonth(addMonths(p_as_on_date, -2)),
            due_amount,
            0
        )
    ) AS `Last 3M Due Amount`,

    sum(
        if(
            due_date >= toStartOfMonth(addMonths(p_as_on_date, -2)),
            ontime_paid_amount,
            0
        )
    ) AS `Last 3M Ontime Paid Amount`,

    round(
        sum(
            if(
                due_date >= toStartOfMonth(addMonths(p_as_on_date, -2)),
                ontime_paid_amount,
                0
            )
        ) * 100
        /
        nullIf(
            sum(
                if(
                    due_date >= toStartOfMonth(addMonths(p_as_on_date, -2)),
                    due_amount,
                    0
                )
            ),
            0
        ),
        2
    ) AS `Last 3M Ontime Repayment Rate`

FROM loan_summary
GROUP BY cust_id
ORDER BY cust_id;