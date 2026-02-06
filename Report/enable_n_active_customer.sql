SET @month = 202512;
SET @country_code = 'UGA';
SET @last_day = LAST_DAY(DATE(CONCAT(@month, '01')));

WITH disabled_cust AS (
    SELECT DISTINCT
        r1.record_code AS cust_id
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
            AND country_code = @country_code
        GROUP BY
            record_code
    ) r2 ON r1.id = r2.id
    WHERE
        JSON_EXTRACT(r1.data_after, '$.status') = 'disabled'
),

active_cust AS (
    SELECT DISTINCT
        l.cust_id
    FROM
        loans l
    JOIN
        loan_txns t ON l.loan_doc_id = t.loan_doc_id
    LEFT JOIN
        disabled_cust d ON l.cust_id = d.cust_id
    WHERE
        DATEDIFF(@last_day, t.txn_date) <= 30
        AND DATE(t.txn_date) <= @last_day
        AND l.country_code = @country_code
        AND t.txn_type = 'disbursal'
        AND l.product_id NOT IN (43, 75, 300)
        AND l.status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
        AND d.cust_id IS NULL
),

enabled_cust AS (
    SELECT DISTINCT
        b.cust_id
    FROM
        borrowers b
    LEFT JOIN
        disabled_cust d ON b.cust_id = d.cust_id
    WHERE
        b.reg_date <= @last_day
        AND b.country_code = @country_code
        AND d.cust_id IS NULL
)

SELECT
    CASE
        WHEN YEAR(b.reg_date) = 2025 THEN '2025'
        WHEN YEAR(b.reg_date) = 2024 THEN '2024'
        WHEN YEAR(b.reg_date) = 2023 THEN '2023'
        WHEN YEAR(b.reg_date) = 2022 THEN '2022'
        WHEN YEAR(b.reg_date) = 2021 THEN '2021'
        ELSE 'Before 2021'
    END AS `Acquisition Year`,

    COUNT(DISTINCT a.cust_id) AS `Active Customers`,
    COUNT(DISTINCT e.cust_id) AS `Enabled Customers`

FROM
    borrowers b
LEFT JOIN
    enabled_cust e ON b.cust_id = e.cust_id
LEFT JOIN
    active_cust a ON b.cust_id = a.cust_id

WHERE
    b.reg_date <= @last_day
    AND b.country_code = @country_code

GROUP BY
    `Acquisition Year`
ORDER BY
    FIELD(`Acquisition Year`, '2025', '2024', '2023', '2022', '2021', 'Before 2021');