WITH
    'UGA' AS p_country_code,
    '202608' AS p_month,

    /* Get configured closure date */
    (
        SELECT max(closure_date)
        FROM closure_date_records
        WHERE status = 'enabled'
          AND month = p_month
          AND country_code = p_country_code
    ) AS p_closure_date,

    /* Determine realization date */
    if(
        isNotNull(p_closure_date),
        p_closure_date,
        if(
            toDate(concat(p_month, '01')) < toStartOfMonth(now()),

            /* Previous month -> month end 23:59:59 */
            toDateTime(
                concat(
                    toString(
                        toLastDayOfMonth(
                            toDate(concat(p_month, '01'))
                        )
                    ),
                    ' 23:59:59'
                )
            ),

            /* Current/future month -> current datetime */
            now()
        )
    ) AS p_realization_date,

    /* Report end */
    if(
        toDate(concat(p_month, '01')) < toStartOfMonth(now()),

        /* Previous month */
        toDateTime(
            concat(
                toString(
                    toLastDayOfMonth(
                        toDate(concat(p_month, '01'))
                    )
                ),
                ' 23:59:59'
            )
        ),

        /* Current month */
        now()
    ) AS p_report_end,

    /* Disbursals */
    disbursals AS
    (
        SELECT
            lt.loan_doc_id AS loan_doc_id,

            max(l.cust_id) AS cust_id,

            max(l.sub_lender_code) AS sub_lender_code,

            sum(lt.amount) AS principal,

            max(l.disbursal_date) AS disbursal_date,

            max(l.due_date) AS due_date,

            max(l.flow_fee) AS flow_fee,

            max(b.person_w_disability) AS person_w_disability,

            max(per.gender) AS gender,

            max(per.dob) AS dob

        FROM loans AS l

        INNER JOIN loan_txns AS lt
            ON lt.loan_doc_id = l.loan_doc_id

        LEFT JOIN borrowers AS b
            ON b.cust_id = l.cust_id

        LEFT JOIN persons AS per
            ON per.id = b.owner_person_id

        WHERE lt.txn_type = 'disbursal'

          AND lt.realization_date <= p_realization_date

          AND l.country_code = p_country_code

          AND l.loan_purpose = 'float_advance'

          AND l.disbursal_date <= p_report_end

          AND l.product_id NOT IN
          (
              43,
              75,
              300
          )

          AND l.status NOT IN
          (
              'voided',
              'hold',
              'pending_disbursal',
              'pending_mnl_dsbrsl'
          )

          /* Exclude written-off loans */
          AND l.loan_doc_id NOT IN
          (
              SELECT loan_doc_id
              FROM loan_write_off
              WHERE country_code = p_country_code

                AND toDate(write_off_date) <= toDate(p_report_end)

                AND write_off_status IN
                (
                    'approved',
                    'partially_recovered',
                    'recovered'
                )
          )

        GROUP BY lt.loan_doc_id
    ),

    /* Payments */
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

          AND l.product_id NOT IN
          (
              43,
              75,
              300
          )

          AND l.loan_purpose = 'float_advance'

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

          /* Exclude written-off loans */
          AND l.loan_doc_id NOT IN
          (
              SELECT loan_doc_id
              FROM loan_write_off
              WHERE country_code = p_country_code

                AND toDate(write_off_date) <= toDate(p_report_end)

                AND write_off_status IN
                (
                    'approved',
                    'partially_recovered',
                    'recovered'
                )
          )

        GROUP BY t.loan_doc_id
    )

/* Final Result */
SELECT
    d.loan_doc_id AS `FA ID`,

    d.cust_id AS `Customer ID`,

    d.sub_lender_code AS `Sub Lender Code`,

    d.disbursal_date AS `Disbursal Date`,

    d.due_date AS `Due Date`,

    d.principal AS `Disbursal Amount`,

    d.person_w_disability AS `Person With Disability`,

    d.gender AS `Gender`,

    d.dob AS `DOB`,

    /* Calculate completed age */
    dateDiff(
        'year',
        toDate(d.dob),
        toDate(p_report_end)
    )
    -
    if(
        formatDateTime(
            toDate(p_report_end),
            '%m%d'
        )
        <
        formatDateTime(
            toDate(d.dob),
            '%m%d'
        ),
        1,
        0
    ) AS `Age`,

    /* Outstanding principal */
    greatest(
        d.principal - coalesce(p.partial_pay, 0),
        0
    ) AS `Overall OS`,

    /* Paid principal */
    least(
        coalesce(p.partial_pay, 0),
        d.principal
    ) AS `Paid Amount`,

    /* Paid fee */
    coalesce(
        p.paid_fee,
        0
    ) AS `Paid Fee`,

    p.last_payment_date AS `Last Payment Date`

FROM disbursals AS d

LEFT JOIN payments AS p
    ON d.loan_doc_id = p.loan_doc_id

/* Only loans with outstanding principal */
WHERE greatest(
    d.principal - coalesce(p.partial_pay, 0),
    0
) > 0

ORDER BY d.loan_doc_id;