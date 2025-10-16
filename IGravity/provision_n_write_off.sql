SET @month = '202507';
SET @country_code = 'UGA';

SET @last_day = LAST_DAY(DATE(CONCAT(@month, '01')));
SET @realization_date = (
    SELECT closure_date 
    FROM closure_date_records 
    WHERE country_code = @country_code 
      AND month = @month 
      AND status = 'enabled'
);

WITH loan_payments AS (
    SELECT 
        l.loan_doc_id,
        l.loan_principal,
        l.due_date
    FROM loans l
    WHERE l.status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
      AND l.country_code = @country_code
      AND DATE(l.disbursal_date) <= @last_day
      AND l.product_id NOT IN ('43', '75', '300')
      AND l.loan_doc_id NOT IN (
          SELECT loan_doc_id 
          FROM loan_write_off 
          WHERE write_off_date <= @last_day 
            AND write_off_status IN ('approved', 'partially_recovered', 'recovered')
            AND country_code = @country_code
      )
),
loan_txn_totals AS (
    SELECT 
        loan_doc_id,
        SUM(IF(txn_type = 'payment', principal, 0)) AS total_amount
    FROM loan_txns
    WHERE DATE(txn_date) <= @last_day
      AND realization_date <= @realization_date
    GROUP BY loan_doc_id
),
loan_summary AS (
    SELECT 
        l.loan_doc_id,
        l.loan_principal - IFNULL(t.total_amount, 0) AS outstanding,
        DATEDIFF(@last_day, l.due_date) AS overdue_days
    FROM loan_payments l
    LEFT JOIN loan_txn_totals t ON l.loan_doc_id = t.loan_doc_id
)
SELECT CONCAT(label, ' = UGX ', FORMAT(amount, 0)) AS result
FROM (
    SELECT '1%' AS label, SUM(IF(outstanding > 0, outstanding, 0)) * 0.01 AS amount FROM loan_summary
    UNION ALL
    SELECT '10%' AS label, SUM(IF(overdue_days > 30 AND outstanding > 0, outstanding, 0)) * 0.1 AS amount FROM loan_summary
    UNION ALL
    SELECT '50%' AS label, SUM(IF(overdue_days > 60 AND outstanding > 0, outstanding, 0)) * 0.5 AS amount FROM loan_summary
    UNION ALL
    SELECT '100%' AS label, SUM(IF(overdue_days > 90 AND outstanding > 0, outstanding, 0)) AS amount FROM loan_summary
) t;