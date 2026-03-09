SELECT 
    -- l.loan_purpose,
    COUNT(distinct l.cust_id) AS new_customers
FROM loans l
JOIN (
    SELECT l.loan_purpose,cust_id, MIN(disbursal_date) AS first_loan_date
    FROM loans l
    WHERE country_code = 'RWA' and product_id not in (select id from loan_products where product_type = 'float_vending')
    AND l.status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
    GROUP BY l.loan_purpose,cust_id
) f 
    ON l.cust_id = f.cust_id 
      AND l.loan_purpose = f.loan_purpose
WHERE f.first_loan_date >= '2025-01-01 00:00:00' 
  AND f.first_loan_date <= '2025-12-31 23:59:59' 
  AND country_code = 'RWA'
-- GROUP BY l.loan_purpose
  ;



  select p.gender,
  count(distinct b.cust_id) from borrowers b  join loans l on b.cust_id = l.cust_id join persons p on p.id = b.owner_person_id
    where
    reg_date <= '2025-12-31'
    and 
    disbursal_date <= '2025-12-31 23:59:59' and l.country_code = 'RWA' group by p.gender;