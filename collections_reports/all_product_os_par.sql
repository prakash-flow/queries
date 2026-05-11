WITH
    /* Global Variables */
    '202601' AS var_month,
    'UGA' AS var_country_code,
    
    toLastDayOfMonth(parseDateTimeBestEffort(concat(var_month, '01'))) AS var_last_day,
    
    (
        SELECT closure_date 
        FROM closure_date_records 
        WHERE country_code = var_country_code 
          AND month = var_month 
          AND status = 'enabled'
        LIMIT 1
    ) AS var_realization_date,

/* ============================================================
   🟢 1. FLOAT ADVANCE & ADJ FA LOGIC (Loan Level STRICTLY)
============================================================ */
    fa_loan_principal AS (
        SELECT 
            l.loan_doc_id AS loan_doc_id,
            l.loan_purpose AS loan_purpose,
            toFloat64(l.loan_principal) AS loan_principal,
            toFloat64(l.flow_fee) AS flow_fee,
            l.due_date AS due_date
        FROM loans l
        INNER JOIN loan_txns lt ON lt.loan_doc_id = l.loan_doc_id
        WHERE lt.txn_type = 'disbursal'
          AND lt.realization_date <= var_realization_date
          AND l.country_code = var_country_code
          AND toDate(l.disbursal_date) <= var_last_day
          AND l.product_id NOT IN (43, 75, 300)
          AND l.status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
        GROUP BY l.loan_doc_id, l.loan_purpose, l.loan_principal, l.flow_fee, l.due_date
    ),

    fa_loan_payments AS (
        SELECT 
            loan_doc_id,
            sumIf(toFloat64(principal), txn_type = 'payment') AS total_paid_principal,
            sumIf(toFloat64(fee), txn_type IN ('payment', 'fee_waiver')) AS total_paid_fee
        FROM loan_txns
        WHERE toDate(txn_date) <= var_last_day
          AND realization_date <= var_realization_date
        GROUP BY loan_doc_id
    ),

    fa_loan_os AS (
        SELECT
            lp.loan_doc_id AS loan_doc_id,
            lp.loan_purpose AS loan_purpose,
            lp.due_date AS due_date,
            greatest(lp.loan_principal - coalesce(p.total_paid_principal, toFloat64(0)), toFloat64(0)) AS os_principal,
            greatest(lp.flow_fee - coalesce(p.total_paid_fee, toFloat64(0)), toFloat64(0)) AS os_fee
        FROM fa_loan_principal lp
        LEFT JOIN fa_loan_payments p ON p.loan_doc_id = lp.loan_doc_id
    ),

    fa_final_horizontal AS (
        SELECT
            var_month AS Month,
            loan_purpose AS `Loan Purpose`,
            sum(os_principal) AS principal_os,
            sum(os_fee) AS fee_os,
            
            sumIf(os_principal, dateDiff('day', due_date, var_last_day) BETWEEN 2 AND 5) AS par_2_and_5,
            sumIf(os_principal, dateDiff('day', due_date, var_last_day) BETWEEN 6 AND 15) AS par_6_and_15,
            sumIf(os_principal, dateDiff('day', due_date, var_last_day) BETWEEN 16 AND 30) AS par_16_and_30,
            sumIf(os_principal, dateDiff('day', due_date, var_last_day) BETWEEN 31 AND 60) AS par_31_and_60,
            sumIf(os_principal, dateDiff('day', due_date, var_last_day) > 60) AS par_60,
            
            sumIf(os_fee, dateDiff('day', due_date, var_last_day) BETWEEN 2 AND 5) AS par_2_and_5_fee,
            sumIf(os_fee, dateDiff('day', due_date, var_last_day) BETWEEN 6 AND 15) AS par_6_and_15_fee,
            sumIf(os_fee, dateDiff('day', due_date, var_last_day) BETWEEN 16 AND 30) AS par_16_and_30_fee,
            sumIf(os_fee, dateDiff('day', due_date, var_last_day) BETWEEN 31 AND 60) AS par_31_and_60_fee,
            sumIf(os_fee, dateDiff('day', due_date, var_last_day) > 60) AS par_60_fee,
            
            sumIf(os_principal + os_fee, dateDiff('day', due_date, var_last_day) > 1) AS `Total overdue`
        FROM fa_loan_os
        GROUP BY loan_purpose
    ),

