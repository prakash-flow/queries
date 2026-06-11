

select p.gender,count(b.id) from borrowers b join persons p on b.owner_person_id = p.id where
date(b.reg_date) >= '2018-12-01' and  date(b.reg_date) < '2025-01-01'
group by gender;



SELECT
    COUNT(CASE WHEN (p.field_1 IN ('kigali') OR p.field_2 IN ('kampala')) THEN 1 END) AS Urban,
    COUNT(CASE WHEN (p.field_1 NOT IN ('kigali') AND p.field_2 NOT IN ('kampala')) THEN 1 END) AS Rural
FROM
    borrowers b
JOIN
    address_info p ON b.owner_address_id = p.id
WHERE
    DATE(b.reg_date) >= '2018-12-01'
    AND DATE(b.reg_date) < '2025-01-01';



SELECT
    COUNT(CASE WHEN (b.biz_addr_prop_type IN ('umberalla_r_apron')) THEN 1 END) AS `Umbrella/apron`,
   	COUNT(CASE WHEN (b.biz_addr_prop_type IN ('kiosk')) THEN 1 END) AS `Kiosk`,
    COUNT(CASE WHEN (b.biz_addr_prop_type IN ('electronics_phones_and_accessories')) THEN 1 END) AS `Electronics, phones, and accessories`,
    COUNT(CASE WHEN (b.biz_addr_prop_type NOT IN ('umberalla_r_apron','electronics_phones_and_accessories','kiosk')) THEN 1 END) AS `Others`
FROM
    borrowers b
WHERE
    DATE(b.reg_date) >= '2018-12-01'
    AND DATE(b.reg_date) < '2025-01-01';
    
    
    
    
    
