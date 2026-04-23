-- ============================================================
-- PART 1: Customer Counts — Combo 1 (FA & Adj FA)
-- Metrics: Registered, Enabled, Active, Inactive
-- ============================================================

WITH base_params AS (
    SELECT
        '202601' AS var_month,
        'RWA'    AS var_country_code
),

params AS (
    SELECT
        var_month,
        var_country_code,
        toDate(concat(substring(var_month, 1, 4), '-', substring(var_month, 5, 2), '-01')) AS var_start_date,
        toLastDayOfMonth(toDate(concat(substring(var_month, 1, 4), '-', substring(var_month, 5, 2), '-01'))) AS var_end_date,
        formatDateTime(subtractMonths(toDate(concat(substring(var_month, 1, 4), '-', substring(var_month, 5, 2), '-01')), 1), '%Y%m') AS var_prev_month,
        toDateTime(concat(toString(CAST((SELECT max(closure_date) FROM closure_date_records WHERE country_code = (SELECT var_country_code FROM base_params) AND month = (SELECT var_month FROM base_params) AND status = 'enabled') AS Date)), ' 23:59:59')) AS var_realization_date,
        toDateTime(concat(toString(CAST((SELECT max(closure_date) FROM closure_date_records WHERE country_code = (SELECT var_country_code FROM base_params) AND month = formatDateTime(subtractMonths(toDate(concat(substring((SELECT var_month FROM base_params), 1, 4), '-', substring((SELECT var_month FROM base_params), 5, 2), '-01')), 1), '%Y%m') AND status = 'enabled') AS Date)), ' 23:59:59')) AS var_prev_realization_date
    FROM base_params
),

-- ============================================================
-- CUSTOMER STATUS CTEs  (as-at end of month)
-- ============================================================

disabled_cust AS (
    SELECT DISTINCT r1.record_code AS cust_id
    FROM record_audits r1
    INNER JOIN (
        SELECT record_code, max(id) AS id
        FROM record_audits
        WHERE toDate(created_at) <= (SELECT var_end_date FROM params)
          AND country_code        = (SELECT var_country_code FROM params)
        GROUP BY record_code
    ) r2 ON r1.id = r2.id
    WHERE JSONExtractString(r1.data_after, 'status') = 'disabled'
),

active_cust_fa AS (
    SELECT DISTINCT l.cust_id AS act_fa_cust_id
    FROM loans l
    INNER JOIN loan_txns t ON l.loan_doc_id = t.loan_doc_id
    LEFT  JOIN disabled_cust d ON l.cust_id = d.cust_id
    WHERE toDate(t.txn_date) >= subtractDays((SELECT var_end_date FROM params), 30)
      AND toDate(t.txn_date)  <= (SELECT var_end_date FROM params)
      AND l.country_code       = (SELECT var_country_code FROM params)
      AND t.txn_type           = 'disbursal'
      AND l.product_id NOT IN  (43, 75, 300)
      AND l.status NOT IN      ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
      AND d.cust_id IS NULL
),

reg_cust AS (
    SELECT DISTINCT b.cust_id AS reg_cust_id
    FROM borrowers b
    WHERE toDate(b.reg_date) <= (SELECT var_end_date FROM params)
      AND b.country_code      = (SELECT var_country_code FROM params)
),

enabled_cust AS (
    SELECT DISTINCT b.cust_id AS enb_cust_id
    FROM borrowers b
    LEFT JOIN disabled_cust d ON b.cust_id = d.cust_id
    WHERE toDate(b.reg_date) <= (SELECT var_end_date FROM params)
      AND b.country_code      = (SELECT var_country_code FROM params)
      AND d.cust_id IS NULL
),

