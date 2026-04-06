-- the query gets the calender weekly collections/ paid amounts for the input range only for fa and Kula

WITH params AS (
    SELECT 
        'UGA' AS country_code,
        toDate('2025-12-01') AS start_date,
        toDate('2026-04-04') AS end_date
),

closure AS (
    SELECT coalesce(
        max(closure_date),
        parseDateTimeBestEffort(
            concat(toString((SELECT end_date FROM params)), ' 23:59:59')
        )
    ) AS closure_date
    FROM flow_api.closure_date_records
    WHERE status='enabled'
      AND country_code = (SELECT country_code FROM params)
      AND month = toYear((SELECT end_date FROM params)) * 100
                + toMonth((SELECT end_date FROM params))
),

loan_base AS (
    SELECT
        l.loan_doc_id,
        toDate(l.due_date) AS due_date,

        subtractDays(
            toDate(l.due_date),
            toDayOfWeek(toDate(l.due_date)) % 7
        ) AS week_start,

        addDays(
            subtractDays(
                toDate(l.due_date),
                toDayOfWeek(toDate(l.due_date)) % 7
            ),
            6
        ) AS week_end,

        (l.loan_principal + l.flow_fee) AS due_amount

    FROM flow_api.loans l

    JOIN (
        SELECT loan_doc_id
        FROM flow_api.loan_txns
        WHERE txn_type = 'disbursal'
          AND realization_date <= (SELECT closure_date FROM closure)
        GROUP BY loan_doc_id
    ) lt
    ON lt.loan_doc_id = l.loan_doc_id

    WHERE l.country_code = (SELECT country_code FROM params)
      AND l.loan_purpose IN ('float_advance','adj_float_advance')
      AND l.status NOT IN (
            'voided','hold',
            'pending_disbursal','pending_mnl_dsbrsl'
      )
      AND l.product_id NOT IN (
          SELECT id
          FROM flow_api.loan_products
          WHERE product_type = 'float_vending'
      )
      AND toDate(l.due_date)
          BETWEEN (SELECT start_date FROM params)
              AND (SELECT end_date FROM params)
),

txns AS (
    SELECT
        lt.loan_doc_id,
        toDate(lt.txn_date) AS txn_date,

        (
            IF(lt.txn_type='payment', ifNull(lt.principal,0), 0)
            +
            IF(
                lt.txn_type IN ('payment','fee_waiver'),
                ifNull(lt.fee,0),
                0
            )
        ) AS amount_paid,

        toDate(lt.realization_date) AS realization_date,
        lb.week_end

    FROM flow_api.loan_txns lt

    JOIN loan_base lb
    ON lb.loan_doc_id = lt.loan_doc_id

    WHERE lt.realization_date <= (SELECT closure_date FROM closure)
      AND lt.country_code = (SELECT country_code FROM params)
      AND lt.txn_type IN ('payment','fee_waiver')

      AND (
            (
              dateDiff('day', lb.due_date, lt.txn_date) <= 1
              AND toDate(lt.realization_date) <= lb.week_end
            )
            OR
            (
              dateDiff('day', lb.due_date, lt.txn_date) > 1
              AND toDate(lt.realization_date)
                  <= (SELECT closure_date FROM closure)
            )
          )
),

bucketed_collections AS (
    SELECT
        lb.loan_doc_id,
        lb.week_start,
        lb.week_end,
        lb.due_amount,

        SUM(IF(dateDiff('day', lb.due_date, t.txn_date) <= 0,
               t.amount_paid, 0)) AS paid_on_time_amt,

        SUM(IF(dateDiff('day', lb.due_date, t.txn_date) = 1,
               t.amount_paid, 0)) AS paid_1_day_late_amt,

        SUM(IF(dateDiff('day', lb.due_date, t.txn_date) BETWEEN 2 AND 5,
               t.amount_paid, 0)) AS paid_2_5_amt,

        SUM(IF(dateDiff('day', lb.due_date, t.txn_date) BETWEEN 6 AND 15,
               t.amount_paid, 0)) AS paid_6_15_amt,

        SUM(IF(dateDiff('day', lb.due_date, t.txn_date) BETWEEN 16 AND 30,
               t.amount_paid, 0)) AS paid_16_30_amt,

        SUM(IF(dateDiff('day', lb.due_date, t.txn_date) > 30,
               t.amount_paid, 0)) AS paid_30_plus_amt,

        SUM(t.amount_paid) AS total_collected

    FROM loan_base lb

    LEFT JOIN txns t
    ON lb.loan_doc_id = t.loan_doc_id

    GROUP BY
        lb.loan_doc_id,
        lb.week_start,
        lb.week_end,
        lb.due_amount
),

final AS (
    SELECT
        week_start,
        week_end,

        SUM(due_amount) AS amount_due,

        SUM(paid_on_time_amt) AS paid_on_time_amt,
        SUM(paid_1_day_late_amt) AS paid_1_day_late_amt,
        SUM(paid_2_5_amt) AS paid_2_5_amt,
        SUM(paid_6_15_amt) AS paid_6_15_amt,
        SUM(paid_16_30_amt) AS paid_16_30_amt,
        SUM(paid_30_plus_amt) AS paid_30_plus_amt,

        SUM(greatest(due_amount - total_collected, 0))
            AS not_paid_amt

    FROM bucketed_collections

    GROUP BY
        week_start,
        week_end
)

SELECT
    formatDateTime(week_start, '%b %y') AS `Month & Year`,

    concat('W', toString(toISOWeek(week_start))) AS `Week`,

    concat(
        formatDateTime(week_start, '%d %b %Y'),
        ' - ',
        formatDateTime(week_end, '%d %b %Y')
    ) AS `Week Date Range`,

    amount_due AS `Amount due during the week`,
    
    round(paid_on_time_amt / amount_due, 6) AS `paid on time %`,
    round(paid_1_day_late_amt / amount_due, 6) AS `paid 1 day late %`,
    round(paid_2_5_amt / amount_due, 6) AS `paid between 2 and 5 %`,
    round(paid_6_15_amt / amount_due, 6) AS `paid between 6 and 15 %`,
    round(paid_16_30_amt / amount_due, 6) AS `paid between 16 and 30 %`,
    round(paid_30_plus_amt / amount_due, 6) AS `paid after 30 days %`,
    round(not_paid_amt / amount_due, 6) AS `not paid yet %`,

    paid_on_time_amt AS `paid on time`,
    paid_1_day_late_amt AS `paid 1 day late`,
    paid_2_5_amt AS `paid between 2 and 5`,
    paid_6_15_amt AS `paid between 6 and 15`,
    paid_16_30_amt AS `paid between 16 and 30`,
    paid_30_plus_amt AS `paid after 30 days`,
    not_paid_amt AS `not paid yet`

FROM final

ORDER BY week_start;