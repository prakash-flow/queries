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
    WHERE lt.txn_type IN ('af_disbursal')
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
        installment_number,
        principal_due AS installment_principal,
        due_date
    FROM loan_installments
    WHERE loan_doc_id IN (SELECT loan_doc_id FROM loan) AND EXTRACT(YEAR_MONTH FROM due_date) <= @month
),

payment AS (
    SELECT
        p.loan_doc_id,
        p.installment_number,
        SUM(p.principal_amount) AS paid_principal
    FROM payment_allocation_items p
    JOIN account_stmts a
        ON a.id = p.account_stmt_id
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
        GREATEST(
            li.installment_principal - IFNULL(p.paid_principal, 0),
            0
        ) AS os_amount
    FROM loan l
    JOIN loan_installment li
        ON li.loan_doc_id = l.loan_doc_id
    LEFT JOIN payment p
        ON p.loan_doc_id = li.loan_doc_id
       AND p.installment_number = li.installment_number
),

/* ===============================
   Loan-level OS + MIN overdue due_date
================================ */
loan_level_os AS (
    SELECT
        loan_doc_id,
        loan_purpose,

        /* Total outstanding per loan */
        SUM(os_amount) AS loan_os,

        /* Earliest overdue installment due date */
        MIN(CASE
            WHEN os_amount > 0
            THEN due_date
        END) AS min_overdue_due_date
    FROM installment_os
    GROUP BY loan_doc_id, loan_purpose
),

/* ===============================
   Loan-level PAR days
================================ */
loan_level_par AS (
    SELECT
        loan_purpose,
        loan_os,

        CASE
            WHEN loan_os = 0
              OR min_overdue_due_date IS NULL
            THEN 0
            ELSE DATEDIFF(@last_day, min_overdue_due_date)
        END AS par_days
    FROM loan_level_os
)

/* ===============================
   Loan-Purpose PAR Aggregation
================================ */
SELECT
    loan_purpose AS `Loan Purpose`,

    SUM(loan_os) AS `Total Outstanding`,

    SUM(CASE WHEN par_days > 1   THEN loan_os ELSE 0 END) AS `Par 1`,
    SUM(CASE WHEN par_days > 5   THEN loan_os ELSE 0 END) AS `Par 5`,
    SUM(CASE WHEN par_days > 10  THEN loan_os ELSE 0 END) AS `Par 10`,
    SUM(CASE WHEN par_days > 15  THEN loan_os ELSE 0 END) AS `Par 15`,
    SUM(CASE WHEN par_days > 30  THEN loan_os ELSE 0 END) AS `Par 30`,
    SUM(CASE WHEN par_days > 60  THEN loan_os ELSE 0 END) AS `Par 60`,
    SUM(CASE WHEN par_days > 90  THEN loan_os ELSE 0 END) AS `Par 90`,
    SUM(CASE WHEN par_days > 120 THEN loan_os ELSE 0 END) AS `Par 120`,
    SUM(CASE WHEN par_days > 180 THEN loan_os ELSE 0 END) AS `Par 180`,
    SUM(CASE WHEN par_days > 360 THEN loan_os ELSE 0 END) AS `Par 360`

FROM loan_level_par
GROUP BY loan_purpose
ORDER BY loan_purpose;