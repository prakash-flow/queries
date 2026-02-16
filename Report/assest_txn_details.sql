/* ===============================
Base transaction CTE
================================ */
WITH txn AS (
    SELECT
        loan_doc_id,
        descr,
        amount,
        stmt_txn_type,
        stmt_txn_id,
        stmt_txn_date,
        acc_number,
        acc_txn_type
    FROM account_stmts
    WHERE acc_txn_type IN ('af_payment', 'af_disbursal', 'af_sales_commission')
      AND country_code = 'UGA'
),

/* ===============================
Loan enrichment + loan number
================================ */
loan_enriched AS (
    SELECT
        l.cust_id,
        l.loan_doc_id,
        l.biz_name,
        l.loan_principal,
        l.interest_rate,
        l.duration,
        l.cust_name,
        DATE(l.disbursal_date) AS disbursal_date,
        loan_purpose,
        ROW_NUMBER() OVER (
            PARTITION BY l.cust_id
            ORDER BY l.disbursal_date
        ) AS loan_number
    FROM loans l
    WHERE l.country_code = 'UGA'
    AND l.loan_doc_id IN (select loan_doc_id from txn)
)

/* ===============================
FINAL: Transaction-wise output
================================ */
SELECT
    t.stmt_txn_id                       AS `Transaction ID`,
    UPPER(t.stmt_txn_type)              AS `Transaction Type`,
    t.descr                             AS `Description`,
    t.amount                            AS `Transaction Amount`,
    DATE(t.stmt_txn_date)               AS `Transaction Date`,
    CASE 
      WHEN acc_txn_type = 'af_payment' THEN 'Payment'
      WHEN acc_txn_type = 'af_disbursal' THEN 'Disbursal'
      WHEN acc_txn_type = 'af_sales_commission' THEN 'Sales Commission'
      ELSE 'Unknown' END `Account Txn Type`,
    CASE
        WHEN loan_purpose = 'growth_financing' THEN 'Growth Financing'
        ELSE 'Asset Financing'
    END AS `Loan Type`,
    UPPER(TRIM(
        REGEXP_REPLACE(
            REGEXP_REPLACE(le.biz_name, '[^A-Za-z]', ' '),
            '[[:space:]]+',
            ' '
        )
    ))                                   AS `Biz Name`,
    UPPER(le.cust_name)                         AS `Customer Name`,
    t.acc_number                        AS `Account Number`,
    le.cust_id                           AS `Customer ID`,
    t.loan_doc_id                       AS `Loan ID`,
    le.loan_number                      AS `Loan Number`
FROM txn t
JOIN loan_enriched le
    ON le.loan_doc_id = t.loan_doc_id
ORDER BY
    le.cust_id,
    le.loan_number;