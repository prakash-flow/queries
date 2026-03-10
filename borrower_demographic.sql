SET @month = "202506";
SET @country_code = 'UGA';

SET @last_day = LAST_DAY(DATE(CONCAT(@month, "01")));

WITH borrower AS (
    SELECT
        COUNT(b.id) AS total_customer,
        SUM(p.gender IN ('female', 'Female')) AS female_count,
        SUM(
            CASE 
                WHEN b.country_code = 'UGA' AND (a.field_2 IS NULL OR a.field_2 != 'kampala') THEN 1
                WHEN b.country_code = 'RWA' AND (a.field_2 IS NULL OR a.field_2 != 'Kigali') THEN 1
                ELSE 0
            END
        ) AS rural_count
    FROM borrowers b
    LEFT JOIN persons p ON p.id = b.owner_person_id
    LEFT JOIN address_info a ON a.id = b.owner_address_id
    WHERE b.reg_date <= @last_day
      AND b.country_code = @country_code
)
SELECT 'Total Borrowers' AS `Borrower Demographics`, total_customer AS `Value` FROM borrower
UNION ALL
SELECT 'Rural Borrower %', ROUND((rural_count / NULLIF(total_customer, 0)) * 100, 2) FROM borrower
UNION ALL
SELECT 'Female Borrower %', ROUND((female_count / NULLIF(total_customer, 0)) * 100, 2) FROM borrower
UNION ALL
SELECT 'Rural Count', rural_count FROM borrower
UNION ALL
SELECT 'Female Count', female_count FROM borrower;