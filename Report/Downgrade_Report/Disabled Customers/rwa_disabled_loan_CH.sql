WITH
    '202603' AS v_month,
    'UGA' AS v_country_code,
    toDate(concat(v_month,'01')) AS first_day,
    toLastDayOfMonth(first_day) AS last_day,

    -- 1. Identify all disabling events for each customer
    disabling_events AS (
        SELECT 
            record_code AS cust_id, 
            created_at AS disabled_at
        FROM record_audits
        WHERE country_code = v_country_code
          AND JSONExtractString(data_after, 'status') = 'disabled'
          AND created_at >= now() - INTERVAL 8 MONTH
    ),

    -- 2. Base loan data with all your original columns + borrowers table join
    loan_details AS (
        SELECT
            l.cust_id AS `Customer ID`,
            l.loan_doc_id AS `FA ID`,
            toDate(l.disbursal_date) AS `Date of FA`,
            l.disbursal_date AS full_disbursal_ts,
            l.loan_principal AS `FA Amount`,
            l.flow_fee AS `Fee Amount`,
            toDate(l.due_date) AS `Due Date`,
            coalesce(p.total_payment, 0) AS `Payment Amount`,
            if(l.status = 'settled', toDate(l.paid_date), NULL) AS `Payment Date`,
            if(l.status = 'settled' AND dateDiff('day', l.due_date, l.paid_date) <= 1, 1, 0) AS `Paid on-time or not`,
            CASE 
                WHEN l.status = 'overdue' THEN dateDiff('day', l.due_date, today())
                WHEN (l.status = 'settled' AND dateDiff('day', l.due_date, l.paid_date) > 1) THEN dateDiff('day', l.due_date, l.paid_date)
                ELSE NULL
            END `Overdue Days (if paid late)`,
            count() OVER (PARTITION BY l.cust_id ORDER BY l.disbursal_date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS `No. of FAs taken till that date`,
            
            -- New Column from Borrowers Table
            b.last_assessment_date AS `Last Assessment Date`,

            -- FA Limit Logic
            greatest(
                toFloat64(l.loan_principal),
                ifNull(argMaxIf(toFloat64(crl.last_upgraded_amount), crl.created_at, crl.created_at <= l.disbursal_date), 0)
            ) AS last_upgraded_amt_raw
        FROM loans l
        LEFT JOIN borrowers b ON b.cust_id = l.cust_id  -- Joining the borrowers table
        LEFT JOIN loan_txns lt ON lt.loan_doc_id = l.loan_doc_id AND lt.txn_type = 'disbursal'
        LEFT JOIN (
            SELECT loan_doc_id, sum(ifNull(principal, 0) + ifNull(fee, 0)) AS total_payment
            FROM loan_txns WHERE txn_type = 'payment' GROUP BY loan_doc_id
        ) p ON p.loan_doc_id = l.loan_doc_id
        LEFT JOIN customer_repayment_limits crl ON crl.cust_id = l.cust_id
        WHERE l.country_code = v_country_code
          AND l.loan_purpose = 'float_advance'
          AND lt.realization_date IS NOT NULL
        GROUP BY 
            l.cust_id, l.loan_doc_id, l.disbursal_date, l.loan_principal, 
            l.flow_fee, l.due_date, l.status, l.paid_date, p.total_payment,
            b.last_assessment_date
    )

-- 3. Final selection with reversed ranking (1 = Oldest, 5 = Newest)
SELECT 
    `Customer ID`, 
    `FA ID`, 
    `Date of FA`, 
    `No. of FAs taken till that date`, 
    `Due Date`, 
    `Payment Date`, 
    `FA Amount`, 
    `Fee Amount`, 
    `Payment Amount`, 
    `Paid on-time or not`, 
    `Overdue Days (if paid late)`,
    `Last Assessment Date`,
    `Disabling Event Date`,
    -- Calculation: (Total rows in group - descending rank + 1)
    (count(*) OVER (PARTITION BY `Customer ID`, `Disabling Event Date`) - event_loan_rank_desc + 1) AS event_loan_rank,
    
    if(
      ifNull(arrayMax(arrayFilter(x -> x <= last_upgraded_amt_raw, [70000,100000,150000,200000,300000,400000,500000,600000,700000,800000,900000,1000000,1500000,2000000,2500000,3000000])), 0) = 0,
      last_upgraded_amt_raw,
      arrayMax(arrayFilter(x -> x <= last_upgraded_amt_raw, [70000,100000,150000,200000,300000,400000,500000,600000,700000,800000,900000,1000000,1500000,2000000,2500000,3000000]))
    ) AS `FA limit at the time of FA`

FROM (
    SELECT 
        ld.*,
        toDate(de.disabled_at) AS `Disabling Event Date`,
        row_number() OVER (
            PARTITION BY ld.`Customer ID`, de.disabled_at 
            ORDER BY ld.full_disbursal_ts DESC
        ) AS event_loan_rank_desc
    FROM loan_details ld
    INNER JOIN disabling_events de ON ld.`Customer ID` = de.cust_id
    WHERE ld.full_disbursal_ts < de.disabled_at 
) 
WHERE event_loan_rank_desc <= 5
ORDER BY `Customer ID`, `Disabling Event Date` DESC, `Date of FA` ASC;