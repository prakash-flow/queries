WITH
    'UGA' AS p_country_code,
    toDate('2026-06-30') AS p_as_on_date,

disabled_cust AS
(
    SELECT DISTINCT
        r1.record_code AS cust_id
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
),

active_cust AS
(
    SELECT DISTINCT
        al.cust_id AS cust_id
    FROM loans al
    INNER JOIN loan_txns t
        ON al.loan_doc_id = t.loan_doc_id
    LEFT JOIN disabled_cust d
        ON al.cust_id = d.cust_id
    WHERE
        dateDiff('day', toDate(t.txn_date), p_as_on_date) <= 30
        AND toDate(t.txn_date) <= p_as_on_date
        AND al.country_code = p_country_code
        AND t.txn_type = 'disbursal'
        AND al.loan_purpose = 'float_advance'
        AND al.product_id NOT IN (43, 75, 300, 765, 766)
        AND al.status NOT IN
        (
            'voided',
            'hold',
            'pending_disbursal',
            'pending_mnl_dsbrsl'
        )
        AND d.cust_id IS NULL
),

base_query AS
(
    SELECT
        ac.cust_id AS cust_id,
        l.loan_doc_id AS loan_doc_id,
        toDate(l.due_date) AS due_date,

        ifNull(l.loan_principal, 0)
        + ifNull(l.flow_fee, 0)
        + ifNull(l.charges, 0) AS expected_amount,

        sum(
            ifNull(lt.principal, 0)
            + ifNull(lt.fee, 0)
            + ifNull(lt.charges, 0)
        ) AS paid_amount,

        sum(
            if(
                toDate(lt.txn_date) <= addDays(toDate(l.due_date), 1),
                ifNull(lt.principal, 0)
                + ifNull(lt.fee, 0)
                + ifNull(lt.charges, 0),
                0
            )
        ) AS ontime_paid_amount,

        sum(
            if(
                toDate(lt.txn_date) <= addDays(toDate(l.due_date), 5),
                ifNull(lt.principal, 0)
                + ifNull(lt.fee, 0)
                + ifNull(lt.charges, 0),
                0
            )
        ) AS paid_within_5_days_amount

    FROM active_cust ac

    LEFT JOIN loans l
        ON ac.cust_id = l.cust_id
       AND l.due_date <= toDateTime(concat(toString(p_as_on_date), ' 23:59:59'))
       AND l.loan_purpose = 'float_advance'
       AND l.country_code = p_country_code
       AND l.product_id NOT IN (43, 75, 300, 765, 766)
       AND l.status NOT IN (
            'voided',
            'hold',
            'pending_disbursal',
            'pending_mnl_dsbrsl'
        )

    LEFT JOIN loan_txns lt
        ON l.loan_doc_id = lt.loan_doc_id
       AND lt.txn_type = 'payment'

    GROUP BY
        ac.cust_id,
        l.loan_doc_id,
        due_date,
        expected_amount
)

SELECT
    cust_id AS `Cust Id`,
    count(loan_doc_id) AS `Loan Count`,
    sum(expected_amount) AS `Total Due Amount`,
    sum(ontime_paid_amount) AS `Ontime Repaid Amount`,
    sum(paid_within_5_days_amount) AS `Paid Within 5 Days Amount`,
    round(
        sum(ontime_paid_amount) * 100.0 / nullIf(sum(expected_amount), 0),
        2
    ) AS `Ontime Repayment Rate`,
    sum(
        if(ontime_paid_amount >= expected_amount, 1, 0)
    ) AS `Ontime Settle Count`
FROM base_query
GROUP BY cust_id
ORDER BY cust_id;
