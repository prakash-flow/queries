SET @country_code = 'RWA';
SET @month = '202512';
SET @last_day = (SELECT LAST_DAY(DATE(CONCAT(@month, '01'))));
SET @closure_date = (
    SELECT closure_date
    FROM flow_api.closure_date_records
    WHERE status = 'enabled'
      AND month = @month
      AND country_code = @country_code
);

WITH loan AS (
    SELECT 
        l.loan_doc_id,
        l.loan_purpose,
        loan_principal AS disbursed_amount
    FROM loans l
    JOIN loan_txns lt
        ON lt.loan_doc_id = l.loan_doc_id
       AND lt.txn_type IN ('disbursal', 'af_disbursal')
    WHERE l.loan_purpose IN ('growth_financing', 'asset_financing')
      AND l.country_code = @country_code
      AND DATE(l.disbursal_date) <= @last_day
      AND lt.realization_date <= @closure_date
      AND l.status NOT IN (
            'voided', 'hold',
            'pending_disbursal', 'pending_mnl_dsbrsl'
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
    GROUP BY l.loan_doc_id, loan_principal
),

loan_installment AS (
    SELECT
        loan_doc_id,
        SUM(principal_due) AS total_principal_receivable
    FROM loan_installments
    WHERE loan_doc_id IN (SELECT loan_doc_id FROM loan)
      AND EXTRACT(YEAR_MONTH FROM due_date) <= @month
    GROUP BY loan_doc_id
),

payment AS (
    SELECT
        p.loan_doc_id,
        SUM(p.principal_amount) AS principal_paid
    FROM payment_allocation_items p
    JOIN account_stmts a
        ON a.id = p.account_stmt_id
       AND EXTRACT(YEAR_MONTH FROM a.stmt_txn_date) <= @month
       AND a.realization_date <= @closure_date
       AND p.country_code = @country_code
       AND a.country_code = @country_code
    GROUP BY p.loan_doc_id
),

loan_summary AS (
    SELECT
        l.loan_doc_id,
        l.loan_purpose,
        l.disbursed_amount,
        IFNULL(li.total_principal_receivable, 0) AS total_principal_receivable,
        IFNULL(p.principal_paid, 0) AS principal_paid,

        /* Outstanding based on disbursal */
        GREATEST(
            l.disbursed_amount - IFNULL(p.principal_paid, 0),
            0
        ) AS outstanding_disbursal,

        /* Outstanding based on receivable */
        GREATEST(
            IFNULL(li.total_principal_receivable, 0) - IFNULL(p.principal_paid, 0),
            0
        ) AS outstanding_receivable

    FROM loan l
    LEFT JOIN loan_installment li
        ON l.loan_doc_id = li.loan_doc_id
    LEFT JOIN payment p
        ON l.loan_doc_id = p.loan_doc_id
)

SELECT
    loan_purpose                                             AS `Loan Purpose`,
    SUM(disbursed_amount)                                    AS `Total Disbursed Amount`,
    ROUND(SUM(total_principal_receivable))                   AS `Total Principal Receivable`,
    ROUND(SUM(principal_paid))                               AS `Total Principal Received`,
    SUM(outstanding_disbursal)                               AS `Outstanding (Disbursal Based)`,
    ROUND(SUM(outstanding_receivable))                       AS `Outstanding (Receivable Based)`,
    SUM(outstanding_disbursal) - SUM(outstanding_receivable) AS `Outstanding (Unallocated)`
FROM loan_summary
GROUP BY loan_purpose;