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
        l.loan_principal,
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
   Installment OS + PAR Days
================================ */
installment_os AS (
    SELECT
        l.loan_purpose,

        GREATEST(
            li.installment_principal - IFNULL(p.paid_principal, 0),
            0
        ) AS os_amount,

        CASE
            WHEN GREATEST(
                li.installment_principal - IFNULL(p.paid_principal, 0),
                0
            ) = 0 THEN 0
            ELSE GREATEST(
                DATEDIFF(@last_day, li.due_date),
                0
            )
        END AS par_days
    FROM loan l
    JOIN loan_installment li
        ON li.loan_doc_id = l.loan_doc_id
    LEFT JOIN payment p
        ON p.loan_doc_id = li.loan_doc_id
       AND p.installment_number = li.installment_number
),

/* ===============================
   Loan-Purpose PAR Aggregation
================================ */
loan_purpose_par AS (
    SELECT
        loan_purpose `Loan Purpose`,

        SUM(os_amount) AS `Total OutStanding`,

        SUM(CASE WHEN par_days > 1   THEN os_amount ELSE 0 END) AS `Par 1`,
        SUM(CASE WHEN par_days > 5   THEN os_amount ELSE 0 END) AS `Par 5`,
        SUM(CASE WHEN par_days > 10  THEN os_amount ELSE 0 END) AS `Par 10`,
        SUM(CASE WHEN par_days > 15  THEN os_amount ELSE 0 END) AS `Par 15`,
        SUM(CASE WHEN par_days > 30  THEN os_amount ELSE 0 END) AS `Par 30`,
        SUM(CASE WHEN par_days > 60  THEN os_amount ELSE 0 END) AS `Par 60`,
        SUM(CASE WHEN par_days > 90  THEN os_amount ELSE 0 END) AS `Par 90`,
        SUM(CASE WHEN par_days > 120 THEN os_amount ELSE 0 END) AS `Par 120`,
        SUM(CASE WHEN par_days > 180 THEN os_amount ELSE 0 END) AS `Par 180`,
        SUM(CASE WHEN par_days > 360 THEN os_amount ELSE 0 END) AS `Par 360`

    FROM installment_os
    WHERE os_amount > 0
    GROUP BY `Loan Purpose`
)

/* ===============================
   FINAL OUTPUT
================================ */
SELECT *
FROM loan_purpose_par
ORDER BY `Loan Purpose`;