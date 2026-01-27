/* ===============================
   Parameters
================================ */
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
   CTEs
================================ */
WITH loan AS (
    SELECT
        l.loan_doc_id,
        l.loan_purpose
    FROM loans l
    JOIN loan_txns lt
        ON lt.loan_doc_id = l.loan_doc_id
    WHERE lt.txn_type IN ('disbursal', 'af_disbursal')
      AND l.loan_purpose IN ('growth_financing', 'asset_financing')
      AND l.country_code = @country_code
      AND DATE(disbursal_date) <= @last_day
      AND realization_date <= @closure_date
      AND product_id NOT IN (
          SELECT id
          FROM loan_products
          WHERE product_type = 'float_vending'
      )
      AND status NOT IN (
          'voided', 'hold',
          'pending_disbursal',
          'pending_mnl_dsbrsl'
      )
      AND l.loan_doc_id NOT IN (
          SELECT loan_doc_id
          FROM loan_write_off
          WHERE country_code = @country_code
            AND write_off_date <= @last_day
            AND write_off_status IN (
                'approved',
                'partially_recovered',
                'recovered'
            )
      )
    GROUP BY l.loan_doc_id
),

loan_installment AS (
    SELECT
        loan_doc_id,
        principal_due,
        due_date,
        installment_number
    FROM loan_installments
    WHERE loan_doc_id IN (SELECT loan_doc_id FROM loan) 
),

payment AS (
    SELECT
        p.loan_doc_id,
        SUM(p.principal_amount) AS paid_principal,
        installment_number
    FROM payment_allocation_items p
    JOIN account_stmts a
        ON a.id = p.account_stmt_id
    JOIN loan_installments li
        ON li.id = p.installment_id AND DATE(li.due_date) <= @last_day
    WHERE EXTRACT(YEAR_MONTH FROM stmt_txn_date) <= @month
      AND realization_date <= @closure_date
      AND p.country_code = @country_code
      AND a.country_code = @country_code
    GROUP BY p.loan_doc_id, p.installment_number
),

/* ===============================
   Installment-level OS
================================ */
installment_os AS (
    SELECT
        l.loan_doc_id,
        l.loan_purpose,
        li.due_date,
        li.principal_due,
        IFNULL(p.paid_principal, 0) AS paid_principal,
        GREATEST(
            li.principal_due - IFNULL(p.paid_principal, 0),
            0
        ) AS os_amount
    FROM loan l
    JOIN loan_installment li
        ON li.loan_doc_id = l.loan_doc_id 
    LEFT JOIN payment p
        ON p.loan_doc_id = li.loan_doc_id
       AND p.installment_number = li.installment_number
  WHERE li.due_date <= @last_day
),

/* ===============================
   Loan-level rollup
================================ */
loan_level AS (
    SELECT
        loan_doc_id,
        loan_purpose,

        SUM(principal_due) AS total_principal_due,
        SUM(paid_principal) AS total_paid_principal,
        SUM(os_amount) AS total_os,

        MIN(CASE
            WHEN os_amount > 0
             AND due_date <= @last_day
            THEN due_date ELSE NULL
        END) AS min_overdue_due_date
    FROM installment_os
    GROUP BY loan_doc_id, loan_purpose
)
    
/* ===============================
   FINAL OUTPUT
================================ */
SELECT
    loan_doc_id,
    loan_purpose,

    total_principal_due,
    total_paid_principal,
    total_os,

    CASE
        WHEN total_os = 0
          OR min_overdue_due_date IS NULL
        THEN 0
        ELSE DATEDIFF(@last_day, min_overdue_due_date)
    END AS par_days

FROM loan_level
ORDER BY par_days DESC, loan_doc_id;