inactive_cust_fa AS (
    SELECT DISTINCT l.cust_id AS ina_fa_cust_id
    FROM loans l
    INNER JOIN (
        SELECT DISTINCT record_code
        FROM record_audits
        WHERE country_code = (SELECT var_country_code FROM params)
          AND toDate(created_at) <= (SELECT var_end_date FROM params)
    ) ra ON l.cust_id = ra.record_code
    LEFT  JOIN disabled_cust d  ON l.cust_id = d.cust_id
    WHERE l.country_code    = (SELECT var_country_code FROM params)
      AND l.product_id NOT IN (43, 75, 300)
      AND l.status NOT IN     ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
      AND d.cust_id IS NULL
      AND l.cust_id NOT IN (
          SELECT DISTINCT l2.cust_id
          FROM loans l2
          INNER JOIN loan_txns t ON l2.loan_doc_id = t.loan_doc_id
          WHERE toDate(t.txn_date) >= subtractDays((SELECT var_end_date FROM params), 30)
            AND toDate(t.txn_date) <= (SELECT var_end_date FROM params)
            AND t.txn_type = 'disbursal'
            AND l2.country_code = (SELECT var_country_code FROM params)
      )
),

active_cust_ast AS (
    SELECT DISTINCT l.cust_id AS act_ast_cust_id, l.loan_purpose
    FROM borrowers b
    INNER JOIN loans l ON b.cust_id = l.cust_id
    INNER JOIN loan_txns t ON l.loan_doc_id = t.loan_doc_id
    WHERE b.country_code = (SELECT var_country_code FROM params)
      AND l.disbursal_date <= toDateTime(concat(toString((SELECT var_end_date FROM params)), ' 23:59:59'))
      AND l.due_date       >= toDateTime(concat(toString((SELECT var_end_date FROM params)), ' 23:59:59'))
      AND t.txn_type IN ('disbursal', 'af_disbursal')
      AND l.product_id NOT IN (43, 75, 300)
      AND l.status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
      AND l.loan_purpose IN ('growth_financing', 'asset_financing')
),

inactive_cust_ast AS (
    SELECT DISTINCT l.cust_id AS ina_ast_cust_id, l.loan_purpose
    FROM borrowers b
    INNER JOIN loans l ON b.cust_id = l.cust_id
    INNER JOIN loan_txns t ON l.loan_doc_id = t.loan_doc_id
    WHERE b.country_code = (SELECT var_country_code FROM params)
      AND t.txn_type = 'af_disbursal'
      AND l.due_date <= toDateTime(concat(toString((SELECT var_end_date FROM params)), ' 23:59:59'))
      AND l.product_id NOT IN (43, 75, 300)
      AND l.status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
      AND l.loan_purpose IN ('growth_financing', 'asset_financing')
      AND l.cust_id NOT IN (
          SELECT DISTINCT l2.cust_id
          FROM borrowers b2
          INNER JOIN loans l2 ON b2.cust_id = l2.cust_id
          INNER JOIN loan_txns t ON l2.loan_doc_id = t.loan_doc_id
          WHERE b2.country_code = (SELECT var_country_code FROM params)
            AND toDate(t.txn_date) >= subtractDays((SELECT var_end_date FROM params), 30)
            AND toDate(t.txn_date) <= (SELECT var_end_date FROM params)
            AND t.txn_type = 'af_disbursal'
            AND l2.product_id NOT IN (43, 75, 300)
            AND l2.status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
            AND l2.loan_purpose IN ('growth_financing', 'asset_financing')
      )
),

-- ============================================================
-- PORTFOLIO OS & PAR CTEs
-- ============================================================

valid_loans AS (
    SELECT DISTINCT l.loan_doc_id AS vl_loan_doc_id, l.loan_purpose AS vl_loan_purpose
    FROM loans l
    INNER JOIN loan_txns lt ON lt.loan_doc_id = l.loan_doc_id
    WHERE l.country_code = (SELECT var_country_code FROM params)
      AND lt.txn_type IN ('disbursal', 'af_disbursal')
      AND toDate(l.disbursal_date) <= (SELECT var_end_date FROM params)
      AND l.product_id NOT IN (43, 75, 300)
      AND l.status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
      AND l.loan_doc_id NOT IN (
          SELECT loan_doc_id
          FROM loan_write_off
          WHERE country_code = (SELECT var_country_code FROM params)
            AND toDate(write_off_date) <= (SELECT var_end_date FROM params)
            AND write_off_status IN ('approved', 'partially_recovered', 'recovered')
      )
),

