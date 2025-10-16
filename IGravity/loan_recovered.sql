-- 1️⃣ Set year, quarter, and country
SET @year = 2025;
SET @quarter = 2;  -- 1, 2, 3, 4
SET @country_code = 'UGA';

-- 2️⃣ Compute first and last day of the quarter
SET @first_day = MAKEDATE(@year, 1) + INTERVAL ((@quarter-1)*3) MONTH;
SET @last_day  = LAST_DAY(@first_day + INTERVAL 2 MONTH);

-- 3️⃣ Compute current month and previous quarter's last month
SET @month = DATE_FORMAT(@last_day, '%Y%m');  -- last month of current quarter
SET @prev_month = DATE_FORMAT(@first_day - INTERVAL 1 MONTH, '%Y%m');  -- last month of previous quarter

-- 4️⃣ Get closure dates dynamically
SET @closure_date = (
    SELECT closure_date
    FROM flow_api.closure_date_records
    WHERE status='enabled' 
      AND month = @month 
      AND country_code = @country_code
);

SET @prev_closure_date = (
    SELECT closure_date
    FROM flow_api.closure_date_records
    WHERE status='enabled' 
      AND month = @prev_month 
      AND country_code = @country_code
);

-- 5️⃣ Main query
SELECT
    l.country_code,
    SUM(t.principal) AS `Loans Recovered`
FROM
    loans l
JOIN
    loan_txns t ON l.loan_doc_id = t.loan_doc_id
WHERE
    l.status NOT IN ('voided','hold','pending_disbursal','pending_mnl_dsbrsl')
    AND l.product_id NOT IN (43, 75, 300)
    AND t.txn_type = 'payment'
    AND l.country_code = @country_code
    -- Overdue condition
    AND DATE(t.txn_date) > DATE_ADD(DATE(l.due_date), INTERVAL 1 DAY)
    -- Quarter & closure date condition
    AND (
        (
            DATE(t.txn_date) >= @first_day 
            AND DATE(t.txn_date) <= @last_day
            AND t.realization_date <= @closure_date
        ) OR (
            DATE(t.txn_date) <= @first_day
            AND t.realization_date > @prev_closure_date
            AND t.realization_date <= @closure_date
        )
    )
    AND l.product_id NOT IN (
        SELECT id
        FROM loan_products
        WHERE product_type = 'float_vending'
    )
GROUP BY
    l.country_code;