/* ============================================================
   🔵 2. GROWTH & ASSET FINANCING LOGIC (Installment Level STRICTLY)
============================================================ */
    gf_loan AS (
        SELECT
            l.loan_doc_id AS loan_doc_id,
            l.loan_purpose AS loan_purpose
        FROM loans l
        INNER JOIN loan_txns lt ON lt.loan_doc_id = l.loan_doc_id
        WHERE lt.txn_type = 'af_disbursal'
          AND l.loan_purpose IN ('growth_financing', 'asset_financing')
          AND l.country_code = var_country_code
          AND toDate(l.disbursal_date) <= var_last_day
          AND l.product_id NOT IN (
              SELECT id FROM loan_products WHERE product_type = 'float_vending'
          )
          AND l.status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
          AND l.loan_doc_id NOT IN (
              SELECT loan_doc_id FROM loan_write_off 
              WHERE country_code = var_country_code 
                AND toDate(write_off_date) <= var_last_day 
                AND write_off_status IN ('approved', 'partially_recovered', 'recovered')
          )
        GROUP BY l.loan_doc_id, l.loan_purpose
    ),

    gf_loan_installment AS (
        SELECT
            li.loan_doc_id AS loan_doc_id,
            li.id AS installment_id,
            li.installment_number AS installment_number,
            toFloat64(li.principal_due) AS installment_principal,
            /* BUG FIX: Removed the <= var_last_day clip to capture ALL future fees */
            toFloat64(li.fee_due) AS fee_due, 
            toDate(li.due_date) AS due_date
        FROM loan_installments li
        INNER JOIN gf_loan l ON l.loan_doc_id = li.loan_doc_id
    ),

    gf_payment AS (
        SELECT
            p.loan_doc_id AS loan_doc_id,
            p.installment_number AS installment_number,
            p.installment_id AS installment_id,
            sum(toFloat64(p.principal_amount)) AS paid_principal,
            sum(toFloat64(p.fee_amount)) AS paid_fee
        FROM payment_allocation_items p
        INNER JOIN account_stmts a ON a.id = p.account_stmt_id
        INNER JOIN loan_installments li ON li.id = p.installment_id 
        /* The payment logic stays locked to the reporting month, which is correct */
        WHERE toYYYYMM(stmt_txn_date) <= toUInt32(var_month)
          AND is_reversed = 0
          AND p.country_code = var_country_code
          AND a.country_code = var_country_code
        GROUP BY p.loan_doc_id, p.installment_number, p.installment_id
    ),

    gf_installment_os AS (
        SELECT
            l.loan_doc_id AS loan_doc_id,
            l.loan_purpose AS loan_purpose,
            li.due_date AS due_date,
            greatest(li.installment_principal - coalesce(p.paid_principal, toFloat64(0)), toFloat64(0)) AS os_amount,
            greatest(li.fee_due - coalesce(p.paid_fee, toFloat64(0)), toFloat64(0)) AS fee_os
        FROM gf_loan l
        INNER JOIN gf_loan_installment li ON li.loan_doc_id = l.loan_doc_id 
        LEFT JOIN gf_payment p ON p.loan_doc_id = li.loan_doc_id AND p.installment_number = li.installment_number
    ),

    gf_loan_level_os AS (
        SELECT
            loan_doc_id,
            loan_purpose,
            sum(os_amount) AS loan_os,
            sum(fee_os) AS fee_os,
            /* BUG FIX: Removed AND due_date <= var_last_day to allow true tracking of the next due installment */
            minIf(due_date, os_amount > 0 OR fee_os > 0) AS min_overdue_due_date
        FROM gf_installment_os
        GROUP BY loan_doc_id, loan_purpose
    ),

    gf_current_due AS (
        SELECT 
            e.loan_doc_id AS loan_doc_id,
            ((sum(toFloat64(e.principal_due)) + sum(toFloat64(e.fee_due))) - (sum(coalesce(pa.paid_principal, toFloat64(0))) + sum(coalesce(pa.paid_fee, toFloat64(0))))) AS current_due
        FROM loan_installments e 
        LEFT JOIN gf_payment pa ON pa.installment_id = e.id AND pa.loan_doc_id = e.loan_doc_id
        /* BUG FIX: Removed the date constraints here so 'current_due' calculates against the ENTIRE loan schedule */
        GROUP BY e.loan_doc_id
    ),

    gf_loan_level_par AS (
        SELECT
            loan_doc_id,
            loan_purpose,
            loan_os,
            if(fee_os < 0, toFloat64(0), fee_os) AS fee_os,
            if(loan_os = 0 OR isNull(min_overdue_due_date), 0, dateDiff('day', min_overdue_due_date, var_last_day)) AS par_days
        FROM gf_loan_level_os
    ),

    gf_final_horizontal AS (
        SELECT
            var_month AS Month,
            la.loan_purpose AS `Loan Purpose`,
            sum(la.loan_os) AS principal_os,
            sum(la.fee_os) AS fee_os,
            
            sumIf(la.loan_os, la.par_days BETWEEN 2 AND 5) AS par_2_and_5,
            sumIf(la.loan_os, la.par_days BETWEEN 6 AND 15) AS par_6_and_15,
            sumIf(la.loan_os, la.par_days BETWEEN 16 AND 30) AS par_16_and_30,
            sumIf(la.loan_os, la.par_days BETWEEN 31 AND 60) AS par_31_and_60,
            sumIf(la.loan_os, la.par_days > 60) AS par_60,
            
            sumIf(la.fee_os, la.par_days BETWEEN 2 AND 5) AS par_2_and_5_fee,
            sumIf(la.fee_os, la.par_days BETWEEN 6 AND 15) AS par_6_and_15_fee,
            sumIf(la.fee_os, la.par_days BETWEEN 16 AND 30) AS par_16_and_30_fee,
            sumIf(la.fee_os, la.par_days BETWEEN 31 AND 60) AS par_31_and_60_fee,
            sumIf(la.fee_os, la.par_days > 60) AS par_60_fee,
            
            sumIf(cd.current_due, la.par_days > 1) AS `Total overdue`
        FROM gf_loan_level_par la
        INNER JOIN loans l ON la.loan_doc_id = l.loan_doc_id
        LEFT JOIN gf_current_due cd ON l.loan_doc_id = cd.loan_doc_id
        GROUP BY la.loan_purpose
    )

/* ============================================================
   🔗 3. FINAL UNION
============================================================ */
SELECT * FROM fa_final_horizontal
UNION ALL
SELECT * FROM gf_final_horizontal
ORDER BY `Loan Purpose` DESC;