loan_installment AS (
    SELECT
        loan_doc_id AS li_loan_doc_id,
        installment_number AS li_install_num,
        principal_due AS li_principal,
        if(toDate(due_date) <= (SELECT var_end_date FROM params), fee_due, 0) AS li_fee_due,
        toDate(due_date) AS li_due_date
    FROM loan_installments
    WHERE loan_doc_id IN (SELECT vl_loan_doc_id FROM valid_loans)
),

payment AS (
    SELECT
        p.loan_doc_id AS pay_loan_doc_id,
        p.installment_number AS pay_install_num,
        p.installment_id AS pay_install_id,
        sum(p.principal_amount) AS paid_principal,
        sum(p.fee_amount) AS paid_fee
    FROM payment_allocation_items p
    INNER JOIN account_stmts a ON a.id = p.account_stmt_id
    INNER JOIN loan_installments li ON li.id = p.installment_id 
    WHERE p.loan_doc_id IN (SELECT vl_loan_doc_id FROM valid_loans)
      AND toDate(a.stmt_txn_date) <= (SELECT var_end_date FROM params)
      AND is_reversed = 0
      AND p.country_code = (SELECT var_country_code FROM params)
      AND a.country_code = (SELECT var_country_code FROM params)
    GROUP BY p.loan_doc_id, p.installment_number, p.installment_id
),

installment_os AS (
    SELECT
        l.vl_loan_doc_id AS ios_loan_doc_id,
        l.vl_loan_purpose AS ios_loan_purpose,
        li.li_due_date AS ios_due_date,
        greatest(li.li_principal - ifNull(p.paid_principal, 0), 0) AS ios_amount,
        greatest(li.li_fee_due - ifNull(p.paid_fee, 0), 0) AS ios_fee_amount
    FROM valid_loans l
    INNER JOIN loan_installment li ON li.li_loan_doc_id = l.vl_loan_doc_id 
    LEFT  JOIN payment p ON p.pay_loan_doc_id = li.li_loan_doc_id AND p.pay_install_num = li.li_install_num
),

loan_level_os AS (
    SELECT
        ios_loan_doc_id AS llos_loan_doc_id,
        ios_loan_purpose AS llos_loan_purpose,
        sum(ios_amount) AS llos_loan_os,
        sum(ios_fee_amount) AS llos_fee_os,
        min(CASE
            WHEN (ios_amount > 0 OR ios_fee_amount > 0) AND toDate(ios_due_date) <= (SELECT var_end_date FROM params)
            THEN toDate(ios_due_date)
        END) AS llos_min_overdue
    FROM installment_os
    GROUP BY ios_loan_doc_id, ios_loan_purpose
),

loan_level_par AS (
    SELECT
        llos_loan_doc_id AS par_loan_doc_id,
        llos_loan_purpose AS par_loan_purpose,
        llos_loan_os AS par_loan_os,
        if(llos_fee_os < 0, 0, llos_fee_os) AS par_fee_os,
        CASE
            WHEN llos_loan_os = 0 OR llos_min_overdue IS NULL THEN 0
            ELSE dateDiff('day', llos_min_overdue, (SELECT var_end_date FROM params))
        END AS par_days
    FROM loan_level_os
),

-- ============================================================
-- COMBO 1 (FA & ADJ FA) PORTFOLIO OS & PAR CTEs
-- ============================================================

