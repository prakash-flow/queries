-- MYSQL Version

SET @country_code = 'UGA';

WITH disabled_customers AS (
    SELECT 
        DISTINCT r1.record_code AS cust_id,
        r1.created_by,r1.created_at,r1.remarks,
        JSON_UNQUOTE(JSON_EXTRACT(r1.data_after, '$.reason')) AS reason
    FROM record_audits r1
    JOIN (
        SELECT record_code, MAX(id) AS id
        FROM record_audits
        WHERE created_at <= NOW()
        GROUP BY record_code
    ) r2 ON r1.id = r2.id
    WHERE JSON_EXTRACT(r1.data_after, '$.status') = 'disabled'
      AND r1.country_code = @country_code
),

valid_loans AS (
    SELECT l.loan_doc_id, l.cust_id, l.due_date, l.paid_date, l.loan_appl_date,l.status,l.disbursal_date
    FROM loans l
    WHERE l.country_code = @country_code
#       AND l.product_id NOT IN (43, 75, 300)
      AND l.status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
),

loan_disbursals AS (
    SELECT l.cust_id, MAX(t.txn_date) AS txn_date
    FROM valid_loans l
    JOIN loan_txns t ON l.loan_doc_id = t.loan_doc_id
    WHERE t.txn_type = 'disbursal'
      AND t.txn_date <= NOW()
    GROUP BY l.cust_id
),

switch_disbursals AS (
    SELECT b.cust_id, MAX(t.txn_date) AS txn_date,max(l.delivery_date) as delivery_date
    FROM sales l
    JOIN sales_txns t ON l.sales_doc_id = t.sales_doc_id
    JOIN borrowers b ON b.cust_id = l.cust_id
    WHERE b.country_code = @country_code
      AND l.status = 'delivered'
      AND t.txn_date <= NOW()
    GROUP BY b.cust_id
),

fa_categorized_disabled_customers AS (
    SELECT ld.cust_id, 
           CASE WHEN ld.txn_date >= DATE_SUB(NOW(), INTERVAL 30 DAY) THEN 'active' ELSE 'inactive' END AS status
    FROM loan_disbursals ld
    JOIN disabled_customers dc ON ld.cust_id = dc.cust_id
),

sw_categorized_disabled_customers AS (
    SELECT sd.cust_id,
           CASE WHEN sd.txn_date >= DATE_SUB(NOW(), INTERVAL 30 DAY) THEN 'active' ELSE 'inactive' END AS status,sd.delivery_date
    FROM switch_disbursals sd
    JOIN disabled_customers dc ON sd.cust_id = dc.cust_id
),

latest_loan_per_cust AS (
    SELECT l.*
    FROM valid_loans l
    JOIN (
        SELECT cust_id, MAX(disbursal_date) AS max_disbursal_date
        FROM valid_loans
        GROUP BY cust_id
    ) sub ON l.cust_id = sub.cust_id AND l.disbursal_date = sub.max_disbursal_date
),

late_payment AS (
    SELECT l.cust_id, COUNT(l.loan_doc_id) AS late_payment
    FROM valid_loans l
    LEFT JOIN (
        SELECT loan_doc_id, MAX(txn_date) AS max_txn_date
        FROM loan_txns
        WHERE txn_type = 'payment'
        GROUP BY loan_doc_id
    ) t ON l.loan_doc_id = t.loan_doc_id
    WHERE l.status = 'settled' AND DATEDIFF(t.max_txn_date, l.due_date) > 1
    GROUP BY l.cust_id
),

ontime_repayment AS (
    SELECT l.cust_id,
           ROUND(SUM(IF(DATE(t.max_txn_date) <= DATE_ADD(l.due_date, INTERVAL 1 DAY), 1, 0)) / COUNT(l.loan_doc_id), 2) AS ontime_repayment_rate
    FROM valid_loans l
    LEFT JOIN (
        SELECT loan_doc_id, MAX(txn_date) AS max_txn_date
        FROM loan_txns
        WHERE txn_type = 'payment'
        GROUP BY loan_doc_id
    ) t ON l.loan_doc_id = t.loan_doc_id
    WHERE l.status = 'settled' AND l.paid_date <= NOW()
    GROUP BY l.cust_id
)

# select *  from (

