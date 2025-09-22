WITH b AS (
    SELECT
        l.cust_id,
        l.loan_doc_id,
        a.acc_number AS receipt_number,
        a.account_id,
        l.cust_name,
        a.ref_account_num AS payment_identifier_1,
        a.ref_alt_acc_num AS payment_identifier_2,
        a.ref_alt_acc_num_2 AS payment_identifier_3,
        a.stmt_txn_date,
        DATE(a.stmt_txn_date) AS txn_date,
        a.descr,
        a.cr_amt as amount,
        a.stmt_txn_id,
        l.status,  -- Loan status included here
        l.flow_rel_mgr_name,
        (LENGTH(l.cust_name) - LENGTH(REPLACE(l.cust_name, ' ', '')) + 1) AS num_words
    FROM loans l
    JOIN loan_txns lt 
        ON l.loan_doc_id = lt.loan_doc_id
        AND lt.txn_type = 'payment'
    JOIN account_stmts a 
        ON a.stmt_txn_id = lt.txn_id
    WHERE l.flow_rel_mgr_id = 2440
      AND l.country_code = 'UGA'
      AND l.status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
),
ja AS (
    SELECT
        b.*,
        CASE 
            WHEN 
                descr LIKE CONCAT('%', SUBSTRING_INDEX(cust_name, ' ', 1), '%')
                OR descr LIKE CONCAT('%', NULLIF(SUBSTRING_INDEX(SUBSTRING_INDEX(cust_name, ' ', 2), ' ', -1), ''), '%')
                OR descr LIKE CONCAT('%', NULLIF(SUBSTRING_INDEX(SUBSTRING_INDEX(cust_name, ' ', 3), ' ', -1), ''), '%')
                OR descr LIKE CONCAT('%', NULLIF(SUBSTRING_INDEX(cust_name, ' ', -1), ''), '%')
            THEN 1 ELSE 0
        END AS name_match,
        CASE 
            WHEN acc1.cust_id = b.cust_id 
              OR acc2.cust_id = b.cust_id 
              OR acc3.cust_id = b.cust_id
            THEN 1 ELSE 0
        END AS account_matches
    FROM b
    LEFT JOIN accounts acc1 
        ON b.cust_id = acc1.cust_id 
        AND b.payment_identifier_1 = acc1.acc_number
    LEFT JOIN accounts acc2 
        ON b.cust_id = acc2.cust_id 
        AND b.payment_identifier_2 = acc2.acc_number
    LEFT JOIN accounts acc3 
        ON b.cust_id = acc3.cust_id 
        AND b.payment_identifier_3 = acc3.acc_number
),
pdc AS (
    SELECT
        ja.*,
        CASE
            WHEN ja.name_match = 0 AND ja.account_matches = 0 THEN 1
            ELSE 0
        END AS paid_by_different_customer,
        r.holder_name AS receipt_name
    FROM ja
    LEFT JOIN accounts r 
        ON r.id = ja.account_id
)
SELECT 
    cust_id AS `Customer ID`,
    loan_doc_id AS `Loan ID`,
    cust_name AS `Customer Name`,
    flow_rel_mgr_name AS `RM Name`,

    -- Remove '256' prefix if it exists in Reference Account
    CASE 
        WHEN COALESCE(payment_identifier_1, payment_identifier_2, payment_identifier_3) LIKE '256%' 
        THEN SUBSTRING(COALESCE(payment_identifier_1, payment_identifier_2, payment_identifier_3), 4)
        ELSE COALESCE(payment_identifier_1, payment_identifier_2, payment_identifier_3)
    END AS `Reference Account`,

    stmt_txn_date AS `Transaction Date`,
    descr AS `Description`,
    amount AS `Amount`,
    stmt_txn_id AS `Transaction ID`,

    status AS `Loan Status`,  -- Loan Status explicitly shown here

    receipt_number AS `Receipt Number`,
    receipt_name AS `Receipt Name`
FROM pdc
WHERE paid_by_different_customer = 1
ORDER BY stmt_txn_date ASC, num_words DESC;