fa_loan_principal AS (
    SELECT 
        l.loan_doc_id AS fap_loan_doc_id,
        l.loan_purpose AS fap_loan_purpose,
        l.loan_principal AS fap_principal,
        l.flow_fee AS fap_flow_fee,
        l.due_date AS fap_due_date
    FROM loans l
    INNER JOIN loan_txns lt ON lt.loan_doc_id = l.loan_doc_id
    WHERE lt.txn_type = 'disbursal'
      AND toDate(lt.realization_date) <= (SELECT var_realization_date FROM params)
      AND l.country_code = (SELECT var_country_code FROM params)
      AND toDate(l.disbursal_date) <= (SELECT var_end_date FROM params)
      AND l.product_id NOT IN (43, 75, 300)
      AND l.status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
      AND l.loan_doc_id NOT IN (
          SELECT loan_doc_id 
          FROM loan_write_off 
          WHERE country_code = (SELECT var_country_code FROM params)
            AND toDate(write_off_date) < (SELECT var_end_date FROM params)
            AND write_off_status IN ('approved', 'partially_recovered', 'recovered')
      )
),

fa_loan_payments AS (
    SELECT 
        loan_doc_id AS fapay_loan_doc_id,
        sum(CASE WHEN txn_type = 'payment' THEN toFloat64(principal) ELSE 0 END) AS fapay_principal,
        sum(CASE WHEN txn_type IN ('payment', 'fee_waiver') THEN toFloat64(fee) ELSE 0 END) AS fapay_fee
    FROM loan_txns
    WHERE loan_doc_id IN (SELECT fap_loan_doc_id FROM fa_loan_principal)
      AND toDate(txn_date) <= (SELECT var_end_date FROM params)
      AND toDate(realization_date) <= (SELECT var_realization_date FROM params)
    GROUP BY loan_doc_id
),

fa_loan_level_os AS (
    SELECT
        lp.fap_loan_doc_id AS fa_os_loan_doc_id,
        lp.fap_loan_purpose AS fa_os_loan_purpose,
        lp.fap_due_date AS fa_os_due_date,
        greatest(toFloat64(lp.fap_principal) - coalesce(p.fapay_principal, 0), 0) AS fa_os_principal,
        greatest(toFloat64(lp.fap_flow_fee) - coalesce(p.fapay_fee, 0), 0) AS fa_os_fee
    FROM fa_loan_principal lp
    LEFT JOIN fa_loan_payments p ON p.fapay_loan_doc_id = lp.fap_loan_doc_id
),

fa_loan_level_par AS (
    SELECT
        fa_os_loan_doc_id AS fa_par_loan_doc_id,
        fa_os_loan_purpose AS fa_par_loan_purpose,
        fa_os_principal AS fa_par_loan_os,
        fa_os_fee AS fa_par_fee_os,
        CASE 
            WHEN fa_os_principal = 0 THEN 0
            ELSE dateDiff('day', toDate(fa_os_due_date), (SELECT var_end_date FROM params))
        END AS fa_par_days
    FROM fa_loan_level_os
),

-- ============================================================
-- REVENUE METRICS CTEs (Combo 1 & Combo 2)
-- ============================================================

