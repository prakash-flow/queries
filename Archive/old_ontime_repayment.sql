WITH
    'UGA' AS p_country_code,
    toDate('2026-06-30') AS p_as_on_date,

active_cust AS
(
    SELECT DISTINCT
        l.cust_id
    FROM loans l
    INNER JOIN loan_txns t
        ON l.loan_doc_id = t.loan_doc_id
    LEFT JOIN
    (
        SELECT DISTINCT
            r1.record_code
        FROM record_audits r1
        INNER JOIN
        (
            SELECT
                record_code,
                max(id) AS id
            FROM record_audits
            WHERE toDate(created_at) <= p_as_on_date
            GROUP BY record_code
        ) r2
            ON r1.id = r2.id
        WHERE JSONExtractString(r1.data_after, 'status') = 'disabled'
    ) disabled_cust
        ON l.cust_id = disabled_cust.record_code
    WHERE
        dateDiff('day', toDate(t.txn_date), p_as_on_date) <= 30
        AND toDate(t.txn_date) <= p_as_on_date
        AND l.country_code = p_country_code
        AND t.txn_type = 'disbursal'
        AND l.loan_purpose = 'float_advance'
        AND l.product_id NOT IN (43,75,300)
        AND l.status NOT IN
        (
            'voided',
            'hold',
            'pending_disbursal',
            'pending_mnl_dsbrsl'
        )
        AND disabled_cust.record_code IS NULL
),

loans_taken AS
(
    SELECT
        ac.cust_id AS cust_id,

        count(l.loan_doc_id) AS overall_loans_taken,

        sum(
            if(
                toDate(l.disbursal_date) >= toStartOfMonth(addMonths(p_as_on_date, -2)),
                1,
                0
            )
        ) AS last_3m_loans_taken,

        sum(
            if(
                toDate(l.disbursal_date) >= toStartOfMonth(addMonths(p_as_on_date, -2))
                AND l.status = 'settled'
                AND toDate(l.paid_date) <= addDays(toDate(l.due_date), 1),
                1,
                0
            )
        ) AS last_3m_ontime_paid_count

    FROM active_cust ac

    LEFT JOIN loans l
        ON ac.cust_id = l.cust_id
        AND l.loan_purpose = 'float_advance'
        AND l.country_code = p_country_code
        AND l.product_id NOT IN (43,75,300)
        AND l.status NOT IN
        (
            'voided',
            'hold',
            'pending_disbursal',
            'pending_mnl_dsbrsl'
        )
        AND toDate(l.disbursal_date) <= p_as_on_date

    GROUP BY ac.cust_id
)

SELECT
    ac.cust_id AS `Cust Id`,

    if(
        count(l.loan_doc_id) = 0,
        0,
        round(
            100.0 *
            sum(
                if(
                    toDate(l.paid_date) <= addDays(toDate(l.due_date), 1),
                    1,
                    0
                )
            ) / count(l.loan_doc_id),
            2
        )
    ) AS `Overall Ontime Repayment Rate`,

    sum(
        if(
            toDate(l.paid_date) <= addDays(toDate(l.due_date), 1),
            1,
            0
        )
    ) AS `Overall Ontime Settle Count`,

    count(l.loan_doc_id) AS `Overall Settled Count`,

    any(lt.overall_loans_taken) AS `Overall Loans Taken`,

    if(
        sum(if(toDate(l.due_date) >= toStartOfMonth(addMonths(p_as_on_date, -2)), 1, 0)) = 0,
        0,
        round(
            100.0 *
            sum(
                if(
                    toDate(l.due_date) >= toStartOfMonth(addMonths(p_as_on_date, -2))
                    AND toDate(l.paid_date) <= addDays(toDate(l.due_date), 1),
                    1,
                    0
                )
            ) / sum(if(toDate(l.due_date) >= toStartOfMonth(addMonths(p_as_on_date, -2)), 1, 0)),
            2
        )
    ) AS `Last 3M Ontime Repayment Rate`,

    sum(
        if(
            toDate(l.due_date) >= toStartOfMonth(addMonths(p_as_on_date, -2))
            AND toDate(l.paid_date) <= addDays(toDate(l.due_date), 1),
            1,
            0
        )
    ) AS `Last 3M Ontime Settle Count`,

    sum(
        if(toDate(l.due_date) >= toStartOfMonth(addMonths(p_as_on_date, -2)), 1, 0)
    ) AS `Last 3M Settled Count`,

    any(lt.last_3m_loans_taken) AS `Last 3M Loans Taken`,
    any(lt.last_3m_ontime_paid_count) AS `Last 3M Ontime Paid Count`

FROM active_cust ac

LEFT JOIN loans l
    ON ac.cust_id = l.cust_id
    AND l.status = 'settled'
    AND l.loan_purpose = 'float_advance'
    AND l.country_code = p_country_code
    AND l.product_id NOT IN (43,75,300)
    AND toDate(l.paid_date) <= p_as_on_date

LEFT JOIN loans_taken lt
    ON ac.cust_id = lt.cust_id

GROUP BY ac.cust_id

ORDER BY ac.cust_id;