WITH product_matrix AS (
    SELECT 0 AS from_val, 49 AS to_val, 0 AS product
    UNION ALL SELECT 50, 59, 2000
    UNION ALL SELECT 60, 69, 2500
    UNION ALL SELECT 70, 84, 3000
    UNION ALL SELECT 85, 94, 3500
    UNION ALL SELECT 95, 109, 4000
    UNION ALL SELECT 110, 119, 4500
    UNION ALL SELECT 120, 179, 5000
    UNION ALL SELECT 180, 239, 7500
    UNION ALL SELECT 240, 299, 10000
    UNION ALL SELECT 300, 359, 12500
    UNION ALL SELECT 360, 999999, 15000
),

t AS (

    SELECT
        l.id,
        l.lead_date,
        l.onboarded_date,
        l.cust_id,
        l.first_name,
        l.last_name,
        l.status,
        l.profile_status,

        p.full_name AS rm_name,

        cla.adjusted_limit,

        cs.id AS cs_id,
        cs.acc_number,
        cs.acc_prvdr_code,
        cs.is_primary_acc,

        SUM(
            CASE
                WHEN jt.csf_type = 'monthly_comms'
                THEN jt.g_val
                ELSE 0
            END
        ) AS monthly_comms,

        SUM(
            CASE
                WHEN jt.csf_type = 'float_used_per_day'
                THEN jt.g_val
                ELSE 0
            END
        ) AS float_used_per_day,

        (
            SUM(
                CASE
                    WHEN jt.csf_type = 'float_used_per_day'
                    THEN jt.g_val
                    ELSE 0
                END
            )
            *
            (
                SUM(
                    CASE
                        WHEN jt.csf_type = 'roi'
                        THEN jt.g_val
                        ELSE 0
                    END
                ) / 100
            )
        ) AS daily_return

    FROM leads l

    LEFT JOIN persons p
        ON l.flow_rel_mgr_id = p.id

    LEFT JOIN customer_limit_adjustments cla
        ON l.cust_id = cla.cust_id
        AND cla.status = 'enabled'

    LEFT JOIN customer_statements cs
        ON cs.entity_id = l.id

    JOIN JSON_TABLE(
        cs.cust_score_factors,
        '$[*]'
        COLUMNS (
            csf_type VARCHAR(100) PATH '$.csf_type',
            g_val DECIMAL(20,2) PATH '$.g_val'
        )
    ) jt

    WHERE
        l.lead_date >= '2026-05-14 00:00:00'
        AND l.status IN (
            '25_ineligible',
            '60_customer_onboarded'
        )
        AND cs.entity = 'lead'
        AND cs.is_removed = 0
        AND l.type = 'kyc'
        AND l.country_code = 'ZMB'

    GROUP BY
        l.id,
        l.lead_date,
        l.onboarded_date,
        l.cust_id,
        l.first_name,
        l.last_name,
        l.status,
        l.profile_status,
        p.full_name,
        cla.adjusted_limit,
        cs.id,
        cs.acc_number,
        cs.acc_prvdr_code,
        cs.is_primary_acc
),

base AS (

    SELECT
        t.id AS `Lead ID`,
        DATE(t.lead_date) AS `Lead Date`,
        DATE(t.onboarded_date) AS `Onboarded Date`,
        t.cust_id AS `Customer ID`,

        UPPER(
            COALESCE(t.first_name, t.last_name)
        ) AS `Customer Name`,

        UPPER(t.rm_name) AS `RM Name`,

        UPPER(
            TRIM(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(
                        t.status,
                        '[^A-Za-z]',
                        ' '
                    ),
                    '[[:space:]]+',
                    ' '
                )
            )
        ) AS `Lead Status`,

        UPPER(t.profile_status) AS `Profile Status`,

        GROUP_CONCAT(
            DISTINCT CONCAT(
                t.acc_prvdr_code,
                ' - ',
                t.acc_number
            )
            SEPARATOR ', '
        ) AS `All Accounts`,

        MAX(
            CASE
                WHEN t.is_primary_acc = 1
                THEN t.acc_number
            END
        ) AS `Primary Account Number`,

        MAX(
            CASE
                WHEN t.is_primary_acc = 1
                THEN t.acc_prvdr_code
            END
        ) AS `Primary Account Provider`,

        MAX(t.adjusted_limit) AS `Adjusted Limit`,

        SUM(t.monthly_comms) AS `Monthly Commission`,

        SUM(t.float_used_per_day) AS `Float Used Per Day`,

        ROUND(SUM(t.daily_return), 2) AS `Daily Returns`,

        ROUND(SUM(t.daily_return), 2) * 6 AS `6 Daily Returns`

    FROM t

    GROUP BY
        t.id,
        t.lead_date,
        t.onboarded_date,
        t.cust_id,
        t.first_name,
        t.last_name,
        t.rm_name,
        t.status,
        t.profile_status
)

SELECT
    b.`Lead ID`,
    b.`Lead Date`,
    b.`Onboarded Date`,
    b.`Customer ID`,
    b.`Customer Name`,
    b.`RM Name`,
    b.`Lead Status`,
    b.`Profile Status`,
    b.`Primary Account Number`,
    b.`Primary Account Provider`,
    b.`Monthly Commission`,
    b.`Float Used Per Day`,
    b.`Daily Returns`,
    b.`6 Daily Returns`,

    ROUND(
        LEAST(
            b.`Float Used Per Day` * 2,
            pm1.product
        )
    ) AS `Actual Limit`,

    COALESCE(
        b.`Adjusted Limit`,
        0
    ) AS `Adjusted Limit`

FROM base b

LEFT JOIN product_matrix pm1
    ON FLOOR(b.`6 Daily Returns` / 5)
       BETWEEN pm1.from_val AND pm1.to_val

LEFT JOIN product_matrix pm2
    ON FLOOR(
            LEAST(
                b.`Float Used Per Day` * 2,
                pm1.product
            )
       )
       BETWEEN pm2.from_val AND pm2.to_val

ORDER BY b.`Lead ID`;