SELECT 
    b.cust_id AS `Cust ID`,
    CASE 
        WHEN l.status = 'overdue' THEN 'overdue'
        WHEN c.status IS NOT NULL THEN c.status
        ELSE 'N/A'
    END AS `Activity Status`,
    b.reg_date AS `Reg date`,
    IFNULL(date(l.disbursal_date) ,'N/A') AS `Churn date`,
    IFNULL(date(d.created_at) ,'N/A') AS `Disable date`,
    IF(l.disbursal_date IS NOT NULL AND d.created_at IS NOT NULL,DATEDIFF(d.created_at, l.disbursal_date),'N/A') AS `Diff between churn and disable`,
    CASE 
        WHEN d.created_by <> 0 THEN 'Manual Disable'
        WHEN d.reason IN ('90_day_inactivity','inactive') THEN 'In-active'
        WHEN d.reason = 'agreement_expired' THEN 'Agreement expiry'
        WHEN d.reason = 'more_than_30_day_overdue' THEN 'Overdue'
        ELSE 'Others'
    END AS `Reason for disable`,
    reason AS `Source Disable Reason`,
    d.remarks AS `Disable Remarks`,
    IFNULL(date(sw.delivery_date) ,'N/A') AS `Switch Delivery Date`,
    IFNULL(sw.status, 'N/A') AS `Float Switch status`,
    b.tot_loans AS `Total loans`,
    IF(lp.late_payment IS NULL, 0, lp.late_payment) AS `Total late loans`,
    IFNULL(o.ontime_repayment_rate, 'N/A') AS `Ontime repayment percentage`
FROM borrowers b
LEFT JOIN fa_categorized_disabled_customers c ON c.cust_id = b.cust_id
LEFT JOIN latest_loan_per_cust l ON l.cust_id = b.cust_id
LEFT JOIN disabled_customers d ON d.cust_id = b.cust_id
LEFT JOIN sw_categorized_disabled_customers sw ON sw.cust_id = b.cust_id
LEFT JOIN late_payment lp ON lp.cust_id = b.cust_id
LEFT JOIN ontime_repayment o ON o.cust_id = b.cust_id
WHERE d.cust_id IS NOT NULL
# ) as aa where   `Activity Status` is not null 
  ;


-- Clickhouse Version

WITH
    'UGA' AS country_code,
    toDateTime(concat(toString(yesterday()), ' 23:59:59')) AS report_ts,

disabled_customers AS (

    SELECT *
    FROM (

        SELECT
            record_code AS cust_id,
            created_by,
            created_at,
            remarks,
            JSONExtractString(data_after,'reason') AS reason,
            JSONExtractString(data_after,'status') AS status,

            row_number() OVER (
                PARTITION BY record_code
                ORDER BY id DESC
            ) AS rn

        FROM record_audits

        WHERE country_code = country_code

    )

    WHERE rn = 1
      AND status = 'disabled'
),

valid_loans AS (

    SELECT
        loan_doc_id,
        cust_id,
        status,
        loan_appl_date,
        disbursal_date,
        due_date,
        paid_date

    FROM loans

    WHERE country_code = country_code
      AND loan_purpose IN ('float_advance','adj_float_advance')
      AND product_id NOT IN (43,75,300)
      AND status NOT IN (
            'voided',
            'hold',
            'pending_disbursal',
            'pending_mnl_dsbrsl'
      )
),

loan_activity AS (

    SELECT
        cust_id,
        max(disbursal_date) AS latest_disbursal_date

    FROM valid_loans

    WHERE disbursal_date IS NOT NULL

    GROUP BY cust_id
),

fa_activity AS (

    SELECT
        la.cust_id,

        if(
            la.latest_disbursal_date >= subtractDays(report_ts,30),
            'active',
            'inactive'
        ) AS status

    FROM loan_activity la

    INNER JOIN disabled_customers dc
        ON dc.cust_id = la.cust_id
),

latest_switch AS (

    SELECT *
    FROM (

        SELECT
            cust_id,
            delivery_date,

            row_number() OVER (
                PARTITION BY cust_id
                ORDER BY delivery_date DESC
            ) AS rn

        FROM sales

        WHERE country_code = country_code
          AND status='delivered'
          AND delivery_date <= report_ts

    )

    WHERE rn = 1
),

switch_activity AS (

    SELECT
        cust_id,
        delivery_date,

        if(
            delivery_date >= subtractDays(report_ts,30),
            'active',
            'inactive'
        ) AS status

    FROM latest_switch
),

