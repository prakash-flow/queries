WITH 
    -- 1. Configuration Constants
    'UGA' AS country_code_var,
    '202512' AS month_str,
    toLastDayOfMonth(toDate(concat(month_str, '01'))) AS last_day_var,
    (
        SELECT closure_date FROM flow_api.closure_date_records 
        WHERE status = 'enabled' AND month = month_str AND country_code = country_code_var 
        LIMIT 1
    ) AS closure_date_var,

    -- 2. Identify Loans
    loan_base AS (
        SELECT 
            l.loan_doc_id, 
            l.acc_prvdr_code,
            l.cust_name,
            l.flow_rel_mgr_name,
            l.product_name,
            toDate(l.disbursal_date) AS disbursal_date,
            toDate(l.due_date) AS due_date,
            l.loan_principal,
            l.flow_fee,
            max2(1, dateDiff('day', toDate(l.disbursal_date), toDate(l.due_date))) AS total_days_duration
        FROM loans l
        JOIN loan_txns lt ON lt.loan_doc_id = l.loan_doc_id
        WHERE lt.txn_type = 'af_disbursal'
          AND l.loan_purpose IN ('growth_financing', 'asset_financing')
          AND l.country_code = country_code_var
          AND toDate(l.disbursal_date) <= last_day_var
          AND lt.realization_date <= closure_date_var
          AND l.product_id NOT IN (
              SELECT id FROM loan_products WHERE product_type = 'float_vending'
          )
          AND l.status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
          AND l.loan_doc_id NOT IN (
              SELECT loan_doc_id FROM loan_write_off 
              WHERE country_code = country_code_var 
                AND write_off_date <= last_day_var 
                AND write_off_status IN ('approved', 'partially_recovered', 'recovered')
          )
        GROUP BY l.loan_doc_id, l.acc_prvdr_code, l.cust_name, l.flow_rel_mgr_name, l.product_name, l.disbursal_date, l.due_date, l.loan_principal, l.flow_fee
    ),

    -- 3. Payment Aggregation
    payment_agg AS (
        SELECT
            p.loan_doc_id AS pay_loan_id,
            p.installment_number AS pay_inst_num,
            sum(p.principal_amount) AS paid_p,
            sum(p.fee_amount) AS paid_f
        FROM payment_allocation_items p
        JOIN account_stmts a ON a.id = p.account_stmt_id
        JOIN loan_installments li ON li.id = p.installment_id
        WHERE formatDateTime(a.stmt_txn_date, '%Y%m') <= month_str
          AND a.realization_date <= closure_date_var
          AND is_reversed = 0
          AND p.country_code = country_code_var
          AND toDate(li.due_date) <= last_day_var
        GROUP BY pay_loan_id, pay_inst_num
    ),

    -- 4. Total Fees Paid per Loan
    total_loan_payments AS (
        SELECT 
            p.loan_doc_id AS pay_loan_id,
            sum(p.fee_amount) AS total_fee_paid
        FROM payment_allocation_items p
        JOIN account_stmts a ON a.id = p.account_stmt_id
        WHERE formatDateTime(a.stmt_txn_date, '%Y%m') <= month_str
          AND a.realization_date <= closure_date_var
          AND is_reversed = 0
          AND p.country_code = country_code_var
        GROUP BY pay_loan_id
    ),

    -- 5. Intermediate Totals
    totals AS (
        SELECT 
            li.loan_doc_id AS join_id,
            sum(max2(0, li.principal_due - coalesce(pa.paid_p, 0))) AS total_os_principal,
            sum(if(toDate(li.due_date) <= last_day_var, 
                   max2(0, li.fee_due - coalesce(pa.paid_f, 0)), 
                   0)) AS total_os_fee,
            minIf(toDate(li.due_date), 
                ((li.principal_due - coalesce(pa.paid_p, 0)) > 0 OR (li.fee_due - coalesce(pa.paid_f, 0)) > 0) 
                AND toDate(li.due_date) <= last_day_var
            ) AS raw_min_date
        FROM loan_installments li
        LEFT JOIN payment_agg pa ON pa.pay_loan_id = li.loan_doc_id AND pa.pay_inst_num = li.installment_number
        GROUP BY join_id
    )