fa_revenue AS (
    SELECT
        l.loan_purpose AS fa_rev_loan_purpose,
        CASE 
            WHEN l.loan_purpose IN ('float_advance', 'adj_float_advance') 
            THEN ifNull(tm.full_name, rm.full_name)
            ELSE 'ALL'
        END AS fa_rev_tm_name,
        SUM(IF(
            lw.loan_doc_id IS NULL OR lw.write_off_date IS NULL OR toDate(t.txn_date) <= toDate(lw.write_off_date), 
            toFloat64(t.fee), 
            0
        )) AS total_fee_received,
        SUM(IF(
            lw.loan_doc_id IS NULL OR lw.write_off_date IS NULL OR toDate(t.txn_date) <= toDate(lw.write_off_date), 
            toFloat64(t.penalty), 
            0
        )) AS total_penalty_received,
        SUM(IF(
            lw.loan_doc_id IS NOT NULL AND lw.write_off_date IS NOT NULL AND toDate(t.txn_date) > toDate(lw.write_off_date), 
            toFloat64(t.amount), 
            0
        )) AS total_recovery
    FROM loans l
    INNER JOIN loan_txns t ON l.loan_doc_id = t.loan_doc_id
    INNER JOIN account_stmts ast ON t.txn_id = ast.stmt_txn_id
    INNER JOIN accounts acc ON ast.account_id = acc.id
    LEFT JOIN loan_write_off lw ON lw.loan_doc_id = l.loan_doc_id
        AND lw.country_code = l.country_code 
        AND toDate(lw.write_off_date) <= (SELECT var_end_date FROM params)
    LEFT JOIN persons rm ON rm.id = l.flow_rel_mgr_id
    LEFT JOIN persons tm ON tm.id = rm.report_to
    WHERE acc.id IN (4182,15839,8403,8284,8285,16919,34119,34120,40795,40796,9192,10111)
      AND l.loan_purpose IN ('float_advance', 'adj_float_advance')
      AND (
          (ast.stmt_txn_date >= toDateTime(concat(toString((SELECT var_start_date FROM params)), ' 00:00:00')) 
           AND ast.stmt_txn_date <= toDateTime(concat(toString((SELECT var_end_date FROM params)), ' 23:59:59')) 
           AND ast.realization_date <= (SELECT var_realization_date FROM params)) 
          OR 
          (ast.stmt_txn_date < toDateTime(concat(toString((SELECT var_start_date FROM params)), ' 00:00:00')) 
           AND ast.realization_date > (SELECT var_prev_realization_date FROM params) 
           AND ast.realization_date <= (SELECT var_realization_date FROM params))
      )
      AND t.txn_type = 'payment'
      AND toDate(t.txn_date) <= (SELECT var_end_date FROM params)
      AND ast.acc_txn_type = 'payment'
      AND t.country_code = (SELECT var_country_code FROM params)
      AND ast.country_code = (SELECT var_country_code FROM params)
      AND l.country_code = (SELECT var_country_code FROM params)
      AND acc.country_code = (SELECT var_country_code FROM params)
    GROUP BY l.loan_purpose, fa_rev_tm_name
),

ast_revenue AS (
    SELECT
        l.loan_purpose AS ast_rev_loan_purpose,
        SUM(CASE WHEN (
            (li.due_date >= toDateTime(concat(toString((SELECT var_start_date FROM params)), ' 00:00:00')) AND li.due_date <= toDateTime(concat(toString((SELECT var_end_date FROM params)), ' 23:59:59')))
            OR
            (li.due_date <= toDateTime(concat(toString(subtractDays(toDate((SELECT var_start_date FROM params)), 1)), ' 23:59:59')) 
             AND (
                 (a.stmt_txn_date >= toDateTime(concat(toString((SELECT var_start_date FROM params)), ' 00:00:00')) AND a.stmt_txn_date <= toDateTime(concat(toString((SELECT var_end_date FROM params)), ' 23:59:59')) AND a.realization_date <= (SELECT var_realization_date FROM params))
                 OR
                 (a.stmt_txn_date < toDateTime(concat(toString((SELECT var_start_date FROM params)), ' 00:00:00')) AND a.realization_date > (SELECT var_prev_realization_date FROM params) AND a.realization_date <= (SELECT var_realization_date FROM params))
             ))
        ) AND (
             (a.stmt_txn_date >= toDateTime(concat(toString((SELECT var_start_date FROM params)), ' 00:00:00')) AND a.stmt_txn_date <= toDateTime(concat(toString((SELECT var_end_date FROM params)), ' 23:59:59')) AND a.realization_date <= (SELECT var_realization_date FROM params))
             OR
             (a.stmt_txn_date < toDateTime(concat(toString((SELECT var_start_date FROM params)), ' 00:00:00')) AND a.realization_date > (SELECT var_prev_realization_date FROM params) AND a.realization_date <= (SELECT var_realization_date FROM params))
        ) THEN toFloat64(pai.fee_amount) ELSE 0 END) AS total_fee_received,
        SUM(CASE WHEN (
            (li.due_date >= toDateTime(concat(toString((SELECT var_start_date FROM params)), ' 00:00:00')) AND li.due_date <= toDateTime(concat(toString((SELECT var_end_date FROM params)), ' 23:59:59')))
            AND a.stmt_txn_date <= toDateTime(concat(toString(subtractDays(toDate((SELECT var_start_date FROM params)), 1)), ' 23:59:59'))
            AND a.realization_date <= (SELECT var_prev_realization_date FROM params)
        ) THEN toFloat64(pai.fee_amount) ELSE 0 END) AS unallocated_fee
    FROM payment_allocation_items pai
    INNER JOIN account_stmts a ON a.id = pai.account_stmt_id
    INNER JOIN loan_installments li ON li.id = pai.installment_id
    INNER JOIN loans l ON l.loan_doc_id = pai.loan_doc_id
    INNER JOIN accounts acc ON a.account_id = acc.id
    WHERE pai.country_code = (SELECT var_country_code FROM params) 
      AND pai.is_reversed = 0
      AND a.acc_txn_type = 'af_payment'
      AND a.country_code = (SELECT var_country_code FROM params)
      AND a.stmt_txn_date <= toDateTime(concat(toString((SELECT var_end_date FROM params)), ' 23:59:59'))
      AND acc.id IN (4182,15839,8403,8284,8285,16919,34119,34120,40795,40796,9192,10111)
      AND l.loan_purpose IN ('growth_financing', 'asset_financing')
    GROUP BY l.loan_purpose
),

