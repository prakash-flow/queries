WITH bands AS (
  SELECT
    quantileExact(0.05)(loan_principal) AS p5,
    quantileExact(0.25)(loan_principal) AS p25,
    quantileExact(0.50)(loan_principal) AS p50,
    quantileExact(0.75)(loan_principal) AS p75,
    quantileExact(0.95)(loan_principal) AS p95
  FROM loans
  WHERE loan_purpose = 'float_advance'
    AND country_code = 'UGA'
    AND status NOT IN ('voided','hold','pending_disbursal','pending_mnl_dsbrsl')
    AND product_id NOT IN (43, 75, 300)
    AND disbursal_date BETWEEN '2024-08-01 00:00:00' AND '2026-08-31 23:59:59'
),
band_values AS (
  SELECT p5  AS band_amount, 'p5'  AS band_label FROM bands
  UNION ALL SELECT p25, 'p25' FROM bands
  UNION ALL SELECT p50, 'p50' FROM bands
  UNION ALL SELECT p75, 'p75' FROM bands
  UNION ALL SELECT p95, 'p95' FROM bands
),
customer_band_counts AS (
  SELECT
    l.cust_id,
    b.band_amount,
    b.band_label,
    count(*) AS loan_count
  FROM loans l
  INNER JOIN band_values b ON l.loan_principal = b.band_amount
  WHERE l.loan_purpose = 'float_advance'
    AND l.country_code = 'UGA'
    AND l.status NOT IN ('voided','hold','pending_disbursal','pending_mnl_dsbrsl')
    AND l.product_id NOT IN (43, 75, 300)
    AND l.disbursal_date BETWEEN '2024-08-01 00:00:00' AND '2026-08-31 23:59:59'
  GROUP BY l.cust_id, b.band_amount, b.band_label
  HAVING loan_count >= 10
),
customer_best_band AS (
  SELECT
    cust_id,
    max(band_amount) AS assigned_band_amount
  FROM customer_band_counts
  GROUP BY cust_id
)
SELECT cust_id, assigned_band_amount AS band_amount
FROM customer_best_band
ORDER BY band_amount DESC, cust_id