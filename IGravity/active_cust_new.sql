WITH active_cust AS (
    SELECT DISTINCT
        l.cust_id
    FROM loans l
    JOIN loan_txns t
        ON l.loan_doc_id = t.loan_doc_id
    LEFT JOIN (
        SELECT DISTINCT
            s1.entity_id
        FROM status_audit_logs s1
        JOIN (
            SELECT
                entity_id,
                MAX(id) AS id
            FROM status_audit_logs
            WHERE DATE(modified_time) <= '2026-07-22'
              AND entity = 'borrower'
            GROUP BY entity_id
        ) s2
            ON s1.id = s2.id
        WHERE s1.current_status = 'disabled'
    ) disabled_cust
        ON l.cust_id = disabled_cust.entity_id
    WHERE DATEDIFF('2026-07-22', t.txn_date) <= 30
      AND DATE(t.txn_date) <= '2026-07-22'
      AND l.country_code = 'RWA'
      AND t.txn_type = 'disbursal'
      AND l.loan_purpose = 'float_advance'
      AND l.product_id NOT IN (43, 75, 300)
      AND l.status NOT IN (
          'voided',
          'hold',
          'pending_disbursal',
          'pending_mnl_dsbrsl'
      )
      AND disabled_cust.entity_id IS NULL
)
SELECT *
FROM active_cust;