latest_loan AS (

    SELECT *
    FROM (

        SELECT
            *,
            row_number() OVER (
                PARTITION BY cust_id
                ORDER BY disbursal_date DESC
            ) AS rn

        FROM valid_loans

    )

    WHERE rn=1
),

latest_payment AS (

    SELECT
        loan_doc_id,
        max(txn_date) AS max_txn_date

    FROM loan_txns

    WHERE txn_type='payment'

    GROUP BY loan_doc_id
),

late_payment AS (

    SELECT
        l.cust_id,
        count() AS late_payment

    FROM valid_loans l

    LEFT JOIN latest_payment p
        ON p.loan_doc_id = l.loan_doc_id

    WHERE l.status='settled'
      AND dateDiff('day', l.due_date, p.max_txn_date) > 1

    GROUP BY l.cust_id
),

ontime_repayment AS (

    SELECT
        l.cust_id,

        round(

            sum(

                if(

                    toDate(p.max_txn_date)
                    <= addDays(toDate(l.due_date),1),

                    1,
                    0
                )

            )

            / nullIf(count(),0),

        2) AS ontime_repayment_rate

    FROM valid_loans l

    LEFT JOIN latest_payment p
        ON p.loan_doc_id = l.loan_doc_id

    WHERE l.status='settled'
      AND l.paid_date <= report_ts

    GROUP BY l.cust_id
)

SELECT

    b.cust_id AS `Cust ID`,

    multiIf(

        ll.status='overdue',
        'overdue',

        fa.status IS NOT NULL,
        fa.status,

        'N/A'

    ) AS `Activity Status`,

    toDate(b.reg_date) AS `Reg Date`,

    coalesce(
        formatDateTime(
            ll.disbursal_date,
            '%Y-%m-%d'
        ),
        'N/A'
    ) AS `Churn Date`,

    coalesce(
        formatDateTime(
            dc.created_at,
            '%Y-%m-%d'
        ),
        'N/A'
    ) AS `Disable Date`,

    coalesce(

        toString(

            dateDiff(
                'day',
                ll.disbursal_date,
                dc.created_at
            )

        ),

        'N/A'

    ) AS `Diff Between Churn And Disable`,

    multiIf(

        dc.created_by != 0,
        'Manual Disable',

        dc.reason IN (
            '90_day_inactivity',
            'inactive'
        ),
        'In-active',

        dc.reason='agreement_expired',
        'Agreement expiry',

        dc.reason='more_than_30_day_overdue',
        'Overdue',

        'Others'

    ) AS `Reason For Disable`,

    multiIf(

    empty(ifNull(dc.reason,'')),
    'N/A',

    startsWith(ifNull(dc.reason,''), '['),

    arrayStringConcat(

        arrayMap(

            x ->
                initcap(
                    replaceRegexpAll(
                        x,
                        '_',
                        ' '
                    )
                ),

            JSONExtract(
                assumeNotNull(dc.reason),
                'Array(String)'
            )

        ),

        ', '

    ),

    initcap(
        replaceRegexpAll(
            ifNull(dc.reason,''),
            '_',
            ' '
        )
    )

) AS `Source Disable Reason`,
    dc.remarks AS `Disable Remarks`,

    coalesce(
        formatDateTime(
            sa.delivery_date,
            '%Y-%m-%d'
        ),
        'N/A'
    ) AS `Switch Delivery Date`,

    coalesce(
        sa.status,
        'N/A'
    ) AS `Float Switch Status`,

    b.tot_loans AS `Total Loans`,

    coalesce(
        lp.late_payment,
        0
    ) AS `Total Late Loans`,

    coalesce(
        toString(
            orx.ontime_repayment_rate
        ),
        'N/A'
    ) AS `Ontime Repayment Percentage`

FROM borrowers b

INNER JOIN disabled_customers dc
    ON dc.cust_id = b.cust_id

LEFT JOIN latest_loan ll
    ON ll.cust_id = b.cust_id

LEFT JOIN fa_activity fa
    ON fa.cust_id = b.cust_id

LEFT JOIN switch_activity sa
    ON sa.cust_id = b.cust_id

LEFT JOIN late_payment lp
    ON lp.cust_id = b.cust_id

LEFT JOIN ontime_repayment orx
    ON orx.cust_id = b.cust_id

WHERE b.country_code = country_code

ORDER BY dc.created_at DESC;