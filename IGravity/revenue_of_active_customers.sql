SET @month = 202411;
SET @country_code = 'UGA';

SELECT IF(@country_code = 'UGA', 'UGX', 'RWF') INTO @currency;

SET @prev_month = DATE_FORMAT(DATE_SUB(DATE(CONCAT(@month, '01')), INTERVAL 1 MONTH), '%Y%m');
SET @last_day = LAST_DAY(DATE(CONCAT(@month, '01')));

SET @closure_date = (
    SELECT closure_date 
    FROM flow_api.closure_date_records 
    WHERE status = 'enabled' 
      AND month = @month 
      AND country_code = @country_code
);

SET @prev_closure_date = (
    SELECT closure_date 
    FROM flow_api.closure_date_records 
    WHERE status = 'enabled' 
      AND month = @prev_month 
      AND country_code = @country_code
);

SELECT @currency, @month, @prev_month, @last_day, @closure_date, @prev_closure_date;

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
),
revenue AS (
    SELECT
        SUM(
            CASE 
                WHEN w.loan_doc_id IS NULL THEN IFNULL(t.fee, 0) + IFNULL(t.penalty, 0)
                ELSE 0
            END
        ) +
        SUM(
            CASE 
                WHEN w.loan_doc_id IS NOT NULL THEN IFNULL(t.amount, 0)
                ELSE 0
            END
        ) AS revenue
    FROM 
        loans l
    JOIN 
        loan_txns t ON l.loan_doc_id = t.loan_doc_id
    LEFT JOIN 
        loan_write_off w ON l.loan_doc_id = w.loan_doc_id AND DATE(w.write_off_date) <= @last_day
    WHERE 
        l.cust_id IN (SELECT cust_id FROM active_cust)
        AND l.status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
        AND l.product_id NOT IN (43, 75, 300)
        AND t.txn_type = 'payment'
        AND (
            (EXTRACT(YEAR_MONTH FROM t.txn_date) = @month AND t.realization_date <= @closure_date)
            OR 
            (EXTRACT(YEAR_MONTH FROM t.txn_date) < @month AND t.realization_date > @prev_closure_date AND t.realization_date <= @closure_date)
        )
        AND l.country_code = @country_code
),
forex_rate AS (
    SELECT 
        forex_rate 
    FROM 
        forex_rates 
    WHERE 
        base = @currency 
        AND quote = 'USD' 
        AND DATE(forex_date) = @last_day
)

SELECT 
    @month AS month,
    (SELECT COUNT(cust_id) FROM active_cust) AS active_cust_count,
    (SELECT revenue FROM revenue) AS revenue,
    (SELECT forex_rate FROM forex_rate) AS forex_rate,
    (SELECT revenue FROM revenue) * (SELECT forex_rate FROM forex_rate) AS revenue_in_usd;