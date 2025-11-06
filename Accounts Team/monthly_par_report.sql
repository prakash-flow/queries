SET @month = '202510';
SET @country_code = 'UGA';
-- SET @loan_purpose = 'business'; -- uncomment if filtering by purpose

SET @last_day = LAST_DAY(DATE(CONCAT(@month, "01")));
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
  JOIN loan_txns lt ON lt.loan_doc_id = l.loan_doc_id
  WHERE lt.txn_type = 'disbursal'
    -- AND l.loan_purpose = @loan_purpose        -- optional filter
    AND l.country_code = @country_code
    AND DATE(lt.txn_date) <= @last_day
    AND lt.realization_date <= @realization_date
    AND l.product_id NOT IN (SELECT id FROM loan_products WHERE product_type = 'float_vending')
    AND l.status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
    AND l.loan_doc_id NOT IN (
        SELECT loan_doc_id
        FROM loan_write_off
        WHERE country_code = @country_code
          AND write_off_date <= @last_day
          AND write_off_status IN ('approved', 'partially_recovered', 'recovered')
    )
  GROUP BY l.loan_doc_id, l.loan_purpose, l.due_date, l.loan_principal, l.flow_fee
),

loan_payments AS (
  SELECT 
      loan_doc_id,
      SUM(CASE WHEN txn_type = 'payment' THEN principal ELSE 0 END) AS total_principal_paid,
      SUM(CASE WHEN txn_type = 'payment' THEN fee ELSE 0 END) AS total_fee_paid
  FROM loan_txns
  WHERE DATE(txn_date) <= @last_day
    AND realization_date <= @realization_date
  GROUP BY loan_doc_id
),

filtered_loans AS (
  SELECT 
      lp.loan_doc_id,
      lp.loan_purpose,
      lp.due_date,
      lp.loan_principal,
      lp.flow_fee,
      COALESCE(p.total_principal_paid, 0) AS principal_paid,
      COALESCE(p.total_fee_paid, 0) AS fee_paid
  FROM loan_principal lp
  LEFT JOIN loan_payments p ON p.loan_doc_id = lp.loan_doc_id
)

SELECT 
    loan_purpose,

    -- Counts
    SUM(IF(loan_principal - principal_paid > 0, 1, 0)) AS os_count,

    -- Outstanding values
    SUM(GREATEST(loan_principal - principal_paid, 0)) AS principal_os,
    SUM(GREATEST(flow_fee - fee_paid, 0)) AS fee_os,
    
    SUM(IF(DATEDIFF(@last_day, due_date) > 1,  GREATEST(loan_principal - principal_paid, 0), 0)) AS par_1,
    SUM(IF(DATEDIFF(@last_day, due_date) > 5,  GREATEST(loan_principal - principal_paid, 0), 0)) AS par_5,
    SUM(IF(DATEDIFF(@last_day, due_date) > 10, GREATEST(loan_principal - principal_paid, 0), 0)) AS par_10,
    SUM(IF(DATEDIFF(@last_day, due_date) > 15, GREATEST(loan_principal - principal_paid, 0), 0)) AS par_15,
    SUM(IF(DATEDIFF(@last_day, due_date) > 30, GREATEST(loan_principal - principal_paid, 0), 0)) AS par_30,
    SUM(IF(DATEDIFF(@last_day, due_date) > 60, GREATEST(loan_principal - principal_paid, 0), 0)) AS par_60,
    SUM(IF(DATEDIFF(@last_day, due_date) > 90, GREATEST(loan_principal - principal_paid, 0), 0)) AS par_90,
    SUM(IF(DATEDIFF(@last_day, due_date) > 120, GREATEST(loan_principal - principal_paid, 0), 0)) AS par_120,
    SUM(IF(DATEDIFF(@last_day, due_date) > 180, GREATEST(loan_principal - principal_paid, 0), 0)) AS par_180,
    SUM(IF(DATEDIFF(@last_day, due_date) > 270, GREATEST(loan_principal - principal_paid, 0), 0)) AS par_270,
    SUM(IF(DATEDIFF(@last_day, due_date) > 360, GREATEST(loan_principal - principal_paid, 0), 0)) AS par_360,

  SUM(IF(DATEDIFF(@last_day, due_date) > 1,  GREATEST(flow_fee - fee_paid, 0), 0)) AS par_1_fee,
    SUM(IF(DATEDIFF(@last_day, due_date) > 5,  GREATEST(flow_fee - fee_paid, 0), 0)) AS par_5_fee,
    SUM(IF(DATEDIFF(@last_day, due_date) > 10, GREATEST(flow_fee - fee_paid, 0), 0)) AS par_10_fee,
    SUM(IF(DATEDIFF(@last_day, due_date) > 15, GREATEST(flow_fee - fee_paid, 0), 0)) AS par_15_fee,
    SUM(IF(DATEDIFF(@last_day, due_date) > 30, GREATEST(flow_fee - fee_paid, 0), 0)) AS par_30_fee,
    SUM(IF(DATEDIFF(@last_day, due_date) > 60, GREATEST(flow_fee - fee_paid, 0), 0)) AS par_60_fee,
    SUM(IF(DATEDIFF(@last_day, due_date) > 90, GREATEST(flow_fee - fee_paid, 0), 0)) AS par_90_fee,
    SUM(IF(DATEDIFF(@last_day, due_date) > 120, GREATEST(flow_fee - fee_paid, 0), 0)) AS par_120_fee,
    SUM(IF(DATEDIFF(@last_day, due_date) > 180, GREATEST(flow_fee - fee_paid, 0), 0)) AS par_180_fee,
    SUM(IF(DATEDIFF(@last_day, due_date) > 270, GREATEST(flow_fee - fee_paid, 0), 0)) AS par_270_fee,
    SUM(IF(DATEDIFF(@last_day, due_date) > 360, GREATEST(flow_fee - fee_paid, 0), 0)) AS par_360_fee

FROM filtered_loans
GROUP BY loan_purpose
ORDER BY principal_os DESC;