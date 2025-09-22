SET @month = 202412;
SET @country_code = 'UGA';

SET @realization_date = (
  SELECT closure_date
  FROM closure_date_records
  WHERE country_code = @country_code
    AND month = @month
    AND status = 'enabled'
);

SELECT 
  a.id,
  a.acc_number,
  a.stmt_txn_date,
  a.stmt_txn_type,
  a.dr_amt,
  a.cr_amt,
  a.realization_date
FROM account_stmts a
WHERE 
  YEAR(a.stmt_txn_date) >= 2023
  AND EXTRACT(YEAR_MONTH FROM a.stmt_txn_date) <= @month
  AND a.country_code = @country_code
  AND (
    a.realization_date > @realization_date
    OR a.realization_date IS NULL
  )
ORDER BY a.stmt_txn_date;