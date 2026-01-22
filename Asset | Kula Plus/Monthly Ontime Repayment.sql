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
        principal_due + fee_due AS installment_due,
        due_date
    FROM loan_installments
    WHERE loan_doc_id IN (SELECT loan_doc_id FROM loan)
),

payment AS (
    SELECT
        p.loan_doc_id,
        p.installment_number,
        SUM(p.allocated_amount) AS paid_amount
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