-- 6. Final Processing Block (All Amounts Ceiled)
SELECT 
    lb.loan_doc_id AS `Loan ID`,
    lb.acc_prvdr_code AS `Account Provider Code`,
    lb.cust_name AS `Customer Name`,
    lb.flow_rel_mgr_name AS `RM Name`,
    lb.product_name AS `Product Name`,
    lb.disbursal_date AS `Disbursal Date`,
    lb.due_date AS `Due Date`,
    
    -- Principal and Fees (All Ceiled)
    toInt64(ceil(coalesce(lb.loan_principal, 0))) AS `Loan Principal`,
    toInt64(ceil(coalesce(lb.flow_fee, 0))) AS `Flow Fee`,
    toInt64(ceil(coalesce(t.total_os_principal, 0))) AS `Principal OS`,
    toInt64(ceil(coalesce(t.total_os_fee, 0))) AS `Fee OS`,
    
    -- Aging and Timing
    toInt64(if(t.raw_min_date = '1970-01-01' OR isNull(t.raw_min_date), 0, dateDiff('day', t.raw_min_date, last_day_var))) AS `Par Days`,
    toInt64(lb.total_days_duration) AS `Duration`,
    toInt64(coalesce(dateDiff('day', lb.disbursal_date, least(lb.due_date, last_day_var)), 0)) AS `days_inside_report`,
    toInt64(max2(0, dateDiff('day', last_day_var, lb.due_date))) AS `days_outside_report`,
    
    -- Fee Calculations (Ceiled)
    toInt64(ceil(coalesce(lb.flow_fee, 0) / lb.total_days_duration)) AS `Fee Per Day`,
    toInt64(max2(0, ceil(((`Fee Per Day` * `days_inside_report`) - coalesce(lp.total_fee_paid, 0))))) AS `fee_os_at_report_date`,

    -- PAR Buckets (Principal) - Ceiled
    toInt64(if(`Par Days` >= 0 AND `Par Days` <= 30, ceil(coalesce(t.total_os_principal, 0)), 0)) AS `Par 0_30 (Principal)`,
    toInt64(if(`Par Days` >= 0 AND `Par Days` <= 30, ceil(coalesce(fee_os_at_report_date, 0)), 0)) AS `Par 0_30 (Fee)`,

    toInt64(if(`Par Days` > 30 AND `Par Days` <= 60, ceil(coalesce(t.total_os_principal, 0)), 0)) AS `Par 30_60 (Principal)`,
    toInt64(if(`Par Days` > 30 AND `Par Days` <= 60, ceil(coalesce(fee_os_at_report_date, 0)), 0)) AS `Par 30_60 (Fee)`,

    toInt64(if(`Par Days` > 60 AND `Par Days` <= 90, ceil(coalesce(t.total_os_principal, 0)), 0)) AS `Par 60_90 (Principal)`,
    toInt64(if(`Par Days` > 60 AND `Par Days` <= 90, ceil(coalesce(fee_os_at_report_date, 0)), 0)) AS `Par 60_90 (Fee)`,

    toInt64(if(`Par Days` > 90 AND `Par Days` <= 120, ceil(coalesce(t.total_os_principal, 0)), 0)) AS `Par 90_120 (Principal)`,
    toInt64(if(`Par Days` > 90 AND `Par Days` <= 120, ceil(coalesce(fee_os_at_report_date, 0)), 0)) AS `Par 90_120 (Fee)`,

    toInt64(if(`Par Days` > 120, ceil(coalesce(t.total_os_principal, 0)), 0)) AS `Par 120+ (Principal)`,
    toInt64(if(`Par Days` > 120, ceil(coalesce(fee_os_at_report_date, 0)), 0)) AS `Par 120+ (Fee)`

FROM loan_base lb
JOIN totals t ON lb.loan_doc_id = t.join_id
LEFT JOIN total_loan_payments lp ON lb.loan_doc_id = lp.pay_loan_id
WHERE (t.total_os_principal > 0 OR fee_os_at_report_date > 0)
ORDER BY lb.disbursal_date;