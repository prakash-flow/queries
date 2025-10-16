SET @year = 2025;
SET @quarter = 3; -- 1, 2, 3, or 4
SET @country = 'UGA';

-- Calculate start and end month of the quarter
SET @first_day = MAKEDATE(@year, 1) + INTERVAL ((@quarter-1)*3) MONTH;
SET @last_day  = LAST_DAY(@first_day + INTERVAL 2 MONTH);

WITH borrower_cte AS (
    SELECT 
        b.cust_id,
        p.gender,
        TIMESTAMPDIFF(YEAR, p.dob, @last_day) AS age
    FROM borrowers b
    JOIN persons p ON p.id = b.owner_person_id
    WHERE b.reg_date BETWEEN @first_day AND @last_day
      AND YEAR(b.reg_date) = @year
      AND b.country_code = @country
)
SELECT 'Total' AS metric, COUNT(DISTINCT cust_id) AS count FROM borrower_cte
UNION ALL
SELECT 'Female', COUNT(DISTINCT cust_id) FROM borrower_cte WHERE gender = 'female'
UNION ALL
SELECT 'Male', COUNT(DISTINCT cust_id) FROM borrower_cte WHERE gender = 'male'
UNION ALL
SELECT 'Youth', COUNT(DISTINCT cust_id) FROM borrower_cte WHERE age <= 35;