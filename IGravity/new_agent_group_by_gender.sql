SELECT 
    COUNT(DISTINCT b.cust_id) AS total_active_cust, 
    COUNT(DISTINCT IF(p.gender = 'female', b.cust_id, NULL)) AS female,
    COUNT(DISTINCT IF(p.gender = 'male', b.cust_id, NULL)) AS male,
    COUNT(DISTINCT IF(TIMESTAMPDIFF(YEAR, p.dob, '2025-03-31') <= 35, b.cust_id, NULL)) AS youth_count
FROM borrowers b
JOIN persons p ON p.id = b.owner_person_id
WHERE EXTRACT(YEAR_MONTH FROM reg_date) in (202501, 202502, 202503)
  AND b.country_code = 'UGA';