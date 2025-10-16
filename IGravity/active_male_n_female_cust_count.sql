SELECT 
    COUNT(DISTINCT b.cust_id) AS total_active_cust, 
    COUNT(DISTINCT IF(p.gender = 'male', b.cust_id, NULL)) AS male,
    COUNT(DISTINCT IF(p.gender = 'female', b.cust_id, NULL)) AS female,
    COUNT(DISTINCT IF(TIMESTAMPDIFF(YEAR, p.dob, '2025-09-30') <= 35, b.cust_id, NULL)) AS youth_count
FROM loans l
JOIN loan_txns t ON l.loan_doc_id = t.loan_doc_id
JOIN borrowers b ON b.cust_id = l.cust_id
JOIN persons p ON p.id = b.owner_person_id
WHERE DATEDIFF('2025-09-30', txn_date) <= 30 
  AND DATE(txn_date) <= '2025-09-30' 
  AND EXTRACT(YEAR_MONTH FROM reg_date) <= 202509
  AND b.country_code = 'UGA' 
  AND txn_type = 'disbursal' 
  AND product_id NOT IN (43, 75, 300) 
  AND l.status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl') 
  AND b.cust_id NOT IN (
    SELECT DISTINCT r1.record_code  
    FROM record_audits r1
    JOIN (
      SELECT record_code, MAX(id) AS id 
      FROM record_audits 
      WHERE DATE(created_at) <= '2025-09-30' 
      GROUP BY record_code
    ) r2 ON r1.id = r2.id 
    WHERE JSON_EXTRACT(r1.data_after, '$.status') = 'disabled'
  )
GROUP BY l.country_code;