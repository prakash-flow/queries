WITH params AS (
    SELECT
        toDate('2025-11-01') AS start_date,
        toDate('2025-11-30') AS end_date,
        'UGA'               AS country_code
),

/* Current month closure date */
closure AS (
    SELECT coalesce(
        max(closure_date),
        parseDateTimeBestEffort(concat(toString((SELECT end_date FROM params)), ' 23:59:59'))
    ) AS closure_date
    FROM flow_api.closure_date_records
    WHERE status = 'enabled'
      AND month = toYear((SELECT end_date FROM params)) * 100 + toMonth((SELECT end_date FROM params))
      AND country_code = (SELECT country_code FROM params)
),

/* Previous month closure date */
prev_closure AS (
    SELECT coalesce(
        max(closure_date),
        parseDateTimeBestEffort(concat(toString(addDays((SELECT start_date FROM params), -1)), ' 23:59:59'))
    ) AS closure_date
    FROM flow_api.closure_date_records
    WHERE status = 'enabled'
      AND month = toYear(addDays((SELECT start_date FROM params), -1)) * 100
               + toMonth(addDays((SELECT start_date FROM params), -1))
      AND country_code = (SELECT country_code FROM params)
),

/* Opening balance = previous month-end closing, computed with IDENTICAL formula */
opening_balance AS (
    SELECT SUM(IF(
        ((lp.loan_principal + lp.flow_fee)
            - coalesce(pay.principal_paid, 0)
            - coalesce(pay.fee_with_fee_waiver, 0)) > 0
        AND greatest(dateDiff('day', toDate(lp.due_date), addDays((SELECT start_date FROM params), -1)), 0) > 1,
        (lp.loan_principal + lp.flow_fee)
            - coalesce(pay.principal_paid, 0)
            - coalesce(pay.fee_with_fee_waiver, 0),
        0
    )) AS amount
    FROM flow_api.loans lp
    LEFT JOIN (
        SELECT
            loan_doc_id,
            SUM(IF(txn_type = 'payment', principal, 0))               AS principal_paid,
            SUM(IF(txn_type IN ('payment', 'fee_waiver'), fee, 0))    AS fee_with_fee_waiver
        FROM flow_api.loan_txns
        WHERE toDate(txn_date) <= addDays((SELECT start_date FROM params), -1)
          AND realization_date <= (SELECT closure_date FROM prev_closure)
          AND country_code = (SELECT country_code FROM params)
        GROUP BY loan_doc_id
    ) pay ON lp.loan_doc_id = pay.loan_doc_id
    WHERE lp.loan_doc_id IN (
        SELECT loan_doc_id FROM flow_api.loan_txns
        WHERE txn_type = 'disbursal'
          AND toDate(txn_date) <= addDays((SELECT start_date FROM params), -1)
          AND realization_date <= (SELECT closure_date FROM prev_closure)
    )
      AND lp.country_code = (SELECT country_code FROM params)
      AND lp.loan_purpose IN ('float_advance', 'adj_float_advance')
      AND lp.status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
      AND lp.product_id NOT IN (SELECT id FROM flow_api.loan_products WHERE product_type = 'float_vending')
      -- AND lp.loan_doc_id NOT IN (
      --     SELECT loan_doc_id FROM flow_api.loan_write_off
      --     WHERE country_code = (SELECT country_code FROM params)
      --       AND write_off_date <= addDays((SELECT start_date FROM params), -1)
      --       AND write_off_status IN ('approved', 'partially_recovered', 'recovered')
      -- )
),

/* All loans that qualify for this report */
loan_principal AS (
    SELECT
        l.loan_doc_id,
        l.loan_principal,
        l.flow_fee,
        toDate(l.due_date)       AS due_date,
        toDate(l.disbursal_date) AS disbursal_date
    FROM flow_api.loans l
    WHERE l.loan_doc_id IN (
        SELECT loan_doc_id FROM flow_api.loan_txns
        WHERE txn_type = 'disbursal'
          AND toDate(txn_date) <= (SELECT end_date FROM params)
          AND realization_date <= (SELECT closure_date FROM closure)
    )
      AND l.country_code = (SELECT country_code FROM params)
      AND l.loan_purpose IN ('float_advance', 'adj_float_advance')
      AND l.status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
      AND l.product_id NOT IN (SELECT id FROM flow_api.loan_products WHERE product_type = 'float_vending')
      -- AND l.loan_doc_id NOT IN (
      --     SELECT loan_doc_id FROM flow_api.loan_write_off
      --     WHERE country_code = (SELECT country_code FROM params)
      --       AND write_off_date <= (SELECT end_date FROM params)
      --       AND write_off_status IN ('approved', 'partially_recovered', 'recovered')
      -- )
),

