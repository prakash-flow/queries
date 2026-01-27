WITH limit_chain AS (
  SELECT
    crl.id AS current_id,
    crl.prev_limit_id AS prev_id,
    next.id AS next_id,
    crl.cust_id,

    prev.current_limit AS prev_limit,
    crl.current_limit AS current_limit,
    next.current_limit AS next_limit,

    crl.status,
    prev.loan_repaid_date AS prev_repaid_date,
    crl.loan_repaid_date AS current_repaid_date,
    next.loan_repaid_date AS next_repaid_date,

    crt_loan.loan_principal AS prev_loan_principal

  FROM customer_repayment_limits crl
  LEFT JOIN customer_repayment_limits prev
    ON crl.prev_limit_id = prev.id
  LEFT JOIN customer_repayment_limits next
    ON next.prev_limit_id = crl.id
  JOIN loans crt_loan
    ON crt_loan.loan_doc_id = crl.loan_doc_id
  WHERE crl.country_code = 'UGA'
    AND crl.is_removed = 0
    AND crl.loan_repaid_date >= '2025-02-17 00:00:00'
    AND crl.prev_limit_id IS NOT NULL
),

loan_stats AS (
  SELECT
    lc.current_id,
    lc.cust_id,
    EXTRACT(YEAR_MONTH FROM MIN(l.disbursal_date)) AS year_month_first_disbursal,
    COUNT(l.loan_doc_id) AS loan_count,
    MAX(l.loan_principal) AS max_loan_amount,
    MIN(l.disbursal_date) AS first_disbursal_date,
    MAX(l.loan_principal) - lc.prev_loan_principal AS loan_book_increased,
    SUM(l.loan_principal - lc.prev_loan_principal) AS loan_book_increased_by_upgrade,

    IFNULL(SUM(CASE WHEN DATEDIFF(IFNULL(l.paid_date, '2025-12-31'), l.due_date) > 10 AND l.loan_principal = 500000 THEN 1 END), 0) AS par_10_count_500K,
    IFNULL(SUM(CASE WHEN DATEDIFF(IFNULL(l.paid_date, '2025-12-31'), l.due_date) > 10 AND l.loan_principal = 500000 THEN l.loan_principal END), 0) AS par_10_value_500k,
    IFNULL(SUM(CASE WHEN DATEDIFF(IFNULL(l.paid_date, '2025-12-31'), l.due_date) > 10 AND l.loan_principal = 750000 THEN 1 END), 0) AS par_10_count_750K,
    IFNULL(SUM(CASE WHEN DATEDIFF(IFNULL(l.paid_date, '2025-12-31'), l.due_date) > 10 AND l.loan_principal = 750000 THEN l.loan_principal END), 0) AS par_10_value_750k,
    IFNULL(SUM(CASE WHEN DATEDIFF(IFNULL(l.paid_date, '2025-12-31'), l.due_date) > 10 AND l.loan_principal = 1000000 THEN 1 END), 0) AS par_10_count_1M,
    IFNULL(SUM(CASE WHEN DATEDIFF(IFNULL(l.paid_date, '2025-12-31'), l.due_date) > 10 AND l.loan_principal = 1000000 THEN l.loan_principal END), 0) AS par_10_value_1M,
    IFNULL(SUM(CASE WHEN DATEDIFF(IFNULL(l.paid_date, '2025-12-31'), l.due_date) > 10 AND l.loan_principal = 1500000 THEN 1 END), 0) AS par_10_count_1_5M,
    IFNULL(SUM(CASE WHEN DATEDIFF(IFNULL(l.paid_date, '2025-12-31'), l.due_date) > 10 AND l.loan_principal = 1500000 THEN l.loan_principal END), 0) AS par_10_value_1_5M,
    IFNULL(SUM(CASE WHEN DATEDIFF(IFNULL(l.paid_date, '2025-12-31'), l.due_date) > 10 AND l.loan_principal = 2000000 THEN 1 END), 0) AS par_10_count_2M,
    IFNULL(SUM(CASE WHEN DATEDIFF(IFNULL(l.paid_date, '2025-12-31'), l.due_date) > 10 AND l.loan_principal = 2000000 THEN l.loan_principal END), 0) AS par_10_value_2M,
    IFNULL(SUM(CASE WHEN DATEDIFF(IFNULL(l.paid_date, '2025-12-31'), l.due_date) > 10 AND l.loan_principal = 2500000 THEN 1 END), 0) AS par_10_count_2_5M,
    IFNULL(SUM(CASE WHEN DATEDIFF(IFNULL(l.paid_date, '2025-12-31'), l.due_date) > 10 AND l.loan_principal = 2500000 THEN l.loan_principal END), 0) AS par_10_value_2_5M,
    IFNULL(SUM(CASE WHEN DATEDIFF(IFNULL(l.paid_date, '2025-12-31'), l.due_date) > 10 AND l.loan_principal = 3000000 THEN 1 END), 0) AS par_10_count_3M,
    IFNULL(SUM(CASE WHEN DATEDIFF(IFNULL(l.paid_date, '2025-12-31'), l.due_date) > 10 AND l.loan_principal = 3000000 THEN l.loan_principal END), 0) AS par_10_value_3M,
    IFNULL(SUM(CASE WHEN DATEDIFF(IFNULL(l.paid_date, '2025-12-31'), l.due_date) > 10 AND l.loan_principal = 4000000 THEN 1 END), 0) AS par_10_count_4M,
    IFNULL(SUM(CASE WHEN DATEDIFF(IFNULL(l.paid_date, '2025-12-31'), l.due_date) > 10 AND l.loan_principal = 4000000 THEN l.loan_principal END), 0) AS par_10_value_4M,
  
  	IFNULL(SUM(CASE WHEN DATEDIFF(IFNULL(l.paid_date, '2025-12-31'), l.due_date) > 10 AND l.paid_date IS NULL AND l.loan_principal = 500000 THEN 1 END), 0) AS crnt_par_10_count_500K,
    IFNULL(SUM(CASE WHEN DATEDIFF(IFNULL(l.paid_date, '2025-12-31'), l.due_date) > 10 AND l.paid_date IS NULL AND l.loan_principal = 500000 THEN l.loan_principal END), 0) AS crnt_par_10_value_500k,
    IFNULL(SUM(CASE WHEN DATEDIFF(IFNULL(l.paid_date, '2025-12-31'), l.due_date) > 10 AND l.paid_date IS NULL AND l.loan_principal = 750000 THEN 1 END), 0) AS crnt_par_10_count_750K,
    IFNULL(SUM(CASE WHEN DATEDIFF(IFNULL(l.paid_date, '2025-12-31'), l.due_date) > 10 AND l.paid_date IS NULL AND l.loan_principal = 750000 THEN l.loan_principal END), 0) AS crnt_par_10_value_750k,
    IFNULL(SUM(CASE WHEN DATEDIFF(IFNULL(l.paid_date, '2025-12-31'), l.due_date) > 10 AND l.paid_date IS NULL AND l.loan_principal = 1000000 THEN 1 END), 0) AS crnt_par_10_count_1M,
    IFNULL(SUM(CASE WHEN DATEDIFF(IFNULL(l.paid_date, '2025-12-31'), l.due_date) > 10 AND l.paid_date IS NULL AND l.loan_principal = 1000000 THEN l.loan_principal END), 0) AS crnt_par_10_value_1M,
    IFNULL(SUM(CASE WHEN DATEDIFF(IFNULL(l.paid_date, '2025-12-31'), l.due_date) > 10 AND l.paid_date IS NULL AND l.loan_principal = 1500000 THEN 1 END), 0) AS crnt_par_10_count_1_5M,
    IFNULL(SUM(CASE WHEN DATEDIFF(IFNULL(l.paid_date, '2025-12-31'), l.due_date) > 10 AND l.paid_date IS NULL AND l.loan_principal = 1500000 THEN l.loan_principal END), 0) AS crnt_par_10_value_1_5M,
    IFNULL(SUM(CASE WHEN DATEDIFF(IFNULL(l.paid_date, '2025-12-31'), l.due_date) > 10 AND l.paid_date IS NULL AND l.loan_principal = 2000000 THEN 1 END), 0) AS crnt_par_10_count_2M,
    IFNULL(SUM(CASE WHEN DATEDIFF(IFNULL(l.paid_date, '2025-12-31'), l.due_date) > 10 AND l.paid_date IS NULL AND l.loan_principal = 2000000 THEN l.loan_principal END), 0) AS crnt_par_10_value_2M,
    IFNULL(SUM(CASE WHEN DATEDIFF(IFNULL(l.paid_date, '2025-12-31'), l.due_date) > 10 AND l.paid_date IS NULL AND l.loan_principal = 2500000 THEN 1 END), 0) AS crnt_par_10_count_2_5M,
    IFNULL(SUM(CASE WHEN DATEDIFF(IFNULL(l.paid_date, '2025-12-31'), l.due_date) > 10 AND l.paid_date IS NULL AND l.loan_principal = 2500000 THEN l.loan_principal END), 0) AS crnt_par_10_value_2_5M,
    IFNULL(SUM(CASE WHEN DATEDIFF(IFNULL(l.paid_date, '2025-12-31'), l.due_date) > 10 AND l.paid_date IS NULL AND l.loan_principal = 3000000 THEN 1 END), 0) AS crnt_par_10_count_3M,
    IFNULL(SUM(CASE WHEN DATEDIFF(IFNULL(l.paid_date, '2025-12-31'), l.due_date) > 10 AND l.paid_date IS NULL AND l.loan_principal = 3000000 THEN l.loan_principal END), 0) AS crnt_par_10_value_3M,
    IFNULL(SUM(CASE WHEN DATEDIFF(IFNULL(l.paid_date, '2025-12-31'), l.due_date) > 10 AND l.paid_date IS NULL AND l.loan_principal = 4000000 THEN 1 END), 0) AS crnt_par_10_count_4M,
    IFNULL(SUM(CASE WHEN DATEDIFF(IFNULL(l.paid_date, '2025-12-31'), l.due_date) > 10 AND l.paid_date IS NULL AND l.loan_principal = 4000000 THEN l.loan_principal END), 0) AS crnt_par_10_value_4M

  FROM limit_chain lc
  JOIN loans l ON l.cust_id = lc.cust_id
  WHERE l.product_id NOT IN (
          SELECT id FROM loan_products WHERE product_type = 'float_vending'
        )
    AND l.status NOT IN (
          'voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl'
        )
    AND l.loan_principal IS NOT NULL
    AND l.disbursal_date >= lc.current_repaid_date
    AND l.disbursal_date < IFNULL(lc.next_repaid_date, '2025-12-31 23:59:59')
    AND l.loan_principal > prev_limit
  GROUP BY lc.current_id, lc.cust_id, lc.prev_loan_principal
)