ast_sales_commission AS (
    SELECT 
        l.loan_purpose AS sc_loan_purpose,
        SUM(toFloat64(a.cr_amt)) AS sales_commission
    FROM account_stmts a 
    INNER JOIN loan_txns lt ON a.stmt_txn_id = lt.txn_id 
    INNER JOIN loans l ON lt.loan_doc_id = l.loan_doc_id
    LEFT JOIN accounts acc ON a.account_id = acc.id
    WHERE a.country_code = (SELECT var_country_code FROM params)
      AND lt.country_code = (SELECT var_country_code FROM params)
      AND l.country_code = (SELECT var_country_code FROM params)
      AND l.loan_purpose IN ('growth_financing', 'asset_financing')
      AND lt.txn_type = 'af_sales_commission'
      AND a.acc_txn_type = 'af_sales_commission'
      AND a.stmt_txn_type = 'credit'
      AND (
          (
            a.stmt_txn_date >= toDateTime(concat(toString((SELECT var_start_date FROM params)), ' 00:00:00')) 
            AND a.stmt_txn_date <= toDateTime(concat(toString((SELECT var_end_date FROM params)), ' 23:59:59')) 
            AND a.realization_date <= (SELECT var_realization_date FROM params)
            AND acc.id IN (4182,15839,8403,8284,8285,16919,34119,34120,40795,40796,9192,10111)
          )
          OR 
          (
            a.stmt_txn_date < toDateTime(concat(toString((SELECT var_start_date FROM params)), ' 00:00:00')) 
            AND a.realization_date > (SELECT var_prev_realization_date FROM params) 
            AND a.realization_date <= (SELECT var_realization_date FROM params)
            AND a.acc_number NOT IN ('732844390','792577307')
            AND (a.recon_status NOT IN ('99_wrong_stmt_import') OR a.recon_status IS NULL)
          )
      )
    GROUP BY l.loan_purpose
)

-- ============================================================
-- FINAL SELECT — Unified Query
-- ============================================================

