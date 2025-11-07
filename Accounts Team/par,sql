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
        l.loan_principal,
        l.flow_fee,
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
        SUM(CASE WHEN txn_type = 'payment' THEN principal ELSE 0 END) AS total_paid_principal,
        SUM(CASE WHEN txn_type = 'payment' THEN fee ELSE 0 END) AS total_paid_fee
    FROM loan_txns
    WHERE DATE(txn_date) <= @last_day
      AND realization_date <= @realization_date
    GROUP BY loan_doc_id
),

loan_os AS (
    SELECT
        lp.loan_doc_id,
        lp.loan_purpose,
        lp.loan_principal,
        lp.flow_fee,
        lp.due_date,
        COALESCE(p.total_paid_principal, 0) AS paid_principal,
        COALESCE(p.total_paid_fee, 0) AS paid_fee,
        GREATEST(lp.loan_principal - COALESCE(p.total_paid_principal, 0), 0) AS os_principal,
        GREATEST(lp.flow_fee - COALESCE(p.total_paid_fee, 0), 0) AS os_fee
    FROM loan_principal lp
    LEFT JOIN loan_payments p ON p.loan_doc_id = lp.loan_doc_id
)

SELECT * FROM (
    -- PRINCIPAL ROWS
    SELECT
        loan_purpose,
        'principal' AS type,
        SUM(CASE WHEN os_principal > 0 THEN 1 ELSE 0 END) AS os_count,
        SUM(os_principal) AS total_os_amount,
        SUM(IF(DATEDIFF(@last_day, due_date) > 1,  os_principal, 0)) AS par_1,
        SUM(IF(DATEDIFF(@last_day, due_date) > 5,  os_principal, 0)) AS par_5,
        SUM(IF(DATEDIFF(@last_day, due_date) > 10, os_principal, 0)) AS par_10,
        SUM(IF(DATEDIFF(@last_day, due_date) > 15, os_principal, 0)) AS par_15,
        SUM(IF(DATEDIFF(@last_day, due_date) > 30, os_principal, 0)) AS par_30,
        SUM(IF(DATEDIFF(@last_day, due_date) > 60, os_principal, 0)) AS par_60,
        SUM(IF(DATEDIFF(@last_day, due_date) > 90, os_principal, 0)) AS par_90,
        SUM(IF(DATEDIFF(@last_day, due_date) > 120,os_principal, 0)) AS par_120,
        SUM(IF(DATEDIFF(@last_day, due_date) > 180,os_principal, 0)) AS par_180,
        SUM(IF(DATEDIFF(@last_day, due_date) > 270,os_principal, 0)) AS par_270,
        SUM(IF(DATEDIFF(@last_day, due_date) > 360,os_principal, 0)) AS par_360
    FROM loan_os
    GROUP BY loan_purpose

    UNION ALL

    -- FEE ROWS
    SELECT
        loan_purpose,
        'fee' AS type,
        SUM(CASE WHEN os_fee > 0 THEN 1 ELSE 0 END) AS os_count,
        SUM(os_fee) AS total_os_amount,
        SUM(IF(DATEDIFF(@last_day, due_date) > 1,  os_fee, 0)) AS par_1,
        SUM(IF(DATEDIFF(@last_day, due_date) > 5,  os_fee, 0)) AS par_5,
        SUM(IF(DATEDIFF(@last_day, due_date) > 10, os_fee, 0)) AS par_10,
        SUM(IF(DATEDIFF(@last_day, due_date) > 15, os_fee, 0)) AS par_15,
        SUM(IF(DATEDIFF(@last_day, due_date) > 30, os_fee, 0)) AS par_30,
        SUM(IF(DATEDIFF(@last_day, due_date) > 60, os_fee, 0)) AS par_60,
        SUM(IF(DATEDIFF(@last_day, due_date) > 90, os_fee, 0)) AS par_90,
        SUM(IF(DATEDIFF(@last_day, due_date) > 120,os_fee, 0)) AS par_120,
        SUM(IF(DATEDIFF(@last_day, due_date) > 180,os_fee, 0)) AS par_180,
        SUM(IF(DATEDIFF(@last_day, due_date) > 270,os_fee, 0)) AS par_270,
        SUM(IF(DATEDIFF(@last_day, due_date) > 360,os_fee, 0)) AS par_360
    FROM loan_os
    GROUP BY loan_purpose
) t
ORDER BY loan_purpose, FIELD(type, 'principal','fee');