SELECT
  ls.year_month_first_disbursal,
  lc.cust_id,
  lc.prev_id,
  lc.current_id,
  lc.next_id,

  lc.prev_limit,
  lc.current_limit,
  lc.next_limit,

  lc.prev_repaid_date,
  lc.current_repaid_date,
  lc.next_repaid_date,

  lc.prev_loan_principal,

  ls.loan_count,
  ls.max_loan_amount,
  ls.first_disbursal_date,
  ls.loan_book_increased,
  ls.loan_book_increased_by_upgrade,

  ls.par_10_count_500K,
  ls.par_10_value_500k,
  ls.par_10_count_750K,
  ls.par_10_value_750k,
  ls.par_10_count_1M,
  ls.par_10_value_1M,
  ls.par_10_count_1_5M,
  ls.par_10_value_1_5M,
  ls.par_10_count_2M,
  ls.par_10_value_2M,
  ls.par_10_count_2_5M,
  ls.par_10_value_2_5M,
  ls.par_10_count_3M,
  ls.par_10_value_3M,
  ls.par_10_count_4M,
  ls.par_10_value_4M,
  ls.crnt_par_10_count_500K,
  ls.crnt_par_10_value_500k,
  ls.crnt_par_10_count_750K,
  ls.crnt_par_10_value_750k,
  ls.crnt_par_10_count_1M,
  ls.crnt_par_10_value_1M,
  ls.crnt_par_10_count_1_5M,
  ls.crnt_par_10_value_1_5M,
  ls.crnt_par_10_count_2M,
  ls.crnt_par_10_value_2M,
  ls.crnt_par_10_count_2_5M,
  ls.crnt_par_10_value_2_5M,
  ls.crnt_par_10_count_3M,
  ls.crnt_par_10_value_3M,
  ls.crnt_par_10_count_4M,
  ls.crnt_par_10_value_4M
FROM limit_chain lc
JOIN loan_stats ls ON lc.current_id = ls.current_id AND lc.cust_id = ls.cust_id

ORDER BY year_month_first_disbursal, lc.cust_id;