WITH limit_cte AS (
  SELECT 
    acc.cust_id,
    MAX(j.limit_value) AS limit_value
  FROM accounts acc,
  JSON_TABLE(
    acc.conditions,
    '$[*]' COLUMNS (
      type VARCHAR(100) PATH '$.type',
      limit_value DECIMAL(15) PATH '$.limit'
    )
  ) AS j
  WHERE j.type = 'commission_based_limits' AND status = 'enabled' AND country_code = 'RWA'
  GROUP BY acc.cust_id
)

SELECT
  b.cust_id AS `Customer ID`,
  CASE 
    WHEN b.category = 'Referral' THEN 'Referral'
    ELSE 'Full KYC' 
  END AS `Category`,
  b.acc_number AS `Account Number`,
  coalesce(DATE(l.self_reg_date), b.reg_date) AS `Self Reg Date`,
  CASE WHEN l.status = '60_customer_onboarded' THEN DATE(COALESCE(l.onboarded_date, l.audit_kyc_end_date)) END AS `Full KYC Completion Date`, 
  b.crnt_fa_limit AS `Current Limit`,
  lc.limit_value AS `Limit After Full KYC`
FROM borrowers b
JOIN leads l 
  ON b.cust_id = l.cust_id
  AND l.type = 'kyc'
  AND l.is_removed = 0
  AND l.self_reg_status = 'self_reg_completed'
LEFT JOIN limit_cte lc
  ON lc.cust_id = b.cust_id
WHERE
  l.country_code = 'RWA'
  -- AND b.fa_status = 'enabled'
  AND b.status = 'enabled'
  AND b.country_code = 'RWA'; 