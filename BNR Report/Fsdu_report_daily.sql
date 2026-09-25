-- ASIGMA DCGF reports - day-wise, for manual sending / cross-verifying
-- app/Scripts/python/asigma/send_reports.py (same logic and the same field names as the API payload).
--
-- Set the date range (default: today - 5 days, same as DEFAULT_DAYS_BACK in send_reports.py) and the sub-lenders (comma separated, e.g. 'FSD2,UDFC'),
-- then uncomment ONE of the SELECTs at the bottom.

SET @country_code     = 'UGA';
SET @sub_lender_codes = 'FSD2';
SET @loan_purposes    = 'float_advance';                        -- comma separated, same as LOAN_PURPOSES in reports.py
SET @from_date        = DATE_SUB(CURDATE(), INTERVAL 5 DAY);   -- or e.g. '2026-09-22'
SET @to_date          = DATE_SUB(CURDATE(), INTERVAL 5 DAY);   -- or e.g. '2026-09-22'

SET @start_date = CONCAT(DATE(@from_date), ' 00:00:00');
SET @end_date   = CONCAT(DATE(@to_date), ' 23:59:59');
SET @isd_code   = (SELECT isd_code FROM markets WHERE country_code = @country_code);

SELECT @country_code, @sub_lender_codes, @start_date, @end_date, @isd_code;

WITH txn_totals AS (
    SELECT
        l.loan_doc_id,
        SUM(IF(t.txn_type = 'payment', t.principal, 0)) AS paid_principal,
        SUM(IF(t.txn_type = 'payment', t.fee, 0)) AS paid_fee,
        SUM(IF(t.txn_type = 'fee_waiver', t.fee, 0)) AS fee_waiver,
        MAX(IF(t.txn_type = 'payment' AND (t.principal > 0 OR t.fee > 0), t.txn_date, NULL)) AS paid_date,
        SUM(IF(t.txn_type = 'payment' AND t.txn_date <= DATE_ADD(l.due_date, INTERVAL 1 DAY), t.principal + t.fee, 0)) AS amount_recived,
        SUM(IF(t.txn_type = 'payment' AND t.txn_date > DATE_ADD(l.due_date, INTERVAL 1 DAY), t.principal + t.fee, 0)) AS amount_recoverd,
        SUM(IF(t.txn_type = 'payment' AND t.txn_date > DATE_ADD(l.due_date, INTERVAL 1 DAY), t.principal, 0)) AS principal_recoverd,
        MAX(IF(t.txn_type = 'payment' AND t.txn_date > DATE_ADD(l.due_date, INTERVAL 1 DAY)
               AND (t.principal > 0 OR t.fee > 0), t.txn_date, NULL)) AS last_recovery_date
    FROM loans l
    JOIN loan_txns t ON t.loan_doc_id = l.loan_doc_id
    WHERE l.country_code = @country_code
      AND l.status NOT IN ('pending_disbursal', 'pending_mnl_dsbrsl', 'voided', 'hold')
      AND FIND_IN_SET(l.sub_lender_code, @sub_lender_codes)
      AND FIND_IN_SET(l.loan_purpose, @loan_purposes)
      AND t.txn_type IN ('payment', 'fee_waiver')
      AND t.txn_date <= @end_date
      AND t.realization_date <= @end_date
    GROUP BY l.loan_doc_id
),

loan_os AS (
    SELECT
        l.cust_id,
        l.loan_doc_id,
        l.loan_principal,
        l.flow_fee,
        l.interest_rate,
        l.disbursal_date,
        l.due_date,
        l.duration,
        l.loan_purpose,
        l.acc_number,
        IFNULL(t.paid_principal, 0) AS paid_principal,
        IFNULL(t.paid_fee, 0) AS paid_fee,
        l.loan_principal - IFNULL(t.paid_principal, 0) AS principal_os,
        l.flow_fee - (IFNULL(t.paid_fee, 0) + IFNULL(t.fee_waiver, 0)) AS fee_os,
        (l.loan_principal - IFNULL(t.paid_principal, 0))
            + (l.flow_fee - (IFNULL(t.paid_fee, 0) + IFNULL(t.fee_waiver, 0))) AS outstanding,
        DATEDIFF(@end_date, l.due_date) AS par_day,
        t.paid_date,
        t.amount_recoverd,
        t.principal_recoverd,
        t.last_recovery_date,
        (l.loan_principal + l.flow_fee) - (t.amount_recived + IFNULL(t.fee_waiver, 0)) AS before_overdue_due_amount
    FROM loans l
    LEFT JOIN txn_totals t ON t.loan_doc_id = l.loan_doc_id
    WHERE l.country_code = @country_code
      AND l.status NOT IN ('pending_disbursal', 'pending_mnl_dsbrsl', 'voided', 'hold')
      AND FIND_IN_SET(l.sub_lender_code, @sub_lender_codes)
      AND FIND_IN_SET(l.loan_purpose, @loan_purposes)
),

