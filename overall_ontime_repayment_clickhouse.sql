-- Per-customer on-time repayment metrics (ClickHouse).
-- Same logic as overall_ontime_repayment.sql (MySQL), converted to ClickHouse
-- syntax: no user session variables, so the parameters are declared as
-- scalar WITH expressions; IFNULL/IF/DATE/DATE_ADD/DATE_SUB become
-- ifNull/if/toDate/addDays/subtractMonths.

WITH
    toDate('2026-09-15')                                  AS end_date,
    toDateTime(concat(toString(end_date), ' 23:59:59'))   AS end_datetime,
    'UGA'                                                 AS v_country_code,
    subtractMonths(end_date, 3)                           AS three_months_ago,

    base_query AS (
        SELECT
            l.cust_id,
            l.loan_doc_id,
            l.due_date,
            (ifNull(l.loan_principal, 0) + ifNull(l.flow_fee, 0) + ifNull(l.charges, 0)) AS expected_amount,
            sum(ifNull(lt.principal, 0) + ifNull(lt.fee, 0) + ifNull(lt.charges, 0)) AS paid_amount,
            sum(
                if(
                    toDate(lt.txn_date) <= addDays(toDate(l.due_date), 1),
                    ifNull(lt.principal, 0) + ifNull(lt.fee, 0) + ifNull(lt.charges, 0),
                    0
                )
            ) AS ontime_paid_amount,
            sum(
                if(
                    toDate(lt.txn_date) <= addDays(toDate(l.due_date), 5),
                    ifNull(lt.principal, 0) + ifNull(lt.fee, 0) + ifNull(lt.charges, 0),
                    0
                )
            ) AS paid_within_5_days_amount,
            if(
                sum(ifNull(lt.principal, 0) + ifNull(lt.fee, 0) + ifNull(lt.charges, 0)) > 0,
                max(toDate(lt.txn_date)),
                NULL
            ) AS paid_date
        FROM loans AS l
        LEFT JOIN loan_txns AS lt
            ON l.loan_doc_id = lt.loan_doc_id
           AND lt.txn_type = 'payment'
        WHERE l.due_date <= end_datetime
          AND l.country_code = v_country_code
          AND l.product_id NOT IN (
                SELECT id FROM loan_products
                WHERE product_type = 'float_vending' OR repayment_type = 'installment'
              )
          AND l.status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
          AND l.loan_purpose IN ('float_advance')
        GROUP BY l.cust_id, l.loan_doc_id, l.due_date, expected_amount
    ),

    raw AS (
        SELECT
            cust_id,
            loan_doc_id,
            max(due_date) AS due_date,
            count(loan_doc_id) AS loan_count,
            sum(ontime_paid_amount) AS ontime_repaid_amount,
            sum(expected_amount) AS total_due_amount,
            sum(paid_within_5_days_amount) AS paid_within_5_days_amount,
            (sum(ontime_paid_amount) / nullIf(sum(expected_amount), 0)) * 100 AS loan_wise_ontime_repayment,
            sum(if(ontime_paid_amount >= expected_amount, 1, 0)) AS ontime_settle_count,
            max(paid_date) AS paid_date
        FROM base_query
        GROUP BY cust_id, loan_doc_id
    )

-- === Per-customer breakdown ===
SELECT
    b.cust_id `Customer ID`,
    b.reg_date `Registration Date`,
    b.acc_purpose AS `Account Purpose`,
    cp.full_name AS `Customer Name`,
    cp.mobile_num AS `Customer Mobile Num`,
    rm.full_name AS `RM Name`,
    rm.mobile_num AS `RM Mobile Number`,

    sum(
        if(coalesce(raw.due_date, toDate('1970-01-01')) >= three_months_ago, 1, 0)
    ) AS `Last 3 Month Loans`,

    ifNull(
        round(
            sum(if(coalesce(raw.due_date, toDate('1970-01-01')) >= three_months_ago, raw.ontime_repaid_amount, 0)) /
            nullIf(
                sum(if(coalesce(raw.due_date, toDate('1970-01-01')) >= three_months_ago, raw.total_due_amount, 0)),
                0
            ) * 100,
            2
        ),
        0
    ) AS `Last 3 Month Ontime Repayment`,

    ifNull(
        sum(
            if(coalesce(raw.due_date, toDate('1970-01-01')) >= three_months_ago, raw.ontime_settle_count, 0)
        ),
        0
    ) AS `Last 3 Month Ontime Loans`,

    count(raw.loan_doc_id) AS `Overall Loans`,

    ifNull(
        round(
            sum(raw.ontime_repaid_amount) / nullIf(sum(raw.total_due_amount), 0) * 100,
            2
        ),
        0
    ) AS `Overall Ontime Repayment`,

    ifNull(sum(raw.ontime_settle_count), 0) AS `Overall Ontime Loans`

FROM borrowers AS b
LEFT JOIN raw ON raw.cust_id = b.cust_id
LEFT JOIN persons AS cp ON cp.id = b.owner_person_id
LEFT JOIN persons AS rm ON rm.id = b.flow_rel_mgr_id
WHERE b.country_code = v_country_code
GROUP BY `Customer ID`, `Registration Date`, `Account Purpose`, `Customer Name`, `Customer Mobile Num`, `RM Name`, `RM Mobile Number`;