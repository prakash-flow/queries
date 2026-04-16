SET @month = '202602';
SET @country_code = 'RWA';

SET @pre_month = (
    SELECT DATE_FORMAT(
        DATE_SUB(STR_TO_DATE(CONCAT(@month, '01'), '%Y%m%d'), INTERVAL 1 MONTH),
        '%Y%m'
    )
);

SET @last_day = LAST_DAY(DATE(CONCAT(@month, '01')));
SET @write_off_date = LAST_DAY(DATE(CONCAT(@pre_month, '01')));

SET @realization_date = (
    SELECT closure_date 
    FROM closure_date_records 
    WHERE country_code = @country_code 
      AND month = @month 
      AND status = 'enabled'
);

WITH loan_principal AS (
    SELECT 
        l.loan_doc_id, 
        l.loan_purpose,
        l.due_date,
        l.loan_principal,
        l.flow_fee
    FROM loans l
    JOIN loan_txns lt 
        ON lt.loan_doc_id = l.loan_doc_id
    WHERE lt.txn_type = 'disbursal'
      AND l.country_code = @country_code
      AND DATE(lt.txn_date) <= @last_day
      AND lt.realization_date <= @realization_date
      AND l.product_id NOT IN (
          SELECT id FROM loan_products WHERE product_type = 'float_vending'
      )
      AND l.status NOT IN (
          'voided','hold','pending_disbursal','pending_mnl_dsbrsl'
      )
      AND l.loan_doc_id NOT IN (
          SELECT loan_doc_id
          FROM loan_write_off
          WHERE country_code = @country_code
            AND write_off_date <= @write_off_date
            AND write_off_status IN ('approved','partially_recovered','recovered')
      )
    GROUP BY l.loan_doc_id
),

loan_payments AS (
    SELECT 
        loan_doc_id,
        SUM(CASE WHEN txn_type = 'payment' THEN principal ELSE 0 END) AS total_principal_paid,
        SUM(CASE WHEN txn_type IN ('payment','fee_waiver') THEN fee ELSE 0 END) AS total_fee_paid
    FROM loan_txns
    WHERE DATE(txn_date) <= @last_day
      AND realization_date <= @realization_date
    GROUP BY loan_doc_id
),

filtered_loans AS (
    SELECT 
        lp.*,
        COALESCE(p.total_principal_paid, 0) AS principal_paid,
        COALESCE(p.total_fee_paid, 0) AS fee_paid
    FROM loan_principal lp
    LEFT JOIN loan_payments p 
        ON p.loan_doc_id = lp.loan_doc_id
),

write_off AS (
    SELECT 
        w.loan_doc_id,
        l.loan_purpose,
        SUM(w.principal) AS write_principal,
        SUM(w.fee) AS write_off_fee
    FROM loan_write_off w
    JOIN loans l 
        ON l.loan_doc_id = w.loan_doc_id
    WHERE l.country_code = @country_code
      AND DATE(w.write_off_date) = @last_day 
    GROUP BY w.loan_doc_id
),

regular_loans AS (
    SELECT 
        @month AS month,
        f.loan_purpose,
        SUM(GREATEST(f.loan_principal - f.principal_paid, 0)) AS principal_os,
        SUM(IF(DATEDIFF(@last_day, f.due_date) > 1,  GREATEST(f.loan_principal - f.principal_paid, 0), 0)) AS par_1,
        SUM(IF(DATEDIFF(@last_day, f.due_date) > 5,  GREATEST(f.loan_principal - f.principal_paid, 0), 0)) AS par_5,
        SUM(IF(DATEDIFF(@last_day, f.due_date) > 10, GREATEST(f.loan_principal - f.principal_paid, 0), 0)) AS par_10,
        SUM(IF(DATEDIFF(@last_day, f.due_date) > 15, GREATEST(f.loan_principal - f.principal_paid, 0), 0)) AS par_15,
        SUM(IF(DATEDIFF(@last_day, f.due_date) > 30, GREATEST(f.loan_principal - f.principal_paid, 0), 0)) AS par_30,
        SUM(IF(DATEDIFF(@last_day, f.due_date) > 60, GREATEST(f.loan_principal - f.principal_paid, 0), 0)) AS par_60,
        SUM(IF(DATEDIFF(@last_day, f.due_date) > 90, GREATEST(f.loan_principal - f.principal_paid, 0), 0)) AS par_90,
        SUM(IF(DATEDIFF(@last_day, f.due_date) > 120, GREATEST(f.loan_principal - f.principal_paid, 0), 0)) AS par_120,
        SUM(IF(DATEDIFF(@last_day, f.due_date) > 180, GREATEST(f.loan_principal - f.principal_paid, 0), 0)) AS par_180,
        SUM(IF(DATEDIFF(@last_day, f.due_date) > 270, GREATEST(f.loan_principal - f.principal_paid, 0), 0)) AS par_270,
        SUM(IF(DATEDIFF(@last_day, f.due_date) > 360, GREATEST(f.loan_principal - f.principal_paid, 0), 0)) AS par_360,

        SUM(COALESCE(w.write_principal,0)) AS write_off_amount

    FROM filtered_loans f
    LEFT JOIN write_off w 
        ON f.loan_doc_id = w.loan_doc_id   -- ✅ FIXED JOIN
    GROUP BY f.loan_purpose
),

