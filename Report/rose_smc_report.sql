SET @country_code = 'UGA';
SET @month = '202512';

SET @last_day = (
    SELECT LAST_DAY(DATE(CONCAT(@month, '01')))
);

SET @closure_date = (
    SELECT closure_date
    FROM flow_api.closure_date_records
    WHERE status = 'enabled'
      AND month = @month
      AND country_code = @country_code
);

/* ===============================
Base eligible loans (ENRICHED)
================================ */
WITH loan AS (
    SELECT
        l.cust_id,
        l.loan_doc_id,
        l.loan_purpose,
        l.biz_name,
        l.loan_principal,
        l.flow_fee,
        DATE(l.disbursal_date) AS disbursal_date,
        l.duration,
        l.interest_rate,
        ROW_NUMBER() OVER (
            PARTITION BY l.cust_id
            ORDER BY l.disbursal_date
        ) AS loan_number
    FROM loans l
    JOIN loan_txns lt ON lt.loan_doc_id = l.loan_doc_id
    WHERE lt.txn_type IN ('af_disbursal')
      AND l.loan_purpose IN ('growth_financing', 'asset_financing')
      AND l.country_code = @country_code
      AND DATE(l.disbursal_date) <= @last_day
      AND lt.realization_date <= @closure_date
      AND l.product_id NOT IN(
        SELECT id
        FROM loan_products
        WHERE product_type = 'float_vending'
      )
      AND l.status NOT IN(
        'voided',
        'hold',
        'pending_disbursal',
        'pending_mnl_dsbrsl'
      )
      AND l.loan_doc_id NOT IN(
        SELECT loan_doc_id
        FROM loan_write_off
        WHERE country_code = @country_code
          AND write_off_date <= @last_day
          AND write_off_status IN ('approved', 'partially_recovered', 'recovered')
      )
),

/* ===============================
Loan installments
================================ */
loan_installment AS (
    SELECT
        loan_doc_id,
        installment_number,
        principal_due AS installment_principal,
        due_date
    FROM loan_installments
    WHERE loan_doc_id IN (SELECT loan_doc_id FROM loan)
),

/* ===============================
Payments mapped to installments (Principal + Fee + Excess)
================================ */
payment AS (
    SELECT
        p.loan_doc_id,
        p.installment_number,
        SUM(p.principal_amount) AS paid_principal,
        SUM(p.fee_amount) AS paid_fee,
        SUM(p.excess_amount) AS paid_excess
    FROM payment_allocation_items p
    JOIN account_stmts a ON a.id = p.account_stmt_id
    JOIN loan_installments li ON li.id = p.installment_id
    WHERE EXTRACT(YEAR_MONTH FROM a.stmt_txn_date) <= @month
      AND a.realization_date <= @closure_date
      AND p.country_code = @country_code
      AND a.country_code = @country_code
    GROUP BY p.loan_doc_id, p.installment_number
),

/* ===============================
Installment-level outstanding
================================ */
installment_os AS (
    SELECT
        l.loan_doc_id,
        l.loan_purpose,
        li.due_date,
        GREATEST(
            li.installment_principal - IFNULL(p.paid_principal, 0),
            0
        ) AS os_amount
    FROM loan l
    JOIN loan_installment li ON li.loan_doc_id = l.loan_doc_id
    LEFT JOIN payment p ON p.loan_doc_id = li.loan_doc_id
       AND p.installment_number = li.installment_number
),

/* ===============================
Loan-level OS + earliest overdue
================================ */
loan_level_os AS (
    SELECT
        loan_doc_id,
        loan_purpose,
        SUM(os_amount) AS loan_os,
        MIN(
            CASE
                WHEN os_amount > 0
                 AND DATE(due_date) <= @last_day THEN due_date
            END
        ) AS min_overdue_due_date
    FROM installment_os
    GROUP BY loan_doc_id, loan_purpose
),

/* ===============================
Loan-level PAR days
================================ */
loan_level_par AS (
    SELECT
        l.loan_doc_id,
        l.loan_purpose,
        l.loan_os,
        l.min_overdue_due_date,
        CASE
            WHEN l.loan_os = 0
              OR l.min_overdue_due_date IS NULL THEN 0
            ELSE DATEDIFF(@last_day, l.min_overdue_due_date)
        END AS par_days
    FROM loan_level_os l
),

/* ===============================
Loan-level aggregated payments
================================ */
loan_level_payments AS (
    SELECT
        loan_doc_id,
        SUM(paid_principal) AS total_paid_principal,
        SUM(paid_fee) AS total_paid_fee,
        SUM(paid_excess) AS total_paid_excess
    FROM payment
    GROUP BY loan_doc_id
)

/* ===============================
FINAL: Loan-wise PAR + Payments
================================ */
SELECT
    l.cust_id AS `Customer ID`,
    l.loan_doc_id AS `Loan ID`,
    l.loan_number AS `Loan Number`,
    TRIM(
        REGEXP_REPLACE(
            REGEXP_REPLACE(l.biz_name, '[^A-Za-z]', ' '),
            '[[:space:]]+',
            ' '
        )
    ) AS `Biz Name`,
    l.loan_principal AS `Loan Principal`,
    l.flow_fee AS `Fee`,
    IFNULL(lp.total_paid_principal, 0) AS `Paid Principal`,
    IFNULL(lp.total_paid_fee, 0) AS `Paid Fee`,
    IFNULL(lp.total_paid_excess, 0) AS `Paid Excess`,
    l.disbursal_date AS `Disbursal Date`,
    l.duration AS `Tenor in Month`,
    CONCAT(
        CASE
            WHEN MOD(ROUND(l.interest_rate * 100, 1), 1) = 0 THEN CAST(ROUND(l.interest_rate * 100, 0) AS CHAR)
            ELSE CAST(ROUND(l.interest_rate * 100, 1) AS CHAR)
        END,
        '%'
    ) AS `Interest Rate`,
    CASE
        WHEN l.loan_purpose = 'growth_financing' THEN 'Growth Financing'
        ELSE 'Asset Financing'
    END AS `Loan Type`,
    CASE
        WHEN lp_par.par_days = 0 AND lp_par.loan_os = 0 THEN 'Settled'
        WHEN lp_par.par_days > 0 AND lp_par.loan_os > 0 THEN 'Overdue'
        WHEN lp_par.par_days = 0 AND lp_par.loan_os > 0 THEN 'Ongoing'
    END AS `Loan Status`,
    lp_par.loan_os AS `Outstanding Amount`,
    DATE(lp_par.min_overdue_due_date) AS `Overdue Date`,
    lp_par.par_days AS `PAR Days`
FROM loan l
JOIN loan_level_par lp_par ON l.loan_doc_id = lp_par.loan_doc_id
LEFT JOIN loan_level_payments lp ON l.loan_doc_id = lp.loan_doc_id
ORDER BY `Customer ID`, `Loan Number`;