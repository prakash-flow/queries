WITH params AS (
    SELECT 
        '202501' AS var_write_off_month,
        'UGA' AS var_country_code,
        
        -- Dynamically calculate the first and last day based on the YYYYMM string
        toDate(concat(substring(var_write_off_month, 1, 4), '-', substring(var_write_off_month, 5, 2), '-01')) AS var_start_date,
        toLastDayOfMonth(var_start_date) AS var_end_date
)

SELECT 
    (SELECT var_write_off_month FROM params) AS `write off month`,
    bc.write_off_date AS `Loan Write Off Date`,
    bc.loan_purpose AS `Loan Purpose`,
    bc.write_off_type AS `Write Off Type`,
    bc.loan_doc_id AS `Loan ID`,
    
    -- Transaction Identifiers (Comma-separated if a loan has multiple payments)
    vr.account_provider_codes AS `Account Provider Code`,
    vr.account_numbers AS `Account Number`,
    vr.transaction_ids AS `Transaction Id`,
    vr.transaction_dates AS `Transaction Date`,
    
    -- Write Off Totals (Native numbers, guaranteed no fan-out duplication)
    bc.write_off_amount AS `Write Off Amount`,
    bc.write_off_principal AS `Write Off Principal`,
    bc.write_off_fee AS `Write Off Fee`,    
    
    -- Aggregated Recovery Totals (Native numbers)
    vr.total_recovery_amount AS `Recovery Amount`,
    vr.total_recovery_principal AS `Recovery Principal`,
    vr.total_recovery_fee AS `Recovery Fee`,
    vr.total_paid_penalty AS `Paid Penalty`,
    vr.total_paid_charges AS `Paid Charges`,
    vr.total_paid_excess AS `Paid Excess`,
    
    vr.recovery_month_offsets AS `Recovery Month Offset`

FROM 
(
    -- 1. BASE COHORT (Strictly 1 Row Per Loan)
    SELECT 
        l.loan_doc_id AS loan_doc_id,       
        l.loan_purpose AS loan_purpose,
        lw.write_off_date AS write_off_date,
        lw.type AS write_off_type,
        lw.write_off_amount AS write_off_amount,
        lw.principal AS write_off_principal,
        lw.fee AS write_off_fee
    FROM loans l
    INNER JOIN loan_write_off lw 
        ON lw.loan_doc_id = l.loan_doc_id
        
    -- Optimized: Using >= and <= so ClickHouse can use partition/primary indexes
    WHERE lw.write_off_date >= (SELECT var_start_date FROM params)
      AND lw.write_off_date <= (SELECT var_end_date FROM params)
      AND l.country_code = (SELECT var_country_code FROM params)                                
) AS bc

LEFT JOIN 
(
    -- 2. VALID RECOVERIES (Rolled up to 1 Row Per Loan)
    SELECT 
        lw.loan_doc_id AS loan_doc_id,      
        
        -- Flatten text/dates into single strings to prevent row duplication
        arrayStringConcat(groupArray(nullIf(a.acc_prvdr_code, '')), ', ') AS account_provider_codes,
        arrayStringConcat(groupArray(nullIf(a.acc_number, '')), ', ') AS account_numbers,
        arrayStringConcat(groupArray(nullIf(t.txn_id, '')), ', ') AS transaction_ids,
        arrayStringConcat(groupArray(toString(nullIf(a.stmt_txn_date, toDateTime('1970-01-01 00:00:00')))), ', ') AS transaction_dates,
        arrayStringConcat(groupArray(toString(dateDiff('month', toStartOfMonth(lw.write_off_date), toStartOfMonth(a.stmt_txn_date)))), ', ') AS recovery_month_offsets,
        
        -- Sum the financials
        sum(t.amount) AS total_recovery_amount,
        sum(t.principal) AS total_recovery_principal,
        sum(t.fee) AS total_recovery_fee,
        sum(t.penalty) AS total_paid_penalty,
        sum(t.charges) AS total_paid_charges,
        sum(t.excess) AS total_paid_excess

    FROM loan_write_off lw
    INNER JOIN loan_txns t 
        ON t.loan_doc_id = lw.loan_doc_id
    INNER JOIN account_stmts a 
        ON a.stmt_txn_id = t.txn_id
    LEFT JOIN closure_date_records cdr
        ON cdr.month = toUInt32(formatDateTime(a.stmt_txn_date, '%Y%m'))
        AND cdr.country_code = (SELECT var_country_code FROM params)
        AND cdr.status = 'enabled'
        
    -- Optimized: Using >= and <= so ClickHouse can use partition/primary indexes
    WHERE lw.write_off_date >= (SELECT var_start_date FROM params)
      AND lw.write_off_date <= (SELECT var_end_date FROM params)
      AND t.txn_type = 'payment' 
      AND a.acc_txn_type = 'payment'
      AND toDate(lw.write_off_date) < toDate(t.txn_date)
      AND (
          a.realization_date <= cdr.closure_date 
          OR 
          (cdr.closure_date IS NULL AND a.realization_date IS NOT NULL) 
      )
    GROUP BY lw.loan_doc_id
) AS vr 
    USING (loan_doc_id)                     

ORDER BY `Loan ID`;