-- =========================
-- VARIABLES
-- =========================
SET @month = 202412;
SET @country_code = 'UGA';

SET @closure_date = (
    SELECT closure_date
    FROM closure_date_records
    WHERE country_code = @country_code
      AND status = 'enabled'
      AND month = @month
);

-- =========================
-- SALES METRICS
-- =========================
WITH
sales_pri AS (
    SELECT
        l.sales_doc_id AS doc_id,
        SUM(lt.amount) AS duplicate
    FROM sales l
    JOIN sales_txns lt ON lt.sales_doc_id = l.sales_doc_id
    WHERE lt.txn_type IN ('duplicate_disbursal','duplicate_payment_reversal')
      AND l.country_code = @country_code
      AND EXTRACT(YEAR_MONTH FROM lt.txn_date) <= @month
      AND lt.realization_date <= @closure_date
    GROUP BY l.sales_doc_id
),
sales_sec AS (
    SELECT
        l.sales_doc_id AS doc_id,
        SUM(lt.amount) AS duplicate_reversal
    FROM sales l
    JOIN sales_txns lt ON lt.sales_doc_id = l.sales_doc_id
    WHERE lt.txn_type IN ('dup_disb_rvrsl','duplicate_payment')
      AND l.country_code = @country_code
      AND EXTRACT(YEAR_MONTH FROM lt.txn_date) <= @month
      AND lt.realization_date <= @closure_date
      AND l.status NOT IN ('voided','hold','pending_disbursal','pending_mnl_dsbrsl')
    GROUP BY l.sales_doc_id
),
sales_metric AS (
    SELECT
        COALESCE(p.doc_id, s.doc_id) AS doc_id,
        IFNULL(p.duplicate,0) AS dup,
        IFNULL(s.duplicate_reversal,0) AS rev,
        GREATEST(IFNULL(p.duplicate,0) - IFNULL(s.duplicate_reversal,0),0) AS unrev
    FROM sales_pri p
    LEFT JOIN sales_sec s ON p.doc_id = s.doc_id
    UNION
    SELECT
        COALESCE(p.doc_id, s.doc_id),
        IFNULL(p.duplicate,0),
        IFNULL(s.duplicate_reversal,0),
        GREATEST(IFNULL(p.duplicate,0) - IFNULL(s.duplicate_reversal,0),0)
    FROM sales_pri p
    RIGHT JOIN sales_sec s ON p.doc_id = s.doc_id
),
sales_result AS (
    SELECT
        LAST_DAY(DATE(CONCAT(@month, '01'))) AS `As of`,
        'SALES' AS `Source`,
        m.doc_id AS `Doc ID`,
        l.cust_id AS `Customer ID`,
        a.acc_prvdr_code `Account Provider Code`,
        CONCAT_WS(' ', p.first_name, p.middle_name, p.last_name) AS `Customer Name`,
        a.acc_number `Account Number`,
        CONCAT_WS(' ', rm.first_name, rm.middle_name, rm.last_name) AS `RM Name`,
        m.dup AS `Duplicate`,
        m.rev AS `Total Reversal`,
        LEAST(m.rev, m.dup) AS `Reversal Againt Duplicate`,
        GREATEST(0, (m.rev - m.dup)) AS `Penalty Collected in Reversal`,
        m.dup - LEAST(m.rev, m.dup) AS `Unreversed`
    FROM sales_metric m
    JOIN sales l ON l.sales_doc_id = m.doc_id
    JOIN borrowers b ON l.cust_id = b.cust_id
    LEFT JOIN accounts a ON a.id = l.from_acc
    LEFT JOIN persons p ON p.id = b.owner_person_id
    LEFT JOIN persons rm ON rm.id = b.flow_rel_mgr_id
)

-- =========================
-- LOAN METRICS
-- =========================
,loan_pri AS (
    SELECT
        l.loan_doc_id AS doc_id,
        SUM(lt.amount) AS duplicate
    FROM loans l
    JOIN loan_txns lt ON lt.loan_doc_id = l.loan_doc_id
    WHERE lt.txn_type IN ('duplicate_disbursal','duplicate_payment_reversal')
      AND l.country_code = @country_code
      AND EXTRACT(YEAR_MONTH FROM lt.txn_date) <= @month
      AND lt.realization_date <= @closure_date
      AND l.product_id NOT IN (
          SELECT id FROM loan_products WHERE product_type = 'float_vending'
      )
      AND l.status NOT IN ('voided','hold','pending_disbursal','pending_mnl_dsbrsl')
    GROUP BY l.loan_doc_id
),
loan_sec AS (
    SELECT
        l.loan_doc_id AS doc_id,
        SUM(lt.amount) AS duplicate_reversal
    FROM loans l
    JOIN loan_txns lt ON lt.loan_doc_id = l.loan_doc_id
    WHERE lt.txn_type IN ('dup_disb_rvrsl','duplicate_payment')
      AND l.country_code = @country_code
      AND EXTRACT(YEAR_MONTH FROM lt.txn_date) <= @month
      AND lt.realization_date <= @closure_date
      AND l.product_id NOT IN (
          SELECT id FROM loan_products WHERE product_type = 'float_vending'
      )
      AND l.status NOT IN ('voided','hold','pending_disbursal','pending_mnl_dsbrsl')
    GROUP BY l.loan_doc_id
),
loan_metric AS (
    SELECT
        COALESCE(p.doc_id, s.doc_id) AS doc_id,
        IFNULL(p.duplicate,0) AS dup,
        IFNULL(s.duplicate_reversal,0) AS rev,
        IFNULL(p.duplicate,0) - IFNULL(s.duplicate_reversal,0) AS unrev
    FROM loan_pri p
    LEFT JOIN loan_sec s ON p.doc_id = s.doc_id
    UNION
    SELECT
        COALESCE(p.doc_id, s.doc_id),
        IFNULL(p.duplicate,0),
        IFNULL(s.duplicate_reversal,0),
        IFNULL(p.duplicate,0) - IFNULL(s.duplicate_reversal,0)
    FROM loan_pri p
    RIGHT JOIN loan_sec s ON p.doc_id = s.doc_id
),
loan_result AS (
    SELECT
        LAST_DAY(DATE(CONCAT(@month, '01'))) AS month,
        'LOAN' AS source,
        m.doc_id AS document_id,
        l.cust_id,
        l.acc_prvdr_code,
        CONCAT_WS(' ', p.first_name, p.middle_name, p.last_name) AS customer_name,
        l.acc_number,
        CONCAT_WS(' ', rm.first_name, rm.middle_name, rm.last_name) AS rm_name,
        m.dup,
        m.rev,
        LEAST(m.rev, m.dup),
        GREATEST(0, (m.rev - m.dup)),
        m.dup - LEAST(m.rev, m.dup) 
    FROM loan_metric m
    JOIN loans l ON l.loan_doc_id = m.doc_id
    JOIN borrowers b ON l.cust_id = b.cust_id
    LEFT JOIN persons p ON p.id = b.owner_person_id
    LEFT JOIN persons rm ON rm.id = l.flow_rel_mgr_id
)

-- =========================
-- FINAL OUTPUT
-- =========================
SELECT * FROM sales_result
UNION ALL
SELECT * FROM loan_result;