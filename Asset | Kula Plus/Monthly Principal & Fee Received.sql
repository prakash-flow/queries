SET @month = 202511;
SET @country_code = 'UGA';

SET @prev_month = DATE_FORMAT(
    DATE_SUB(DATE(CONCAT(@month,'01')), INTERVAL 1 MONTH),
    '%Y%m'
);

SET @last_day = LAST_DAY(DATE(CONCAT(@month,'01')));

SET @closure_date = (
    SELECT closure_date
    FROM flow_api.closure_date_records
    WHERE status = 'enabled'
      AND month = @month
      AND country_code = @country_code
);

SET @prev_closure_date = (
    SELECT closure_date
    FROM flow_api.closure_date_records
    WHERE status = 'enabled'
      AND month = @prev_month
      AND country_code = @country_code
);

WITH reconed_txns AS (
    SELECT
        stmt_txn_id,
        acc_number
    FROM account_stmts t
    WHERE country_code = @country_code
      AND acc_txn_type = 'af_payment'
      AND (
        (
          EXTRACT(YEAR_MONTH FROM stmt_txn_date) = @month
          AND t.realization_date <= @closure_date
        )
        OR (
          EXTRACT(YEAR_MONTH FROM stmt_txn_date) < @month
          AND t.realization_date > @prev_closure_date
          AND t.realization_date <= @closure_date
        )
      )
),

asset_payment AS (
    SELECT
        rt.acc_number,
        pai.loan_doc_id,
        pai.installment_number,

        SUM(pai.principal_amount) AS principal,
        SUM(pai.fee_amount) AS fee,
        SUM(pai.interest_amount) AS interest,
        SUM(pai.charges_amount) AS charges,
        SUM(pai.excess_amount) AS excess,
        SUM(pai.penalty_amount) AS penalty

    FROM payment_allocation_items pai
    JOIN reconed_txns rt
      ON rt.stmt_txn_id = pai.stmt_txn_id
    WHERE pai.country_code = @country_code
    GROUP BY
        rt.acc_number,
        pai.loan_doc_id,
        pai.installment_number
)

SELECT
    ap.acc_number,
    l.loan_purpose,

    /* CURRENT */
    SUM(CASE WHEN EXTRACT(YEAR_MONTH FROM li.due_date) <= @month THEN ap.principal ELSE 0 END) AS current_principal,
    SUM(CASE WHEN EXTRACT(YEAR_MONTH FROM li.due_date) <= @month THEN ap.fee ELSE 0 END) AS current_fee,
    SUM(CASE WHEN EXTRACT(YEAR_MONTH FROM li.due_date) <= @month THEN ap.interest ELSE 0 END) AS current_interest,
    SUM(CASE WHEN EXTRACT(YEAR_MONTH FROM li.due_date) <= @month THEN ap.charges ELSE 0 END) AS current_charges,
    SUM(CASE WHEN EXTRACT(YEAR_MONTH FROM li.due_date) <= @month THEN ap.excess ELSE 0 END) AS current_excess,
    SUM(CASE WHEN EXTRACT(YEAR_MONTH FROM li.due_date) <= @month THEN ap.penalty ELSE 0 END) AS current_penalty,

    /* FUTURE */
    SUM(CASE WHEN EXTRACT(YEAR_MONTH FROM li.due_date) > @month THEN ap.principal ELSE 0 END) AS future_principal,
    SUM(CASE WHEN EXTRACT(YEAR_MONTH FROM li.due_date) > @month THEN ap.fee ELSE 0 END) AS future_fee,
    SUM(CASE WHEN EXTRACT(YEAR_MONTH FROM li.due_date) > @month THEN ap.interest ELSE 0 END) AS future_interest,
    SUM(CASE WHEN EXTRACT(YEAR_MONTH FROM li.due_date) > @month THEN ap.charges ELSE 0 END) AS future_charges,
    SUM(CASE WHEN EXTRACT(YEAR_MONTH FROM li.due_date) > @month THEN ap.excess ELSE 0 END) AS future_excess,
    SUM(CASE WHEN EXTRACT(YEAR_MONTH FROM li.due_date) > @month THEN ap.penalty ELSE 0 END) AS future_penalty

FROM asset_payment ap
JOIN loan_installments li
  ON li.loan_doc_id = ap.loan_doc_id
 AND li.installment_number = ap.installment_number

JOIN loans l
  ON l.loan_doc_id = ap.loan_doc_id

GROUP BY
    ap.acc_number,
    l.loan_purpose

ORDER BY
    ap.acc_number,
    l.loan_purpose;