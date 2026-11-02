WITH
    'UGA' AS p_country_code,
    toDate('2026-08-31') AS p_date,   -- report date (run daily)

    toString(toYYYYMM(p_date)) AS p_month,

    toDateTime(concat(toString(p_date), ' 23:59:59')) AS p_report_end,

    (
        SELECT max(closure_date)
        FROM closure_date_records
        WHERE status = 'enabled'
          AND month = p_month
          AND country_code = p_country_code
    ) AS p_closure_date,

    if(
        p_date = toLastDayOfMonth(p_date),
        toDateTime(p_closure_date),
        p_report_end
    ) AS p_realization_date,

    disbursals AS
    (
        SELECT
            lt.loan_doc_id AS loan_doc_id,
            sum(lt.amount) AS principal,
            max(l.disbursal_date) AS disbursal_date,
            max(l.due_date) AS due_date,
            max(l.flow_fee) AS flow_fee
        FROM loans AS l
        INNER JOIN loan_txns AS lt
            ON lt.loan_doc_id = l.loan_doc_id
        WHERE lt.txn_type = 'disbursal'
          AND lt.realization_date <= p_realization_date
          AND l.country_code = p_country_code
          AND l.disbursal_date <= p_report_end
          AND l.product_id NOT IN (43, 75, 300)
          AND l.status NOT IN
          (
              'voided',
              'hold',
              'pending_disbursal',
              'pending_mnl_dsbrsl'
          )
          AND l.loan_doc_id NOT IN
          (
              SELECT loan_doc_id
              FROM loan_write_off
              WHERE country_code = p_country_code
                AND toDate(write_off_date) <= p_date
                AND write_off_status IN
                (
                    'approved',
                    'partially_recovered',
                    'recovered'
                )
          )
        GROUP BY lt.loan_doc_id
    ),

    payments AS
    (
        SELECT
            t.loan_doc_id AS loan_doc_id,
            sum(t.principal) AS partial_pay,
            sum(t.fee) AS paid_fee,
            max(t.txn_date) AS last_payment_date
        FROM loan_txns AS t
        INNER JOIN loans AS l
            ON l.loan_doc_id = t.loan_doc_id
        WHERE l.country_code = p_country_code
          AND l.disbursal_date <= p_report_end
          AND l.product_id NOT IN (43, 75, 300)
          AND t.realization_date <= p_realization_date
          AND t.txn_date <= p_report_end
          AND t.txn_type = 'payment'
          AND l.status NOT IN
          (
              'voided',
              'hold',
              'pending_disbursal',
              'pending_mnl_dsbrsl'
          )
          AND l.loan_doc_id NOT IN
          (
              SELECT loan_doc_id
              FROM loan_write_off
              WHERE country_code = p_country_code
                AND toDate(write_off_date) <= p_date
                AND write_off_status IN
                (
                    'approved',
                    'partially_recovered',
                    'recovered'
                )
          )
        GROUP BY t.loan_doc_id
    ),

    outstanding AS
    (
        SELECT
            d.loan_doc_id AS loan_doc_id,
            greatest(d.principal - coalesce(p.partial_pay, 0), 0) AS os_amount,
            dateDiff('day', toDate(d.due_date), p_date) AS dpd
        FROM disbursals AS d
        LEFT JOIN payments AS p
            ON d.loan_doc_id = p.loan_doc_id
        WHERE greatest(d.principal - coalesce(p.partial_pay, 0), 0) > 0
    )

SELECT
    p_date AS `Date`,

    countIf(dpd <= 0) AS `Ongoing Count`,
    sumIf(os_amount, dpd <= 0) AS `Ongoing Value`,

    countIf(dpd BETWEEN 1 AND 5) AS `PAR 1-5 Count`,
    sumIf(os_amount, dpd BETWEEN 1 AND 5) AS `PAR 1-5 Value`,

    countIf(dpd > 5) AS `PAR >5 Count`,
    sumIf(os_amount, dpd > 5) AS `PAR >5 Value`,

    count() AS `Total OS Count`,
    sum(os_amount) AS `Total OS Value`
FROM outstanding;