loan_status AS (
    SELECT
        os.*,
        CASE
            WHEN os.outstanding <= 0 THEN 'settled'
            WHEN os.par_day <= 0 THEN 'normal'
            WHEN os.par_day BETWEEN 1 AND 89 THEN 'Watch'
            WHEN os.par_day BETWEEN 90 AND 179 THEN 'Substandard'
            WHEN os.par_day BETWEEN 180 AND 359 THEN 'Doubtful'
            WHEN os.par_day >= 360 THEN 'Loss'
        END AS status,
        IF(os.par_day > 0 AND os.outstanding > 0, os.par_day, 0) AS days_overdue
    FROM loan_os os
),

disbursal_report AS (
    SELECT
        ls.cust_id AS borrower_ID,
        p.national_id AS borrower_NIN,
        ls.acc_number AS agent_identification_number,
        CASE
            WHEN p.mobile_num IS NULL OR p.mobile_num = '' THEN p.mobile_num
            WHEN REPLACE(TRIM(p.mobile_num), ' ', '') LIKE '+%' THEN REPLACE(TRIM(p.mobile_num), ' ', '')
            WHEN REPLACE(TRIM(p.mobile_num), ' ', '') LIKE CONCAT(@isd_code, '%')
                 AND LENGTH(REPLACE(TRIM(p.mobile_num), ' ', '')) > 9 THEN CONCAT('+', REPLACE(TRIM(p.mobile_num), ' ', ''))
            ELSE CONCAT('+', @isd_code, TRIM(LEADING '0' FROM REPLACE(TRIM(p.mobile_num), ' ', '')))
        END AS borrower_phone_number,
        p.full_name AS borrower_name,
        p.gender AS borrower_gender,
        DATE(p.dob) AS borrower_date_of_birth,
        NULL AS borrower_rating,                           
        ai.field_2 AS borrower_location,
        ls.principal_os AS principle_outstanding,          
        ls.loan_doc_id AS loan_ID,
        ls.loan_principal AS loan_amount,
        '1' AS loan_cycle,
        ls.status AS loan_status,
        ls.loan_purpose,
        ls.interest_rate AS loan_interest_rate,
        DATE(ls.disbursal_date) AS loan_issue_date,
        DATE(ls.due_date) AS maturity_date,
        ls.duration AS loan_tenure_in_days
    FROM loan_status ls
    JOIN borrowers b ON b.cust_id = ls.cust_id
    JOIN address_info ai ON ai.id = b.owner_address_id
    JOIN persons p ON p.id = b.owner_person_id
    WHERE ls.disbursal_date BETWEEN @start_date AND @end_date
    ORDER BY ls.disbursal_date
),

arrears_report AS (
    SELECT
        cust_id AS borrower_ID,
        loan_doc_id AS loan_ID,
        status AS loan_status,
        IF(par_day > 1, outstanding, 0) AS amount_in_arrears,
        principal_os AS principal_outstanding,
        outstanding AS outstanding_balance,
        outstanding AS exposure_at_default,
        days_overdue AS days_arrears
    FROM loan_status
    WHERE outstanding > 0
),

repayments_report AS (
    SELECT
        cust_id AS borrower_ID,
        loan_doc_id AS loan_ID,
        paid_principal + paid_fee AS repaid_principal_amount,
        outstanding AS outstanding_amount,
        IF(outstanding <= 0, DATE(paid_date), NULL) AS repaid_date,
        status AS loan_status
    FROM loan_status
    WHERE paid_principal + paid_fee > 0
      AND paid_date BETWEEN @start_date AND @end_date
),

recoveries_report AS (
    SELECT
        cust_id AS borrower_ID,
        loan_doc_id AS loan_ID,
        amount_recoverd AS recovered_amount,
        outstanding AS outstanding_amount,
        IF(outstanding <= 0, DATE(paid_date), NULL) AS recovery_date,
        DATE(DATE_ADD(due_date, INTERVAL 1 DAY)) AS default_date,
        before_overdue_due_amount AS outstanding_balance_at_default_date,
        -- recovered principal / (1 + flat fee / loan amount) ^ ((recovery date - default date) / loan tenor)
        principal_recoverd / POW(1 + flow_fee / NULLIF(loan_principal, 0),
            DATEDIFF(DATE(last_recovery_date), DATE(DATE_ADD(due_date, INTERVAL 1 DAY))) / NULLIF(duration, 0)
        ) AS discounted_value_of_recovered_amount  
    FROM loan_status
    WHERE amount_recoverd > 0
)

SELECT * FROM disbursal_report;
-- SELECT * FROM arrears_report;
-- SELECT * FROM repayments_report;
-- SELECT * FROM recoveries_report;
