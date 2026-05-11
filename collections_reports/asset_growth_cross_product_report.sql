WITH
    'UGA' AS country_code_var,
    '202602' AS month_str,
    toDate(concat(month_str, '01')) AS month_start_var,
    toLastDayOfMonth(month_start_var) AS last_day_var,
    (
        SELECT closure_date
        FROM flow_api.closure_date_records
        WHERE status = 'enabled'
          AND month = month_str
          AND country_code = country_code_var
        LIMIT 1
    ) AS closure_date_var,

    base_loans AS (
        SELECT
            l.cust_id,
            l.loan_doc_id,
            multiIf(
                l.loan_purpose = 'growth_financing', 'KP',
                l.loan_purpose = 'asset_financing', 'Asset',
                l.loan_purpose
            ) AS base_loan_purpose,
            toDate(l.disbursal_date) AS base_disbursal_date,
            l.status AS base_loan_status,
            if(
                l.paid_date IS NOT NULL
                AND toDate(l.paid_date) < toDate(l.due_date),
                toDate(l.paid_date),
                toDate(l.due_date)
            ) AS base_end_date
        FROM loans l
        INNER JOIN loan_txns lt
            ON lt.loan_doc_id = l.loan_doc_id
        WHERE lt.txn_type = 'af_disbursal'
          AND l.loan_purpose IN ('growth_financing', 'asset_financing')
          AND l.country_code = country_code_var
          AND toDate(l.disbursal_date) <= last_day_var
          AND lt.realization_date <= closure_date_var
          AND l.product_id NOT IN (
              SELECT id
              FROM loan_products
              WHERE product_type = 'float_vending'
          )
          AND l.status NOT IN (
              'voided',
              'hold',
              'pending_disbursal',
              'pending_mnl_dsbrsl'
          )
          AND l.loan_doc_id NOT IN (
              SELECT loan_doc_id
              FROM loan_write_off
              WHERE country_code = country_code_var
                AND write_off_date <= last_day_var
                AND write_off_status IN ('approved', 'partially_recovered', 'recovered')
          )
        GROUP BY
            l.cust_id,
            l.loan_doc_id,
            l.loan_purpose,
            toDate(l.disbursal_date),
            l.status,
            if(
                l.paid_date IS NOT NULL
                AND toDate(l.paid_date) < toDate(l.due_date),
                toDate(l.paid_date),
                toDate(l.due_date)
            )
    ),

    other_loans AS (
        SELECT
            l.cust_id,
            l.loan_doc_id,
            l.loan_purpose,
            multiIf(
                l.loan_purpose = 'adj_float_advance', 'Kula',
                l.loan_purpose = 'float_advance', 'FA',
                l.loan_purpose
            ) AS other_product_type,
            toDate(l.disbursal_date) AS other_disbursal_date,
            if(
                l.paid_date IS NOT NULL
                AND toDate(l.paid_date) < toDate(l.due_date),
                toDate(l.paid_date),
                toDate(l.due_date)
            ) AS other_end_date
        FROM loans l
        INNER JOIN loan_txns lt
            ON lt.loan_doc_id = l.loan_doc_id
        WHERE lt.txn_type IN ('disbursal', 'af_disbursal')
          AND l.loan_purpose IN ('adj_float_advance', 'float_advance')
          AND l.country_code = country_code_var
          AND toDate(l.disbursal_date) <= last_day_var
          AND lt.realization_date <= closure_date_var
          AND l.product_id NOT IN (
              SELECT id
              FROM loan_products
              WHERE product_type = 'float_vending'
          )
          AND l.status NOT IN (
              'voided',
              'hold',
              'pending_disbursal',
              'pending_mnl_dsbrsl'
          )
          AND l.loan_doc_id NOT IN (
              SELECT loan_doc_id
              FROM loan_write_off
              WHERE country_code = country_code_var
                AND write_off_date <= last_day_var
                AND write_off_status IN ('approved', 'partially_recovered', 'recovered')
          )
        GROUP BY
            l.cust_id,
            l.loan_doc_id,
            l.loan_purpose,
            toDate(l.disbursal_date),
            if(
                l.paid_date IS NOT NULL
                AND toDate(l.paid_date) < toDate(l.due_date),
                toDate(l.paid_date),
                toDate(l.due_date)
            )
    )

SELECT
    bl.loan_doc_id AS `Loan ID KP/Asset`,
    bl.cust_id AS `Customer ID`,
    any(p.full_name) AS `Customer Name`,
    any(b.biz_name) AS `Business Name`,
    bl.base_loan_purpose AS `Base Loan Purpose`,
    bl.base_disbursal_date AS `Base Disbursal Date`,
    bl.base_loan_status AS `Current KP/Asset Loan Status`,

    if(
        countDistinctIf(
            ol.loan_doc_id,
            ol.loan_doc_id != bl.loan_doc_id
            AND ol.other_product_type = 'Kula'
            AND ol.other_disbursal_date >= addMonths(bl.base_disbursal_date, -3)
            AND ol.other_disbursal_date <= bl.base_disbursal_date
        ) > 0,
        'Yes',
        'No'
    ) AS `Existing Kula Customer`,

    if(
        countDistinctIf(
            ol.loan_doc_id,
            ol.loan_doc_id != bl.loan_doc_id
            AND ol.other_product_type = 'FA'
            AND ol.other_disbursal_date >= addMonths(bl.base_disbursal_date, -3)
            AND ol.other_disbursal_date <= bl.base_disbursal_date
        ) > 0,
        'Yes',
        'No'
    ) AS `Existing FA Customer`,

    countDistinctIf(
        ol.loan_doc_id,
        ol.loan_doc_id != bl.loan_doc_id
        AND ol.other_product_type = 'Kula'
        AND ol.other_disbursal_date >= bl.base_disbursal_date
        AND ol.other_disbursal_date <= bl.base_end_date
    ) AS `Kula Disbursed During Tenor`,

    countDistinctIf(
        ol.loan_doc_id,
        ol.loan_doc_id != bl.loan_doc_id
        AND ol.other_product_type = 'FA'
        AND ol.other_disbursal_date >= bl.base_disbursal_date
        AND ol.other_disbursal_date <= bl.base_end_date
    ) AS `FA Disbursed During Tenor`,

    countDistinctIf(
        ol.loan_doc_id,
        ol.loan_doc_id != bl.loan_doc_id
        AND ol.other_product_type = 'Kula'
        AND ol.other_disbursal_date <= bl.base_end_date
        AND ol.other_end_date >= bl.base_disbursal_date
    ) AS `Active Kula Loans`,

    countDistinctIf(
        ol.loan_doc_id,
        ol.loan_doc_id != bl.loan_doc_id
        AND ol.other_product_type = 'FA'
        AND ol.other_disbursal_date <= bl.base_end_date
        AND ol.other_end_date >= bl.base_disbursal_date
    ) AS `Active FA Loans`

FROM base_loans bl
LEFT JOIN other_loans ol
    ON ol.cust_id = bl.cust_id
LEFT JOIN borrowers b
    ON b.cust_id = bl.cust_id
LEFT JOIN persons p
    ON p.id = b.owner_person_id
GROUP BY
    bl.loan_doc_id,
    bl.cust_id,
    bl.base_loan_purpose,
    bl.base_disbursal_date,
    bl.base_loan_status,
    bl.base_end_date
ORDER BY
    bl.base_disbursal_date,
    `Loan ID KP/Asset`;