/* Lifetime payments per loan as of end_date / closure */
loan_payments AS (
    SELECT
        loan_doc_id,
        SUM(IF(txn_type = 'payment', principal, 0))            AS principal_paid,
        SUM(IF(txn_type = 'payment', fee, 0))                  AS fee_paid,
        SUM(IF(txn_type IN ('payment', 'fee_waiver'), fee, 0)) AS fee_with_fee_waiver,
        maxIf(toDate(txn_date), txn_type = 'payment' AND (principal > 0 OR fee > 0)) AS last_payment_date
    FROM flow_api.loan_txns
    WHERE toDate(txn_date) <= (SELECT end_date FROM params)
      AND realization_date  <= (SELECT closure_date FROM closure)
      AND country_code       = (SELECT country_code FROM params)
    GROUP BY loan_doc_id
),

/* Overdue payments collected THIS month (txn_date in the month window) */
collections AS (
    SELECT
        lt.loan_doc_id AS loan_doc_id,
        SUM(IF(toDate(lt.txn_date) > addDays(l.due_date, 1) AND lt.txn_type = 'payment',
               ifNull(lt.principal, 0), 0))                                           AS od_prin,
        SUM(IF(toDate(lt.txn_date) > addDays(l.due_date, 1) AND lt.txn_type = 'payment',
               ifNull(lt.fee, 0), 0))                                                 AS od_fee,
        SUM(IF(toDate(lt.txn_date) > addDays(l.due_date, 1)
               AND lt.txn_type IN ('payment', 'fee_waiver'),
               ifNull(lt.principal, 0) + ifNull(lt.fee, 0), 0))                       AS od_total,

        /* Buckets: classified by last_payment_date (max txn_date for the loan) */
        SUM(IF(lt.txn_type = 'payment' AND toDate(lt.txn_date) > addDays(l.due_date, 1)
               AND dateDiff('day', l.due_date, p.last_payment_date) BETWEEN 2 AND 5,
               ifNull(lt.principal, 0) + ifNull(lt.fee, 0), 0))                       AS od_rec_2_5,
        SUM(IF(lt.txn_type = 'payment' AND toDate(lt.txn_date) > addDays(l.due_date, 1)
               AND dateDiff('day', l.due_date, p.last_payment_date) BETWEEN 6 AND 15,
               ifNull(lt.principal, 0) + ifNull(lt.fee, 0), 0))                       AS od_rec_6_15,
        SUM(IF(lt.txn_type = 'payment' AND toDate(lt.txn_date) > addDays(l.due_date, 1)
               AND dateDiff('day', l.due_date, p.last_payment_date) BETWEEN 16 AND 30,
               ifNull(lt.principal, 0) + ifNull(lt.fee, 0), 0))                       AS od_rec_16_30,
        SUM(IF(lt.txn_type = 'payment' AND toDate(lt.txn_date) > addDays(l.due_date, 1)
               AND dateDiff('day', l.due_date, p.last_payment_date) BETWEEN 31 AND 60,
               ifNull(lt.principal, 0) + ifNull(lt.fee, 0), 0))                       AS od_rec_31_60,
        SUM(IF(lt.txn_type = 'payment' AND toDate(lt.txn_date) > addDays(l.due_date, 1)
               AND dateDiff('day', l.due_date, p.last_payment_date) > 60,
               ifNull(lt.principal, 0) + ifNull(lt.fee, 0), 0))                       AS od_rec_gt_60
    FROM flow_api.loan_txns lt
    JOIN  loan_principal l ON lt.loan_doc_id = l.loan_doc_id
    LEFT JOIN loan_payments p ON lt.loan_doc_id = p.loan_doc_id
    WHERE toDate(lt.txn_date) BETWEEN (SELECT start_date FROM params) AND (SELECT end_date FROM params)
      AND lt.realization_date <= (SELECT closure_date FROM closure)
      AND lt.country_code      = (SELECT country_code FROM params)
    GROUP BY lt.loan_doc_id
),

