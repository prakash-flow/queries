SET @month = '202510';
SET @country_code = 'UGA';

SET @last_day = LAST_DAY(DATE(CONCAT(@month, "01")));
SET @realization_date = (
    SELECT closure_date 
    FROM closure_date_records 
    WHERE country_code = @country_code 
      AND month = @month 
      AND status = 'enabled'
);

SELECT @month, @country_code, @last_day, @realization_date;

WITH loan_principal AS (
    SELECT 
        l.loan_doc_id,
        l.loan_purpose,
        l.loan_principal AS loan_principal,
        l.flow_fee AS flow_fee,
        l.due_date
    FROM loans l
    JOIN loan_txns lt ON lt.loan_doc_id = l.loan_doc_id
    WHERE lt.txn_type = 'disbursal'
      AND lt.realization_date <= @realization_date
      AND l.country_code = @country_code
      AND DATE(l.disbursal_date) <= @last_day
      AND l.product_id NOT IN (43, 75, 300)
      AND l.status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
      AND l.loan_doc_id NOT IN (
            SELECT loan_doc_id 
            FROM loan_write_off 
            WHERE write_off_date <= @last_day 
              AND write_off_status IN ('approved', 'partially_recovered', 'recovered') 
              AND country_code = @country_code
      )
    GROUP BY l.loan_doc_id, l.loan_purpose
),

loan_payments AS (
    SELECT 
        loan_doc_id,
        SUM(CASE WHEN txn_type = 'payment' THEN principal ELSE 0 END) AS total_principal,
        SUM(CASE WHEN txn_type = 'payment' THEN fee ELSE 0 END) AS total_fee
    FROM loan_txns
    WHERE DATE(txn_date) <= @last_day
      AND realization_date <= @realization_date
    GROUP BY loan_doc_id
),

filtered_loans AS (
    SELECT 
        lp.loan_doc_id,
        lp.loan_purpose,
        lp.loan_principal,
        lp.due_date,
        COALESCE(p.total_amount, 0) AS total_paid
    FROM loan_principal lp
    LEFT JOIN loan_payments p ON p.loan_doc_id = lp.loan_doc_id
)

SELECT 
    loan_purpose,
    SUM(IF(loan_principal - total_paid > 0, 1, 0)) AS os_count,
    SUM(GREATEST(loan_principal - total_paid, 0)) AS total_os,
    SUM(IF(DATEDIFF(@last_day, due_date) > 1,  GREATEST(loan_principal - total_paid, 0), 0)) AS par_1,
    SUM(IF(DATEDIFF(@last_day, due_date) > 5,  GREATEST(loan_principal - total_paid, 0), 0)) AS par_5,
    SUM(IF(DATEDIFF(@last_day, due_date) > 10,  GREATEST(loan_principal - total_paid, 0), 0)) AS par_10,
    SUM(IF(DATEDIFF(@last_day, due_date) > 15,  GREATEST(loan_principal - total_paid, 0), 0)) AS par_15,
    SUM(IF(DATEDIFF(@last_day, due_date) > 30, GREATEST(loan_principal - total_paid, 0), 0)) AS par_30,
    SUM(IF(DATEDIFF(@last_day, due_date) > 60, GREATEST(loan_principal - total_paid, 0), 0)) AS par_60,
    SUM(IF(DATEDIFF(@last_day, due_date) > 90, GREATEST(loan_principal - total_paid, 0), 0)) AS par_90,
    SUM(IF(DATEDIFF(@last_day, due_date) > 120, GREATEST(loan_principal - total_paid, 0), 0)) AS par_120,
    SUM(IF(DATEDIFF(@last_day, due_date) > 180, GREATEST(loan_principal - total_paid, 0), 0)) AS par_180,
    SUM(IF(DATEDIFF(@last_day, due_date) > 270, GREATEST(loan_principal - total_paid, 0), 0)) AS par_270,
    SUM(IF(DATEDIFF(@last_day, due_date) > 360, GREATEST(loan_principal - total_paid, 0), 0)) AS par_360
FROM filtered_loans
GROUP BY loan_purpose
ORDER BY total_os DESC;