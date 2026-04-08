-- 1. Configuration Constants
SET @country_code_var = 'UGA';
SET @month_str = '202512';
SET @last_day_var = LAST_DAY(STR_TO_DATE(CONCAT(@month_str, '01'), '%Y%m%d'));

WITH 
    -- 2. Identify Loans
    loan_base AS (
        SELECT 
            l.loan_doc_id, 
            l.acc_prvdr_code,
            l.cust_name,
            l.flow_rel_mgr_name,
            l.product_name,
            DATE(l.disbursal_date) AS disbursal_date,
            DATE(l.due_date) AS due_date,
            l.loan_principal,
            l.flow_fee,
            GREATEST(1, DATEDIFF(DATE(l.due_date), DATE(l.disbursal_date))) AS total_days_duration
        FROM loans l
        JOIN loan_txns lt ON lt.loan_doc_id = l.loan_doc_id
        WHERE lt.txn_type = 'af_disbursal'
          AND l.loan_purpose IN ('growth_financing', 'asset_financing')
          AND l.country_code = @country_code_var
          AND DATE(l.disbursal_date) <= @last_day_var
          AND lt.realization_date <= (
              SELECT closure_date FROM flow_api.closure_date_records 
              WHERE status = 'enabled' AND month = @month_str AND country_code = @country_code_var 
              LIMIT 1
          )
          AND l.product_id NOT IN (
              SELECT id FROM loan_products WHERE product_type = 'float_vending'
          )
          AND l.status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
          AND l.loan_doc_id NOT IN (
              SELECT loan_doc_id FROM loan_write_off 
              WHERE country_code = @country_code_var 
                AND write_off_date <= @last_day_var 
                AND write_off_status IN ('approved', 'partially_recovered', 'recovered')
          )
        GROUP BY l.loan_doc_id, l.acc_prvdr_code, l.cust_name, l.flow_rel_mgr_name, l.product_name, l.disbursal_date, l.due_date, l.loan_principal, l.flow_fee
    ),

    -- 3. Payment Aggregation (Per Installment)
    payment_agg AS (
        SELECT
            p.loan_doc_id AS pay_loan_id,
            p.installment_number AS pay_inst_num,
            SUM(p.principal_amount) AS paid_p,
            SUM(p.fee_amount) AS paid_f
        FROM payment_allocation_items p
        JOIN account_stmts a ON a.id = p.account_stmt_id
        JOIN loan_installments li ON li.id = p.installment_id
        WHERE DATE_FORMAT(a.stmt_txn_date, '%Y%m') <= @month_str
        AND is_reversed = 0
          AND a.realization_date <= (
              SELECT closure_date FROM flow_api.closure_date_records 
              WHERE status = 'enabled' AND month = @month_str AND country_code = @country_code_var 
              LIMIT 1
          )
          AND p.country_code = @country_code_var
          AND DATE(li.due_date) <= @last_day_var
        GROUP BY pay_loan_id, pay_inst_num
    ),

    -- 4. Total Fees Paid per Loan (Lifetime up to closure)
    total_loan_payments AS (
        SELECT 
            p.loan_doc_id AS pay_loan_id,
            SUM(p.fee_amount) AS total_fee_paid
        FROM payment_allocation_items p
        JOIN account_stmts a ON a.id = p.account_stmt_id
        WHERE DATE_FORMAT(a.stmt_txn_date, '%Y%m') <= @month_str
        AND is_reversed = 0
          AND a.realization_date <= (
              SELECT closure_date FROM flow_api.closure_date_records 
              WHERE status = 'enabled' AND month = @month_str AND country_code = @country_code_var 
              LIMIT 1
          )
          AND p.country_code = @country_code_var
        GROUP BY pay_loan_id
    ),

    -- 5. Intermediate Totals (Calculates OS balances)
    totals AS (
        SELECT 
            li.loan_doc_id AS join_id,
            SUM(GREATEST(0, li.principal_due - COALESCE(pa.paid_p, 0))) AS total_os_principal,
            SUM(IF(DATE(li.due_date) <= @last_day_var, 
                   GREATEST(0, li.fee_due - COALESCE(pa.paid_f, 0)), 
                   0)) AS total_os_fee,
            MIN(CASE 
                WHEN ((li.principal_due - COALESCE(pa.paid_p, 0)) > 0 OR (li.fee_due - COALESCE(pa.paid_f, 0)) > 0) 
                AND DATE(li.due_date) <= @last_day_var
                THEN DATE(li.due_date) ELSE NULL 
            END) AS raw_min_date
        FROM loan_installments li
        LEFT JOIN payment_agg pa ON pa.pay_loan_id = li.loan_doc_id AND pa.pay_inst_num = li.installment_number
        GROUP BY join_id
    )

