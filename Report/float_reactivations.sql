WITH filtered_loans AS (
    SELECT
        l.loan_doc_id,
        l.cust_id
    FROM loans l
    JOIN borrowers b 
        ON b.cust_id = l.cust_id
    WHERE b.country_code <> 'MDG'
      AND l.loan_purpose = 'float_advance'
      AND l.product_id NOT IN (43, 75, 300)
      AND l.status NOT IN (
          'voided',
          'hold',
          'pending_disbursal',
          'pending_mnl_dsbrsl'
      )
),

cust_loans AS (
    SELECT
        b.country_code,
        b.cust_id,
        b.reg_date,
        COUNT(fl.loan_doc_id) AS tot_loans
    FROM borrowers b
    LEFT JOIN filtered_loans fl
        ON fl.cust_id = b.cust_id
    WHERE b.country_code <> 'MDG'
    GROUP BY 
        b.country_code,
        b.cust_id,
        b.reg_date
)

-- 2025 rows
SELECT
    country_code AS country,
    '2025' AS year,
    COUNT(DISTINCT cust_id) AS registered_customers,
    COUNT(DISTINCT CASE WHEN tot_loans = 0 THEN cust_id END) AS `0_FA_customers`,
    COUNT(DISTINCT CASE WHEN tot_loans = 1 THEN cust_id END) AS `1_FA_customers`,
    COUNT(DISTINCT CASE WHEN tot_loans > 1 THEN cust_id END) AS `1+_FA_customers`
FROM cust_loans
WHERE YEAR(reg_date) = 2025
GROUP BY country_code

UNION ALL

-- Overall rows
SELECT
    country_code AS country,
    'Overall' AS year,
    COUNT(DISTINCT cust_id) AS registered_customers,
    COUNT(DISTINCT CASE WHEN tot_loans = 0 THEN cust_id END) AS `0_FA_customers`,
    COUNT(DISTINCT CASE WHEN tot_loans = 1 THEN cust_id END) AS `1_FA_customers`,
    COUNT(DISTINCT CASE WHEN tot_loans > 1 THEN cust_id END) AS `1+_FA_customers`
FROM cust_loans
WHERE YEAR(reg_date) <= 2025
GROUP BY country_code

ORDER BY country, year;