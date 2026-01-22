/* ===============================
   Parameters
================================ */
SET @country_code = 'UGA';
SET @month = '202508';

SET @pre_month = DATE_FORMAT(
    DATE_SUB(STR_TO_DATE(CONCAT(@month, '01'), '%Y%m%d'), INTERVAL 1 MONTH),
    '%Y%m'
);

SET @start_date = CONCAT(DATE(CONCAT(@month, '01')),' 00:00:00');
SET @last_day   = CONCAT(LAST_DAY(CONCAT(@month, '01')), ' 23:59:59');

SET @pre_start_date = CONCAT(DATE(CONCAT(@pre_month, '01')),' 00:00:00');
SET @pre_last_day   = CONCAT(LAST_DAY(CONCAT(@pre_month, '01')), ' 23:59:59');

SET @realization_date = IFNULL(
    (
        SELECT closure_date
        FROM closure_date_records
        WHERE month = @month
          AND status = 'enabled'
          AND country_code = @country_code
        LIMIT 1
    ),
    @last_day
);

SET @pre_realization_date = (
    SELECT closure_date
    FROM closure_date_records
    WHERE month = @pre_month
      AND status = 'enabled'
      AND country_code = @country_code
    LIMIT 1
);

/* ===============================
   FINAL QUERY
================================ */
WITH raw AS (

    /* ===============================
       PREVIOUS MONTH RECON
    ================================ */
    SELECT
        l.loan_purpose,
        SUM(ap.fee_amount) AS fee
    FROM account_stmts t
    JOIN payment_allocation_items ap
        ON ap.account_stmt_id = t.id
    JOIN loan_installments li
        ON li.loan_doc_id = ap.loan_doc_id
       AND li.id = ap.installment_id
    JOIN loans l
        ON l.loan_doc_id = ap.loan_doc_id
    WHERE t.acc_txn_type = 'af_payment'
      AND t.country_code = @country_code
      AND t.stmt_txn_date <= @pre_last_day
      AND t.realization_date <= @pre_realization_date
      AND ap.country_code = @country_code
      AND li.due_date BETWEEN @start_date AND @last_day
    GROUP BY l.loan_purpose

    UNION ALL

    /* ===============================
       CURRENT MONTH PAYMENTS
    ================================ */
    SELECT
        l.loan_purpose,
        SUM(ap.fee_amount) AS fee
    FROM account_stmts t
    JOIN payment_allocation_items ap
        ON ap.account_stmt_id = t.id
    JOIN loan_installments li
        ON li.loan_doc_id = ap.loan_doc_id
       AND li.id = ap.installment_id
    JOIN loans l
        ON l.loan_doc_id = ap.loan_doc_id
    WHERE t.acc_txn_type = 'af_payment'
      AND t.country_code = @country_code
      AND t.stmt_txn_date BETWEEN @start_date AND @last_day
      AND t.realization_date <= @realization_date
      AND ap.country_code = @country_code
      AND (
            li.due_date BETWEEN @start_date AND @last_day
         OR li.due_date <= @pre_last_day
      )
    GROUP BY l.loan_purpose
)

/* ===============================
   FINAL SINGLE FEE OUTPUT
================================ */
SELECT
    loan_purpose,
    SUM(fee) AS fee
FROM raw
GROUP BY loan_purpose
ORDER BY loan_purpose;