-- 6. Final Processing Block
SELECT 
    lb.loan_doc_id AS `Loan ID`,
    lb.acc_prvdr_code AS `Account Provider Code`,
    lb.cust_name AS `Customer Name`,
    lb.flow_rel_mgr_name AS `RM Name`,
    lb.product_name AS `Product Name`,
    lb.disbursal_date AS `Disbursal Date`,
    lb.due_date AS `Due Date`,
    
    CAST(CEIL(COALESCE(lb.loan_principal, 0)) AS SIGNED) AS `Loan Principal`,
    CAST(CEIL(COALESCE(lb.flow_fee, 0)) AS SIGNED) AS `Flow Fee`,
    CAST(CEIL(COALESCE(t.total_os_principal, 0)) AS SIGNED) AS `Principal OS`,
    CAST(CEIL(COALESCE(t.total_os_fee, 0)) AS SIGNED) AS `Fee OS`,
    
    -- Aging and Timing
    CAST(IF(t.raw_min_date IS NULL, 0, DATEDIFF(@last_day_var, t.raw_min_date)) AS SIGNED) AS `Par Days`,
    CAST(lb.total_days_duration AS SIGNED) AS `Duration`,
    
    -- Days Inside/Outside calculations
    CAST(GREATEST(0, LEAST(lb.total_days_duration, DATEDIFF(@last_day_var, lb.disbursal_date))) AS SIGNED) AS `days_inside_report`,
    CAST(GREATEST(0, lb.total_days_duration - GREATEST(0, LEAST(lb.total_days_duration, DATEDIFF(@last_day_var, lb.disbursal_date)))) AS SIGNED) AS `days_outside_report`,
    
    -- Fee Calculations
    CAST(COALESCE(lb.flow_fee, 0) / lb.total_days_duration AS DECIMAL(18,4)) AS `Fee Per Day`,
    
    -- Fee OS at report date: The expected fee accrued minus what was actually paid
    CAST(CEIL(GREATEST(0, LEAST(
        COALESCE(t.total_os_fee, 0), 
        ((COALESCE(lb.flow_fee, 0) / lb.total_days_duration) * GREATEST(0, LEAST(lb.total_days_duration, DATEDIFF(@last_day_var, lb.disbursal_date)))) - COALESCE(lp.total_fee_paid, 0)
    ))) AS SIGNED) AS `fee_os_at_report_date`,

    -- Fee OS after report date: Calculated as the remainder to ensure sum = Fee OS
    CAST(CEIL(COALESCE(t.total_os_fee, 0) - GREATEST(0, LEAST(
        COALESCE(t.total_os_fee, 0), 
        ((COALESCE(lb.flow_fee, 0) / lb.total_days_duration) * GREATEST(0, LEAST(lb.total_days_duration, DATEDIFF(@last_day_var, lb.disbursal_date)))) - COALESCE(lp.total_fee_paid, 0)
    ))) AS SIGNED) AS `fee_os_after_report_date`,

    -- PAR Buckets (Principal & Fee)
    CAST(IF(IF(t.raw_min_date IS NULL, 0, DATEDIFF(@last_day_var, t.raw_min_date)) BETWEEN 0 AND 30, CEIL(COALESCE(t.total_os_principal, 0)), 0) AS SIGNED) AS `Par 0_30 (Principal)`,
    CAST(IF(IF(t.raw_min_date IS NULL, 0, DATEDIFF(@last_day_var, t.raw_min_date)) BETWEEN 0 AND 30, CEIL(COALESCE(t.total_os_fee, 0)), 0) AS SIGNED) AS `Par 0_30 (Fee)`,

    CAST(IF(IF(t.raw_min_date IS NULL, 0, DATEDIFF(@last_day_var, t.raw_min_date)) BETWEEN 31 AND 60, CEIL(COALESCE(t.total_os_principal, 0)), 0) AS SIGNED) AS `Par 30_60 (Principal)`,
    CAST(IF(IF(t.raw_min_date IS NULL, 0, DATEDIFF(@last_day_var, t.raw_min_date)) BETWEEN 31 AND 60, CEIL(COALESCE(t.total_os_fee, 0)), 0) AS SIGNED) AS `Par 30_60 (Fee)`,

    CAST(IF(IF(t.raw_min_date IS NULL, 0, DATEDIFF(@last_day_var, t.raw_min_date)) BETWEEN 61 AND 90, CEIL(COALESCE(t.total_os_principal, 0)), 0) AS SIGNED) AS `Par 60_90 (Principal)`,
    CAST(IF(IF(t.raw_min_date IS NULL, 0, DATEDIFF(@last_day_var, t.raw_min_date)) BETWEEN 61 AND 90, CEIL(COALESCE(t.total_os_fee, 0)), 0) AS SIGNED) AS `Par 60_90 (Fee)`,

    CAST(IF(IF(t.raw_min_date IS NULL, 0, DATEDIFF(@last_day_var, t.raw_min_date)) BETWEEN 91 AND 120, CEIL(COALESCE(t.total_os_principal, 0)), 0) AS SIGNED) AS `Par 90_120 (Principal)`,
    CAST(IF(IF(t.raw_min_date IS NULL, 0, DATEDIFF(@last_day_var, t.raw_min_date)) BETWEEN 91 AND 120, CEIL(COALESCE(t.total_os_fee, 0)), 0) AS SIGNED) AS `Par 90_120 (Fee)`,

    CAST(IF(IF(t.raw_min_date IS NULL, 0, DATEDIFF(@last_day_var, t.raw_min_date)) > 120, CEIL(COALESCE(t.total_os_principal, 0)), 0) AS SIGNED) AS `Par 120+ (Principal)`,
    CAST(IF(IF(t.raw_min_date IS NULL, 0, DATEDIFF(@last_day_var, t.raw_min_date)) > 120, CEIL(COALESCE(t.total_os_fee, 0)), 0) AS SIGNED) AS `Par 120+ (Fee)`

FROM loan_base lb
JOIN totals t ON lb.loan_doc_id = t.join_id
LEFT JOIN total_loan_payments lp ON lb.loan_doc_id = lp.pay_loan_id
WHERE (t.total_os_principal > 0 OR t.total_os_fee > 0)
ORDER BY lb.disbursal_date;