SELECT
    (SELECT var_month FROM params)              AS `Month`,
    l.loan_purpose                              AS `Loan Purpose`,
    CASE 
        WHEN l.loan_purpose IN ('float_advance', 'adj_float_advance') 
        THEN ifNull(tm.full_name, rm.full_name)
        ELSE 'ALL'
    END                                         AS `TM Name`,
    countDistinct(reg_cust_id)                  AS `Reg Customers`,
    countDistinct(CASE WHEN l.loan_purpose IN ('growth_financing', 'asset_financing') THEN reg_cust_id ELSE enb_cust_id END) AS `Enabled Customers`,
    countDistinct(coalesce(act_fa_cust_id, act_ast_cust_id)) AS `Active Customers`,
    countDistinct(coalesce(ina_fa_cust_id, ina_ast_cust_id)) AS `Inactive Customers`,
    sum(ifNull(coalesce(toFloat64(fa_llp.fa_par_loan_os), toFloat64(llp.par_loan_os)), 0)) AS `Total OS (Principal)`,
    sum(if(ifNull(coalesce(fa_llp.fa_par_days, llp.par_days), 0) <= 10, ifNull(coalesce(toFloat64(fa_llp.fa_par_loan_os), toFloat64(llp.par_loan_os)), 0), 0)) AS `Net Portfolio OS (Excl PAR 10)`,
    sum(if(ifNull(coalesce(fa_llp.fa_par_days, llp.par_days), 0) > 120, ifNull(coalesce(toFloat64(fa_llp.fa_par_loan_os), toFloat64(llp.par_loan_os)), 0), 0)) AS `PAR 120 (Write-offs)`,
    max(
        ifNull(coalesce(fa_rev.total_fee_received, ast_rev.total_fee_received), 0) + 
        ifNull(ast_rev.unallocated_fee, 0) + 
        ifNull(fa_rev.total_recovery, 0) + 
        ifNull(fa_rev.total_penalty_received, 0) + 
        ifNull(ast_sc.sales_commission, 0)
    ) AS `Revenue (Fee + Other Incomes)`
FROM loans l
LEFT  JOIN persons rm        ON rm.id = l.flow_rel_mgr_id
LEFT  JOIN persons tm        ON tm.id = rm.report_to
LEFT  JOIN reg_cust          ON l.cust_id = reg_cust_id
LEFT  JOIN enabled_cust      ON l.cust_id = enb_cust_id
LEFT  JOIN active_cust_fa    ON l.cust_id = act_fa_cust_id   AND l.loan_purpose IN ('float_advance', 'adj_float_advance')
LEFT  JOIN inactive_cust_fa  ON l.cust_id = ina_fa_cust_id   AND l.loan_purpose IN ('float_advance', 'adj_float_advance')
LEFT  JOIN active_cust_ast   ON l.cust_id = act_ast_cust_id  AND l.loan_purpose = active_cust_ast.loan_purpose
LEFT  JOIN inactive_cust_ast ON l.cust_id = ina_ast_cust_id  AND l.loan_purpose = inactive_cust_ast.loan_purpose
LEFT  JOIN loan_level_par llp ON l.loan_doc_id = llp.par_loan_doc_id AND l.loan_purpose IN ('growth_financing', 'asset_financing')
LEFT  JOIN fa_loan_level_par fa_llp ON l.loan_doc_id = fa_llp.fa_par_loan_doc_id AND l.loan_purpose IN ('float_advance', 'adj_float_advance')
LEFT  JOIN fa_revenue fa_rev ON l.loan_purpose = fa_rev.fa_rev_loan_purpose AND CASE WHEN l.loan_purpose IN ('float_advance', 'adj_float_advance') THEN ifNull(tm.full_name, rm.full_name) ELSE 'ALL' END = fa_rev.fa_rev_tm_name
LEFT  JOIN ast_revenue ast_rev ON l.loan_purpose = ast_rev.ast_rev_loan_purpose
LEFT  JOIN ast_sales_commission ast_sc ON l.loan_purpose = ast_sc.sc_loan_purpose
WHERE l.country_code      = (SELECT var_country_code FROM params)
  AND l.product_id NOT IN  (43, 75, 300)
  AND l.status NOT IN      ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
  AND l.loan_purpose IN    ('float_advance', 'adj_float_advance', 'growth_financing', 'asset_financing')
GROUP BY l.loan_purpose, `TM Name`;
