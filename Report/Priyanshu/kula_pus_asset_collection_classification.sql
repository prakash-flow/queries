SET @country_code = 'UGA';

  WITH classified AS (
      SELECT
          pai.principal_amount + pai.fee_amount AS amount,
          DATE_FORMAT(ast.stmt_txn_date,'%Y-%m') AS txn_month,
          CASE
              WHEN li.id IS NULL THEN NULL
              WHEN DATE(ast.stmt_txn_date) > DATE(DATE_ADD(li.due_date, INTERVAL 1 DAY)) THEN 'overdue'
              WHEN NOT EXISTS (
                  SELECT 1 FROM loan_installments li2
                  WHERE li2.loan_doc_id = li.loan_doc_id
                    AND li2.due_date < li.due_date
                    AND DATE(ast.stmt_txn_date) <= DATE(DATE_ADD(li2.due_date, INTERVAL 1 DAY))
              ) THEN 'current'
              ELSE 'future'
          END AS bucket
      FROM payment_allocation_items pai
      JOIN account_stmts ast ON ast.id = pai.account_stmt_id
      JOIN loans l ON l.loan_doc_id = pai.loan_doc_id
      LEFT JOIN loan_installments li ON li.id = pai.installment_id
      WHERE pai.is_reversed = 0
        AND l.loan_purpose IN ('growth_financing','asset_financing')
        AND l.country_code = @country_code
  )
  SELECT
      txn_month AS month,
      SUM(amount) AS total_amount,
      SUM(IF(bucket = 'current', amount, 0)) AS on_time,
      SUM(IF(bucket = 'future', amount, 0)) AS future,
      SUM(IF(bucket = 'overdue', amount, 0)) AS overdue
  FROM classified
  GROUP BY txn_month
  ORDER BY txn_month;