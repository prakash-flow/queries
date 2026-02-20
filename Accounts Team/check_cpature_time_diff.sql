SELECT
    l.loan_purpose,
    DATE(lt.txn_date) AS transaction_date,
    COUNT(*) AS total_txns_count,
    SUM(CASE WHEN diff_days <= 2 THEN 1 ELSE 0 END) AS capture_within_two_days,
    SUM(CASE WHEN diff_days > 2 THEN 1 ELSE 0 END) AS capture_after_two_days,
    lt.created_by
FROM (
    SELECT
        lt.*,
        DATEDIFF(lt.created_at, lt.txn_date) AS diff_days
    FROM loan_txns lt
    WHERE lt.txn_date >= '2025-01-01'
      AND lt.txn_date <  '2025-02-01'
      AND lt.txn_type = 'payment'
) lt
JOIN loans l
    ON l.loan_doc_id = lt.loan_doc_id
JOIN account_stmts a
    ON a.stmt_txn_id = lt.txn_id
   AND a.acc_txn_type = 'payment'
GROUP BY
    lt.created_by,
    l.loan_purpose,
    DATE(lt.txn_date);