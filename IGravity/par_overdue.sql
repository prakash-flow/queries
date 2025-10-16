-- 1️⃣ Set year, quarter, and country
SET @year = 2025;
SET @quarter = 3;  -- 1, 2, 3, 4
SET @country_code = 'UGA';

-- 2️⃣ Compute first and last day of the quarter
SET @first_day = MAKEDATE(@year, 1) + INTERVAL ((@quarter-1)*3) MONTH;
SET @last_day  = LAST_DAY(@first_day + INTERVAL 2 MONTH);

-- 3️⃣ Compute last month of the quarter for closure_date
SET @month = DATE_FORMAT(@last_day, '%Y%m');

-- 4️⃣ Get closure date dynamically
SET @realization_date = (
    SELECT IFNULL(
        (SELECT closure_date
         FROM closure_date_records
         WHERE month = @month
           AND status = 'enabled'
           AND country_code = @country_code),
        NOW()
    )
);

-- 5️⃣ CTE to calculate overdue amounts
WITH par_cte AS (
    SELECT
        pri.od_days,
        SUM(
            IF(principal - IFNULL(partial_pay, 0) < 0, 0, principal - IFNULL(partial_pay, 0))
        ) AS od_amount
    FROM (
        SELECT
            lt.loan_doc_id,
            SUM(lt.amount) AS principal,
            due_date,
            IF(DATEDIFF(@last_day, due_date) <= 0, 0, DATEDIFF(@last_day, due_date)) AS od_days
        FROM loans l
        JOIN loan_txns lt ON lt.loan_doc_id = l.loan_doc_id
        WHERE lt.txn_type = 'disbursal'
          AND DATE(l.disbursal_date) BETWEEN '2018-12-01' AND @last_day
          AND lt.realization_date <= @realization_date
          AND l.loan_doc_id NOT IN (
              SELECT loan_doc_id
              FROM loan_write_off
              WHERE country_code = @country_code
                AND write_off_date <= @last_day
                AND write_off_status IN ('approved','partially_recovered','recovered')
          )
          AND l.product_id NOT IN (43, 75, 300)
          AND l.status NOT IN ('voided','hold','pending_disbursal','pending_mnl_dsbrsl')
          AND l.country_code = @country_code
        GROUP BY lt.loan_doc_id
    ) AS pri
    LEFT JOIN (
        SELECT
            t.loan_doc_id,
            SUM(t.principal) AS partial_pay
        FROM loans l
        JOIN loan_txns t ON t.loan_doc_id = l.loan_doc_id
        WHERE t.txn_type = 'payment'
          AND DATE(l.disbursal_date) BETWEEN '2018-12-01' AND @last_day
          AND DATE(t.txn_date) BETWEEN '2018-12-01' AND @last_day
          AND t.realization_date <= @realization_date
          AND l.loan_doc_id NOT IN (
              SELECT loan_doc_id
              FROM loan_write_off
              WHERE country_code = @country_code
                AND write_off_date <= @last_day
                AND write_off_status IN ('approved','partially_recovered','recovered')
          )
          AND l.product_id NOT IN (43, 75, 300)
          AND l.status NOT IN ('voided','hold','pending_disbursal','pending_mnl_dsbrsl')
          AND l.country_code = @country_code
        GROUP BY t.loan_doc_id
    ) AS pp ON pri.loan_doc_id = pp.loan_doc_id
    GROUP BY pri.od_days
)

-- 6️⃣ Final overdue buckets
SELECT 'Not Overdue' AS `Days in Arrears Portfolio Outstanding`, SUM(od_amount) AS `Portfolio Outstanding` 
FROM par_cte WHERE od_days <= 0
UNION ALL
SELECT '1 - 30', SUM(od_amount) FROM par_cte WHERE od_days BETWEEN 1 AND 30
UNION ALL
SELECT '31-60', SUM(od_amount) FROM par_cte WHERE od_days BETWEEN 31 AND 60
UNION ALL
SELECT '61-90', SUM(od_amount) FROM par_cte WHERE od_days BETWEEN 61 AND 90
UNION ALL
SELECT '91-120', SUM(od_amount) FROM par_cte WHERE od_days BETWEEN 91 AND 120
UNION ALL
SELECT '121-180', SUM(od_amount) FROM par_cte WHERE od_days BETWEEN 121 AND 180
UNION ALL
SELECT '>180', SUM(od_amount) FROM par_cte WHERE od_days > 180;