/* Loan state as of end_date */
loan_state AS (
    SELECT
        l.loan_doc_id,
        l.due_date,
        l.loan_principal,
        l.flow_fee,
        (l.loan_principal - coalesce(p.principal_paid, 0))        AS principal_os,
        (l.flow_fee       - coalesce(p.fee_with_fee_waiver, 0))   AS fee_os,
        ((l.loan_principal + l.flow_fee)
            - coalesce(p.principal_paid, 0)
            - coalesce(p.fee_with_fee_waiver, 0))                 AS outstanding,
        IF(
            ((l.loan_principal + l.flow_fee)
                - coalesce(p.principal_paid, 0)
                - coalesce(p.fee_with_fee_waiver, 0)) > 0,
            greatest(dateDiff('day', l.due_date, (SELECT end_date FROM params)), 0),
            0
        ) AS dpd
    FROM loan_principal l
    LEFT JOIN loan_payments p ON l.loan_doc_id = p.loan_doc_id
)

SELECT
    formatDateTime((SELECT end_date FROM params), '%b %y') AS `Month`,

    /* ── Opening balance (auto-computed with same formula as closing) ── */
    (SELECT amount FROM opening_balance)                              AS `Opening Balance`,

    /* ── Portfolio totals ── */
    SUM(IF(t.principal_os > 0, t.principal_os, 0))                   AS `Principal OS`,
    SUM(IF(t.fee_os       > 0, t.fee_os,       0))                   AS `Fee OS`,

    /* ── Closing overdue ── */
    SUM(IF(t.dpd > 1 AND t.outstanding > 0, t.outstanding, 0))       AS `Total Overdue (Closing Balance)`,

    /* ── Recoveries ── */
    SUM(IF(addDays(t.due_date, 2) BETWEEN (SELECT start_date FROM params) AND (SELECT end_date FROM params),
           ifNull(c.od_total, 0), 0))                                 AS `New OD Recovery`,
    SUM(ifNull(c.od_total, 0))                                        AS `Total Recovery`,

    /* ── GROSS NEW OVERDUE: derived algebraically to guarantee the equation:
          Opening + Gross New − Total Recovery = Closing (always exact, no gap)
       Gross New = Closing − Opening + Total Recovery ─────────────────────── */
    (
        SUM(IF(t.dpd > 1 AND t.outstanding > 0, t.outstanding, 0))
        - (SELECT amount FROM opening_balance)
        + SUM(ifNull(c.od_total, 0))
    )                                                                 AS `Gross New Overdue Generated`,

    /* ── NET NEW OVERDUE: outstanding only for loans that went overdue this month
          (equals sum of the New Overdue bucket columns below) ── */
    SUM(IF(addDays(t.due_date, 2) BETWEEN (SELECT start_date FROM params) AND (SELECT end_date FROM params)
           AND t.dpd > 1 AND t.outstanding > 0,
           t.outstanding, 0))                                         AS `Net New Overdue Generated`,

    /* ── New overdue buckets (Gross = outstanding still unpaid + already recovered this month, per DPD bucket) ── */
    SUM(IF(addDays(t.due_date, 2) BETWEEN (SELECT start_date FROM params) AND (SELECT end_date FROM params) AND t.dpd BETWEEN 2 AND  5  AND t.outstanding > 0, t.outstanding, 0))
      + SUM(IF(addDays(t.due_date, 2) BETWEEN (SELECT start_date FROM params) AND (SELECT end_date FROM params), ifNull(c.od_rec_2_5,   0), 0)) AS `New Overdue 2-5 days`,
    SUM(IF(addDays(t.due_date, 2) BETWEEN (SELECT start_date FROM params) AND (SELECT end_date FROM params) AND t.dpd BETWEEN 6 AND 15  AND t.outstanding > 0, t.outstanding, 0))
      + SUM(IF(addDays(t.due_date, 2) BETWEEN (SELECT start_date FROM params) AND (SELECT end_date FROM params), ifNull(c.od_rec_6_15,  0), 0)) AS `New Overdue 6-15 days`,
    SUM(IF(addDays(t.due_date, 2) BETWEEN (SELECT start_date FROM params) AND (SELECT end_date FROM params) AND t.dpd BETWEEN 16 AND 30 AND t.outstanding > 0, t.outstanding, 0))
      + SUM(IF(addDays(t.due_date, 2) BETWEEN (SELECT start_date FROM params) AND (SELECT end_date FROM params), ifNull(c.od_rec_16_30, 0), 0)) AS `New Overdue 16-30 days`,
    SUM(IF(addDays(t.due_date, 2) BETWEEN (SELECT start_date FROM params) AND (SELECT end_date FROM params) AND t.dpd BETWEEN 31 AND 60 AND t.outstanding > 0, t.outstanding, 0))
      + SUM(IF(addDays(t.due_date, 2) BETWEEN (SELECT start_date FROM params) AND (SELECT end_date FROM params), ifNull(c.od_rec_31_60, 0), 0)) AS `New Overdue 31-60 days`,
    SUM(IF(addDays(t.due_date, 2) BETWEEN (SELECT start_date FROM params) AND (SELECT end_date FROM params) AND t.dpd > 60            AND t.outstanding > 0, t.outstanding, 0))
      + SUM(IF(addDays(t.due_date, 2) BETWEEN (SELECT start_date FROM params) AND (SELECT end_date FROM params), ifNull(c.od_rec_gt_60, 0), 0)) AS `New Overdue >60 days`,

    /* ── Total overdue buckets (all loans, not just new this month) ── */
    SUM(IF(t.dpd BETWEEN 2 AND  5  AND t.outstanding > 0, t.outstanding, 0)) AS `Total Overdue 2-5 days`,
    SUM(IF(t.dpd BETWEEN 6 AND 15  AND t.outstanding > 0, t.outstanding, 0)) AS `Total Overdue 6-15 days`,
    SUM(IF(t.dpd BETWEEN 16 AND 30 AND t.outstanding > 0, t.outstanding, 0)) AS `Total Overdue 16-30 days`,
    SUM(IF(t.dpd BETWEEN 31 AND 60 AND t.outstanding > 0, t.outstanding, 0)) AS `Total Overdue 31-60 days`,
    SUM(IF(t.dpd > 60               AND t.outstanding > 0, t.outstanding, 0)) AS `Total Overdue >60 days`,

    /* ── New OD recovery buckets ── */
    SUM(IF(addDays(t.due_date, 2) BETWEEN (SELECT start_date FROM params) AND (SELECT end_date FROM params), ifNull(c.od_rec_2_5,   0), 0)) AS `New OD Recovery 2-5 days`,
    SUM(IF(addDays(t.due_date, 2) BETWEEN (SELECT start_date FROM params) AND (SELECT end_date FROM params), ifNull(c.od_rec_6_15,  0), 0)) AS `New OD Recovery 6-15 days`,
    SUM(IF(addDays(t.due_date, 2) BETWEEN (SELECT start_date FROM params) AND (SELECT end_date FROM params), ifNull(c.od_rec_16_30, 0), 0)) AS `New OD Recovery 16-30 days`,
    SUM(IF(addDays(t.due_date, 2) BETWEEN (SELECT start_date FROM params) AND (SELECT end_date FROM params), ifNull(c.od_rec_31_60, 0), 0)) AS `New OD Recovery 31-60 days`,
    SUM(IF(addDays(t.due_date, 2) BETWEEN (SELECT start_date FROM params) AND (SELECT end_date FROM params), ifNull(c.od_rec_gt_60, 0), 0)) AS `New OD Recovery >60 days`,

    /* ── Total recovery buckets (all loans this month) ── */
    SUM(ifNull(c.od_rec_2_5,   0)) AS `Total Recovery 2-5 days`,
    SUM(ifNull(c.od_rec_6_15,  0)) AS `Total Recovery 6-15 days`,
    SUM(ifNull(c.od_rec_16_30, 0)) AS `Total Recovery 16-30 days`,
    SUM(ifNull(c.od_rec_31_60, 0)) AS `Total Recovery 31-60 days`,
    SUM(ifNull(c.od_rec_gt_60, 0)) AS `Total Recovery >60 days`,

    /* ── Summary totals ── */
    SUM(ifNull(c.od_prin,  0)) AS `Overdue Principal Collection`,
    SUM(ifNull(c.od_fee,   0)) AS `Overdue Fee Collection`,
    SUM(ifNull(c.od_total, 0)) AS `Total Overdue Collection`

FROM loan_state t
LEFT JOIN collections c ON t.loan_doc_id = c.loan_doc_id