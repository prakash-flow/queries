SET @month = '202512';
SET @country_code = 'RWA';

SET @last_day = LAST_DAY(STR_TO_DATE(CONCAT(@month,'01'),'%Y%m%d'));
SET @last_date_with_time = CONCAT(@last_day,' 23:59:59');
SET @realization_date = (
    SELECT COALESCE(MAX(closure_date), @last_date_with_time)
    FROM closure_date_records
    WHERE month = @month
      AND status = 'enabled'
      AND country_code = @country_code
);

WITH disbursed_loans AS (
    SELECT DISTINCT loan_doc_id
    FROM loan_txns
    WHERE txn_type = 'disbursal'
      AND txn_date <= @last_date_with_time
      AND realization_date <= @realization_date
),

loan_principal AS (
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
            AND write_off_status IN (
                'approved',
                'partially_recovered',
                'recovered'
            )
      )
  GROUP BY l.loan_doc_id, l.loan_purpose, l.due_date, l.loan_principal, l.flow_fee
),

loan_payments AS (
  SELECT 
      loan_doc_id,
      SUM(CASE WHEN txn_type = 'payment' THEN principal ELSE 0 END) AS total_principal_paid,
      SUM(CASE WHEN txn_type in ('payment','fee_waiver') THEN fee ELSE 0 END) AS total_fee_paid,
      MAX(CASE WHEN txn_type='payment' and (principal > 0 or fee > 0 )   THEN txn_date END) AS last_paid_date
  FROM loan_txns
  WHERE DATE(txn_date) <= @last_day
    AND realization_date <= @realization_date
    AND country_code = @country_code
    AND loan_doc_id NOT IN (
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
  GROUP BY loan_doc_id
),
payments_for_future as (
  select loan_doc_id,
      SUM(CASE WHEN txn_type = 'payment' THEN principal ELSE 0 END) AS total_principal_paid,
      SUM(CASE WHEN txn_type in ('payment') THEN fee ELSE 0 END) AS total_fee_paid,
      MAX(CASE WHEN txn_type='payment' and (principal > 0 or fee > 0 )   THEN txn_date END) AS last_paid_date
  FROM loan_txns
  WHERE
    (realization_date > @realization_date or txn_date > @last_date_with_time)
    AND country_code = @country_code
  GROUP BY loan_doc_id
),

filtered_loans AS (
  SELECT 
      lp.loan_doc_id,
      lp.loan_purpose,
      lp.due_date,
      lp.loan_principal,
      lp.flow_fee,
      last_paid_date as last_paid_date,
      COALESCE(p.total_principal_paid, 0) AS principal_paid,
      COALESCE(p.total_fee_paid, 0) AS fee_paid,
      (lp.loan_principal - ifnull(p.total_principal_paid,0)) AS principal_os ,
      (lp.flow_fee - ifnull(total_fee_paid,0) ) AS fee_os,
      DATEDIFF(@last_day, lp.due_date) AS dpd
  FROM loan_principal lp
  LEFT JOIN loan_payments p ON p.loan_doc_id = lp.loan_doc_id
)
SELECT
    l.acc_prvdr_code as `Account Provider Code`,
    os.loan_doc_id AS `Loan Doc ID`,
    l.cust_name AS `Customer Name`,
    os.loan_purpose AS `Product Name`,
    l.disbursal_date AS `Disbursal Date`,
    os.loan_principal AS `Loan Principal`,
    os.flow_fee AS `Flow Fee`,
    (os.loan_principal + os.flow_fee) AS `Principal & Fee (Total amounts)`,
    os.due_date AS `Due Date`,
    (principal_paid +fee_paid) `Principal Paid & Fee Paid AS Of 2025 Dec`,
    os.principal_os AS `Principal OS AS Of 2025 Dec`,
    os.fee_os AS `Fee OS AS Of 2025 Dec`,
    IF(os.dpd<=0,0,os.dpd) AS `Overdue Days AS Of 2025 Dec`,
    CASE
        WHEN os.dpd = 1 THEN '1 day'
        WHEN os.dpd BETWEEN 2 AND 5 THEN '2-5 days'
        WHEN os.dpd BETWEEN 6 AND 15 THEN '6-15 days'
        WHEN os.dpd BETWEEN 16 AND 30 THEN '16-30 days'
        WHEN os.dpd BETWEEN 31 AND 90 THEN '31-90 days'
        WHEN os.dpd > 90 THEN 'above 90 days'
    END AS `Arrear Bucket AS Of 2025 Dec`,
    ifnull(pf.total_principal_paid,0) as `2026 Paid Principal`,
    ifnull(pf.total_fee_paid,0) as `2026 Paid Fee`,
    pf.last_paid_date as `2026 Last Payment Transaction Date`

FROM filtered_loans os
JOIN loans l ON l.loan_doc_id = os.loan_doc_id
Left JOIN payments_for_future pf ON os.loan_doc_id = pf.loan_doc_id
WHERE os.principal_os > 0 OR os.fee_os > 0
ORDER BY os.dpd DESC;









