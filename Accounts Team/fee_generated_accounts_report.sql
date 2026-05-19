SET @country_code = 'UGA';
SET @month = '202504';

SET @prev_month = (
    SELECT DATE_FORMAT(
        DATE_SUB(STR_TO_DATE(CONCAT(@month, '01'), '%Y%m%d'), INTERVAL 1 MONTH),
        '%Y%m'
    )
);
SET @start_date = DATE(CONCAT(@month, '01'));
SET @last_day = LAST_DAY(@start_date);
SET @realization_date = IFNULL(
    (
        SELECT closure_date
        FROM closure_date_records
        WHERE month = @month 
          AND status = 'enabled' 
          AND country_code = @country_code
    ),
    NOW()
);
SET @pre_realization_date = (
    SELECT closure_date
    FROM closure_date_records
    WHERE month = @prev_month 
      AND status = 'enabled' 
      AND country_code = @country_code
)

SET @loan_purpose = "float_advance,adj_float_advance,terminal_financing";
SET @loan_purpose = "adj_float_advance";

WITH raw AS (
                SELECT
                    t.loan_doc_id as loan_doc_id,
                    t.fee AS fee,
                    CASE
                        WHEN lw.loan_doc_id IS NULL THEN 0
                        WHEN lw.write_off_date IS NULL THEN 0
                        ELSE toDate(t.txn_date) > lw.write_off_date
                    END AS is_recovery
                FROM loans l
                JOIN loan_txns t ON l.loan_doc_id = t.loan_doc_id
                JOIN account_stmts ast ON t.txn_id = ast.stmt_txn_id
                LEFT JOIN loan_write_off lw
                    ON lw.loan_doc_id = l.loan_doc_id
                AND lw.country_code = l.country_code
                WHERE
                    FIND_IN_SET(l.loan_purpose, @loan_purpose)
                    AND t.txn_type = 'payment'
                    AND ast.acc_txn_type = 'payment'
                    AND l.country_code = @country_code
                    AND t.country_code = @country_code
                    AND ast.country_code = @country_code
                    AND (
                        (
                            stmt_txn_date BETWEEN @start_date AND @end_date
                            AND t.realization_date <= @realization_date
                        )
                        OR
                        (
                            stmt_txn_date < @start_date
                            AND t.realization_date > @pre_realization_date
                            AND t.realization_date <= @realization_date
                        )
                    )
            )
            SELECT
                COUNT(DISTINCT IF(is_recovery = 0, loan_doc_id, NULL)) AS recived_total_count,
                SUM(IF(is_recovery = 0, fee, 0)) AS recived_total_fees,
                COUNT(DISTINCT IF(is_recovery = 1 and fee > 0, loan_doc_id, NULL)) AS recoverd_total_count,
                SUM(IF(is_recovery = 1, fee, 0)) AS recoverd_total_fees
            FROM raw