-- ---------------- ASSET PART ----------------

loan AS (
    SELECT l.loan_doc_id, l.loan_purpose
    FROM loans l
    JOIN loan_txns lt 
        ON lt.loan_doc_id = l.loan_doc_id
    WHERE lt.txn_type = 'af_disbursal'
      AND l.loan_purpose IN ('growth_financing','asset_financing')
      AND l.country_code = @country_code
      AND DATE(l.disbursal_date) <= @last_day
      AND lt.realization_date <= @realization_date
      AND l.product_id NOT IN (
          SELECT id FROM loan_products WHERE product_type = 'float_vending'
      )
      AND l.status NOT IN (
          'voided','hold','pending_disbursal','pending_mnl_dsbrsl'
      )
),

loan_installment AS (
    SELECT loan_doc_id, installment_number, principal_due, due_date
    FROM loan_installments
),

payment AS (
    SELECT
        p.loan_doc_id,
        p.installment_number,
        SUM(p.principal_amount) AS paid_principal
    FROM payment_allocation_items p
    JOIN account_stmts a ON a.id = p.account_stmt_id
    WHERE EXTRACT(YEAR_MONTH FROM stmt_txn_date) <= @month
      AND p.country_code = @country_code
      AND is_reversed = 0
    GROUP BY p.loan_doc_id, p.installment_number
),

installment_os AS (
    SELECT
        l.loan_doc_id,
        l.loan_purpose,
        li.due_date,
        GREATEST(li.principal_due - IFNULL(p.paid_principal,0),0) AS os_amount
    FROM loan l
    JOIN loan_installment li 
        ON li.loan_doc_id = l.loan_doc_id
    LEFT JOIN payment p 
        ON p.loan_doc_id = li.loan_doc_id
       AND p.installment_number = li.installment_number
),

loan_level_par AS (
    SELECT
        loan_purpose,
        SUM(os_amount) AS loan_os,
        MAX(DATEDIFF(@last_day, due_date)) AS par_days
    FROM installment_os
    GROUP BY loan_purpose
),

asset AS (
    SELECT
        @month AS month,
        loan_purpose,
        loan_os AS principal_os,
        SUM(IF(par_days > 1,  loan_os, 0)) AS par_1,
        SUM(IF(par_days > 5,  loan_os, 0)) AS par_5,
        SUM(IF(par_days > 10, loan_os, 0)) AS par_10,
        SUM(IF(par_days > 15, loan_os, 0)) AS par_15,
        SUM(IF(par_days > 30, loan_os, 0)) AS par_30,
        SUM(IF(par_days > 60, loan_os, 0)) AS par_60,
        SUM(IF(par_days > 90, loan_os, 0)) AS par_90,
        SUM(IF(par_days > 120, loan_os, 0)) AS par_120,
        SUM(IF(par_days > 180, loan_os, 0)) AS par_180,
        SUM(IF(par_days > 270, loan_os, 0)) AS par_270,
        SUM(IF(par_days > 360, loan_os, 0)) AS par_360,
        0 as write_off_amount

    FROM loan_level_par
    GROUP BY loan_purpose
)

-- FINAL RESULT

SELECT * FROM asset
UNION ALL
SELECT * FROM regular_loans;









