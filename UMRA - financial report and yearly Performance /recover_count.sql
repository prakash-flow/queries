WITH base AS (
    SELECT
        l.loan_doc_id,
        MAX(
            IF(
                txn_type = 'payment'
                AND (t.principal > 0 OR t.fee > 0 OR t.charges > 0 OR t.penalty > 0),
                t.realization_date,
                NULL
            )
        ) AS realization,
        Max(write_off_date) as write_off_date
    FROM loans l
    JOIN loan_write_off lw
        ON l.loan_doc_id = lw.loan_doc_id
    JOIN loan_txns t
        ON t.loan_doc_id = l.loan_doc_id
    WHERE l.country_code = 'RWA'
      AND lw.country_code = 'RWA'
      -- AND lw.write_off_date < DATE(paid_date)
      AND current_os_amount = 0
      AND lw.write_off_date < '2026-12-31'
      -- AND DATE(paid_date) BETWEEN '2022-12-31' AND '2022-12-31'
    GROUP BY l.loan_doc_id
)
SELECT COUNT(DISTINCT loan_doc_id)
FROM base
WHERE DATE(realization) BETWEEN '2026-01-01' AND '2026-06-30' and write_off_date < DATE(realization);









