-- 1️⃣ Set year and quarter
SET @year = 2025;
SET @quarter = 3;  -- 1, 2, 3, or 4
SET @country_code = 'UGA';

-- 2️⃣ Compute first and last day of the quarter
SET @first_day = MAKEDATE(@year, 1) + INTERVAL ((@quarter-1)*3) MONTH;
SET @last_day  = LAST_DAY(@first_day + INTERVAL 2 MONTH);

-- 3️⃣ Compute current month and previous quarter's last month
SET @month = DATE_FORMAT(@last_day, '%Y%m');  -- current quarter end month
SET @prev_quarter_last_month = DATE_FORMAT(@first_day - INTERVAL 1 MONTH, '%Y%m');  -- previous quarter end month

-- 4️⃣ Get closure dates
SET @closure_date = (SELECT closure_date FROM flow_api.closure_date_records WHERE status='enabled' AND month = @month AND country_code=@country_code);
SET @prev_closure_date = (SELECT closure_date FROM flow_api.closure_date_records WHERE status='enabled' AND month = @prev_quarter_last_month AND country_code=@country_code);

-- 5️⃣ Get forex rate for UGX to USD conversion
SET @forex_rate = (SELECT forex_rate FROM forex_rates WHERE base = 'UGX' AND quote = 'USD' AND DATE(forex_date) = @last_day);

-- 6️⃣ Active customers (30-day activity within the quarter)
WITH active_cust AS (
    SELECT DISTINCT
        l.cust_id AS cust_id
    FROM
        loans l
    JOIN
        loan_txns t ON l.loan_doc_id = t.loan_doc_id
    LEFT JOIN (
        SELECT DISTINCT
            r1.record_code
        FROM
            record_audits r1
        JOIN (
            SELECT
                record_code,
                MAX(id) AS id
            FROM
                record_audits
            WHERE
                DATE(created_at) <= @last_day
            GROUP BY
                record_code
        ) r2 ON r1.id = r2.id
        WHERE
            JSON_EXTRACT(r1.data_after, '$.status') = 'disabled'
    ) disabled_cust ON l.cust_id = disabled_cust.record_code
    WHERE
        DATEDIFF(@last_day, t.txn_date) <= 30
        AND DATE(t.txn_date) <= @last_day
        AND l.country_code = @country_code
        AND t.txn_type = 'disbursal'
        AND l.product_id NOT IN (43, 75, 300)
        AND l.status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
        AND disabled_cust.record_code IS NULL
)
-- 7️⃣ Main query for the specific quarter with forex conversion
SELECT
    CONCAT('Q', @quarter, ' ', @year) as 'Quarter',
    SUM(t.amount) as 'Loan Disbursed to Active Customers (UGX)',
    @forex_rate as 'Forex Rate (UGX/USD)',
    CASE 
        WHEN @forex_rate IS NOT NULL AND @forex_rate > 0 
        THEN SUM(t.amount) * @forex_rate 
        ELSE NULL 
    END as 'Loan Disbursed to Active Customers (USD)'
FROM
    loans l
JOIN
    loan_txns t ON l.loan_doc_id = t.loan_doc_id
WHERE
    l.loan_doc_id = t.loan_doc_id
    AND l.status NOT IN (
        'voided',
        'hold',
        'pending_disbursal',
        'pending_mnl_dsbrsl'
    )
    AND l.product_id NOT IN (43, 75, 300)
    AND t.txn_type = 'disbursal'
    AND l.country_code = @country_code
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
        SELECT
            id
        FROM
            loan_products
        WHERE
            product_type = 'float_vending'
    )
    AND l.cust_id IN (SELECT cust_id FROM active_cust)
GROUP BY
    l.country_code;