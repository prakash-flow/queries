SET @month = '202503';
SET @country_code = 'UGA';

SET @first_day = DATE(CONCAT(@month, '01'));
SET @last_day = LAST_DAY(@first_day);

WITH recentReassignments AS (
    SELECT cust_id, from_rm_id
    FROM (
        SELECT
            cust_id,
            from_rm_id,
            ROW_NUMBER() OVER (
                PARTITION BY cust_id
                ORDER BY from_date ASC
            ) rn
        FROM rm_cust_assignments rm_cust
        WHERE rm_cust.country_code = @country_code
          AND rm_cust.reason_for_reassign NOT IN ('initial_assignment')
          AND DATE(rm_cust.from_date) > @last_day
    ) t
    WHERE rn = 1
),
customers AS (
    SELECT
        COALESCE(r.from_rm_id, b.flow_rel_mgr_id) AS rm_id,
        b.cust_id
    FROM borrowers b
    LEFT JOIN recentReassignments r 
           ON r.cust_id = b.cust_id
    WHERE EXTRACT(YEAR_MONTH FROM b.reg_date) = @month   
      AND b.country_code = @country_code
)
SELECT @month `Month`, rm_id `RM ID`, COUNT(1) AS `Acquisition`
FROM customers
GROUP BY rm_id;