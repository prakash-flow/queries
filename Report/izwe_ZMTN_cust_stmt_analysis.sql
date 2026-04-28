SELECT
  t.run_id AS `Run ID`,
  t.acc_number AS `Account Number`,
  t.txn_type AS `Txn Type`,

  COUNT(*) AS `Txn Count`,

  ROUND(SUM(t.comms), 2) AS `Commission`,

  ROUND(SUM(t.comms) / COUNT(*), 2) AS `Comms Per Txn`,

  d.statement_duration AS `Statment Duration`,

  ROUND(
    SUM(t.cr_amt + t.dr_amt) / NULLIF(COUNT(*), 0), 
    2
  ) AS `Average Amount Txn`,

  ROUND(
    COUNT(*) / NULLIF(d.statement_duration, 0), 
    2
  ) AS `Txn Per Day`,

  ROUND(
    (
      COUNT(*) / NULLIF(d.statement_duration, 0)
    ) *
    (
      SUM(t.cr_amt + t.dr_amt) / NULLIF(COUNT(*), 0)
    ), 2
  ) AS `Float Used Per Day`,

  ROUND(
    SUM(
      CASE 
        WHEN (t.cr_amt + t.dr_amt) != 0 
        THEN (t.comms / (t.cr_amt + t.dr_amt)) * 100 
      END
    ), 2
  ) AS `ROI`,

  ROUND(
    AVG(
      CASE 
        WHEN (t.cr_amt + t.dr_amt) != 0 
        THEN (t.comms / (t.cr_amt + t.dr_amt)) * 100 
      END
    ), 2
  ) AS `Average ROI`

FROM izwe_cust_acc_stmts t

JOIN (
  SELECT 
    run_id,
    acc_number,
    DATEDIFF(MAX(txn_date), MIN(txn_date)) AS statement_duration
  FROM izwe_cust_acc_stmts
  WHERE acc_prvdr_code = 'ZMTN'
  GROUP BY run_id, acc_number
) d 
  ON t.run_id = d.run_id 
 AND t.acc_number = d.acc_number

WHERE t.acc_prvdr_code = 'ZMTN'
  AND LOWER(t.txn_type) IN ('Cash in', 'Cash out', 'Debit', 'External payment')
  AND d.acc_number = '765558117'

GROUP BY t.run_id, t.acc_number, t.txn_type

ORDER BY 
  t.run_id,
  t.acc_number;