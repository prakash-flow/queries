SET @country_code = 'UGA';

  WITH loan AS (
      SELECT
          l.loan_doc_id,
          l.loan_purpose,
          l.disbursal_date,
          l.loan_principal
      FROM loans l
      JOIN loan_txns lt
          ON lt.loan_doc_id = l.loan_doc_id
         AND lt.txn_type = 'af_disbursal'
      WHERE l.loan_purpose IN ('growth_financing', 'asset_financing')
        AND l.country_code = @country_code
        AND NOT EXISTS (
              SELECT 1 FROM loan_products lp
              WHERE lp.id = l.product_id AND lp.product_type = 'float_vending'
        )
        AND l.status NOT IN ('voided','hold','pending_disbursal','pending_mnl_dsbrsl')
        AND NOT EXISTS (
              SELECT 1 FROM loan_write_off w
              WHERE w.loan_doc_id = l.loan_doc_id
                AND w.country_code = @country_code
                AND w.write_off_status IN ('approved','partially_recovered','recovered')
        )
      GROUP BY l.loan_doc_id, l.loan_purpose, l.disbursal_date, l.loan_principal
  )
  SELECT
      DATE_FORMAT(disbursal_date, '%Y-%m') AS disbursal_month,
      CASE
          WHEN loan_purpose = 'growth_financing' THEN 'Kula Plus'
          WHEN loan_purpose = 'asset_financing'  THEN 'Kula Asset'
      END AS loan_purpose,
      COUNT(DISTINCT loan_doc_id) AS loans_disbursed,
      SUM(loan_principal)         AS amount_disbursed
  FROM loan
  GROUP BY disbursal_month, loan_purpose
  ORDER BY disbursal_month, loan_purpose;