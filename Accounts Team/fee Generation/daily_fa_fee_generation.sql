WITH 
    -- 1. Configuration Variables
    'UGA' AS country_code_var,
    '202512' AS month_str,
    toLastDayOfMonth(toDate(concat(month_str, '01'))) AS last_day_var,
    (
        SELECT closure_date 
        FROM flow_api.closure_date_records 
        WHERE status = 'enabled' 
          AND month = month_str 
          AND country_code = country_code_var
        LIMIT 1
    ) AS closure_date_var,
    ['float_advance', 'adj_float_advance'] AS loan_purpose_list,

    -- 2. Identify Disbursals
    disbursals AS (
        SELECT 
            l.loan_doc_id, 
            any(loan_principal) AS principal, 
            any(flow_fee) AS fee,
            any(duration) AS duration_val,
            any(toDate(disbursal_date)) AS start_date
        FROM loans l
        INNER JOIN loan_txns lt ON lt.loan_doc_id = l.loan_doc_id
        WHERE lt.txn_type = 'disbursal'
          AND has(loan_purpose_list, l.loan_purpose)
          AND l.country_code = country_code_var
          AND toDate(disbursal_date) <= last_day_var
          AND realization_date <= closure_date_var
          AND product_id NOT IN (
              SELECT id FROM loan_products WHERE product_type = 'float_vending'
          )
          AND status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
          AND l.loan_doc_id NOT IN (
              SELECT loan_doc_id FROM loan_write_off 
              WHERE country_code = country_code_var 
                AND write_off_date <= last_day_var 
                AND write_off_status IN ('approved', 'partially_recovered', 'recovered')
          )
        GROUP BY l.loan_doc_id
    ),

    -- 3. Aggregate Payments
    payments AS (
        SELECT 
            l.loan_doc_id, 
            sum(lt.principal) AS partial_principal, 
            sum(lt.fee) AS partial_fee
        FROM disbursals l
        INNER JOIN loan_txns lt ON lt.loan_doc_id = l.loan_doc_id
        WHERE lt.txn_type IN ('payment', 'fee_waiver')
          AND toDate(txn_date) <= last_day_var
          AND realization_date <= closure_date_var
        GROUP BY l.loan_doc_id
    ),

    -- 4. Main Calculation Engine
    parsedLoans AS (
        SELECT 
            l.loan_doc_id,
            l.acc_prvdr_code,
            l.cust_name,
            l.flow_rel_mgr_name,
            l.product_name,
            l.disbursal_date,
            l.due_date,
            pri.principal AS loan_principal,
            pri.fee AS total_flow_fee,
            
            -- Core Outstanding Balances
            max2(0, pri.principal - coalesce(pp.partial_principal, 0)) AS os_principal,
            max2(0, pri.fee - coalesce(pp.partial_fee, 0)) AS os_fee_remaining,
            
            -- Par Days
            max2(0, dateDiff('day', toDate(l.due_date), last_day_var)) AS par_days,

            -- Days Splits
            pri.duration_val AS total_duration,
            dateDiff('day', pri.start_date, least(dateAdd(day, pri.duration_val, pri.start_date), last_day_var)) AS days_inside_report,
            max2(0, dateDiff('day', greatest(pri.start_date, last_day_var), dateAdd(day, pri.duration_val, pri.start_date))) AS days_outside_report,

            -- Fee Accruals
            toInt64(pri.fee / nullIf(pri.duration_val, 0)) AS fee_per_day,
            toInt64(max2(0, (fee_per_day * days_inside_report) - coalesce(pp.partial_fee, 0))) AS fee_os_at_report_date
        FROM disbursals pri
        LEFT JOIN loans l ON l.loan_doc_id = pri.loan_doc_id
        LEFT JOIN payments pp ON pri.loan_doc_id = pp.loan_doc_id
    )

-- 5. Final Bucket Allocation
SELECT 
    *,
    -- PAR 0-30
    if(par_days >= 0 AND par_days <= 30, os_principal, 0) AS `Par 0_30 (Principal)`,
    if(par_days >= 0 AND par_days <= 30, fee_os_at_report_date, 0) AS `Par 0_30 (Fee)`,

    -- PAR 30-60
    if(par_days > 30 AND par_days <= 60, os_principal, 0) AS `Par 30_60 (Principal)`,
    if(par_days > 30 AND par_days <= 60, fee_os_at_report_date, 0) AS `Par 30_60 (Fee)`,

    -- PAR 60-90
    if(par_days > 60 AND par_days <= 90, os_principal, 0) AS `Par 60_90 (Principal)`,
    if(par_days > 60 AND par_days <= 90, fee_os_at_report_date, 0) AS `Par 60_90 (Fee)`,

    -- PAR 90-120
    if(par_days > 90 AND par_days <= 120, os_principal, 0) AS `Par 90_120 (Principal)`,
    if(par_days > 90 AND par_days <= 120, fee_os_at_report_date, 0) AS `Par 90_120 (Fee)`,

    -- PAR 120+
    if(par_days > 120, os_principal, 0) AS `Par 120+ (Principal)`,
    if(par_days > 120, fee_os_at_report_date, 0) AS `Par 120+ (Fee)`

FROM parsedLoans 
WHERE os_principal > 0 OR fee_os_at_report_date > 0;