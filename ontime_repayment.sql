set @country_code = 'RWA';

SELECT
  loan_purpose,
  ROUND(
    100 * SUM(
      CASE
        WHEN t.max_txn_date <= DATE_ADD(l.due_date, INTERVAL 1 DAY) THEN 1
        ELSE 0
      END
    ) / COUNT(l.loan_doc_id),
    2
  ) AS ontime_repayment_rate,
  SUM(
    CASE
      WHEN t.max_txn_date <= DATE_ADD(l.due_date, INTERVAL 1 DAY) THEN 1
      ELSE 0
    END
  ) AS ontime_settle_count
FROM
  loans l
  JOIN (
    SELECT
      loan_doc_id,
      MAX(txn_date) AS max_txn_date
    FROM
      loan_txns
    WHERE
      txn_type = 'payment'
    GROUP BY
      loan_doc_id
  ) t ON l.loan_doc_id = t.loan_doc_id
WHERE
  l.status = 'settled'
  AND l.paid_date <= '2025-12-31 23:59:59'
  AND l.product_id NOT IN (43, 75, 300)
  AND l.status NOT IN (
    'voided',
    'hold',
    'pending_disbursal',
    'pending_mnl_dsbrsl'	
  )
 AND l.country_code = @country_code
GROUP BY
  l.loan_purpose