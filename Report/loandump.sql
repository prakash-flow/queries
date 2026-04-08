SET @month = '202512';
SET @country_code = 'UGA';

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
),

last_payment_amount AS (
    SELECT loan_doc_id, amount
    FROM (
        SELECT 
            loan_doc_id,
            amount,
            ROW_NUMBER() OVER (PARTITION BY loan_doc_id ORDER BY txn_date DESC) rn
        FROM loan_txns
        WHERE txn_type='payment'
          AND country_code=@country_code
          AND txn_date <= @last_date_with_time
    ) t
    WHERE rn=1
),

last_visit AS (
    SELECT *
    FROM (
        SELECT 
            cust_id,
            visitor_id,
            visit_end_time,
            type,
            remarks,
            ROW_NUMBER() OVER(PARTITION BY cust_id ORDER BY visit_start_time DESC) rn
        FROM field_visits
        WHERE sch_status='checked_out'
          AND country_code=@country_code
    ) x
    WHERE rn=1
)

SELECT
    p.full_name AS `Customer Name`,
    l.cust_id AS `Customer ID`,
    a.field_2 AS `District`,
    a.field_8 AS `Location`,
    os.loan_doc_id AS `Loan Doc ID`,
    os.loan_purpose AS `Loan Purpose`,
    p.national_id AS `Client National ID`,
    p.mobile_num AS `Client Primary Mobile No`,
    l.disbursal_date AS `Disbursal Date`,
    os.loan_principal AS `Disbursal Amount`,
    os.flow_fee AS `Fees`,
    os.due_date AS `Due Date`,
    os.last_paid_date AS `Last Paid Date`,
    lpa.amount AS `Last Paid Amount`,
    os.principal_os AS `Principal OS`,
    os.fee_os AS `Fee OS`,
    If(os.dpd >1,os.principal_os + os.fee_os,0) AS `Total Overdue Amount`,
    IF(os.dpd<=0,0,os.dpd) AS `Overdue Days`,

    CASE
        WHEN os.dpd = 1 THEN '1 day'
        WHEN os.dpd BETWEEN 2 AND 5 THEN '2-5 days'
        WHEN os.dpd BETWEEN 6 AND 15 THEN '6-15 days'
        WHEN os.dpd BETWEEN 16 AND 30 THEN '16-30 days'
        WHEN os.dpd BETWEEN 31 AND 90 THEN '31-90 days'
        WHEN os.dpd > 90 THEN 'above 90 days'
    END AS `Arrear Bucket`,
    CASE
        WHEN os.dpd > 1 THEN 'overdue'
        WHEN os.dpd  between 0 and 1 Then 'due'
        WHEN os.dpd < 0 THen 'Ongoing'
    end AS `Status`,
    rm.full_name AS `RM Name`,
    rm.id AS `RM ID`,
    IFNULL(tm.full_name,rm.full_name) AS `TM Name`,
    lv.visit_end_time AS `Last RM Visit Date`,
    lv.type AS `Last RM Visit Type`,
    lv.remarks AS `Last RM Visit Remarks`,
    lw.appr_date AS `Write Off Approved`,
    lw.write_off_date AS `Write Off Date`

FROM filtered_loans os
JOIN loans l ON l.loan_doc_id = os.loan_doc_id
JOIN borrowers b ON b.cust_id = l.cust_id
LEFT JOIN loan_write_off lw ON lw.loan_doc_id = os.loan_doc_id
LEFT JOIN address_info a ON b.owner_address_id = a.id
LEFT JOIN persons p ON b.owner_person_id = p.id
LEFT JOIN persons rm ON rm.id = l.flow_rel_mgr_id
LEFT JOIN persons tm ON tm.id = rm.report_to
LEFT JOIN last_payment_amount lpa ON lpa.loan_doc_id = os.loan_doc_id
LEFT JOIN last_visit lv ON lv.cust_id = l.cust_id
WHERE os.principal_os > 0 OR os.fee_os > 0
ORDER BY os.dpd DESC;