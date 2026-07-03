SELECT
    CONCAT('256', cc.alt_acc_num) `Agent MSISDN`,
        
    COALESCE(
        MAX(CASE WHEN cc.month = '202605' THEN cc.holder_name END),
        MAX(CASE WHEN cc.month = '202604' THEN cc.holder_name END),
        MAX(CASE WHEN cc.month = '202603' THEN cc.holder_name END)
    ) AS `Agent Name`,

        -- Monthly commissions
        MAX(CASE WHEN cc.month = '202603' THEN cc.commission END) AS `202603`,
        MAX(CASE WHEN cc.month = '202604' THEN cc.commission END) AS `202604`,
        MAX(CASE WHEN cc.month = '202605' THEN cc.commission END) AS `202605`,

        -- Average commission (Oct–Dec 2025)
        CAST(
            (
                MAX(CASE WHEN cc.month = '202603' THEN cc.commission END) +
                MAX(CASE WHEN cc.month = '202604' THEN cc.commission END) +
                MAX(CASE WHEN cc.month = '202605' THEN cc.commission END)
            ) / 3 AS UNSIGNED
        ) AS `Average Commission`,

        -- Assessment Limit
        CASE
            WHEN CAST(
                (
                    MAX(CASE WHEN cc.month = '202603' THEN cc.commission END) +
                    MAX(CASE WHEN cc.month = '202604' THEN cc.commission END) +
                    MAX(CASE WHEN cc.month = '202605' THEN cc.commission END)
                ) / 3 AS UNSIGNED
            ) < 60000 THEN 'Ineligible'

            WHEN CAST(
                (
                    MAX(CASE WHEN cc.month = '202603' THEN cc.commission END) +
                    MAX(CASE WHEN cc.month = '202604' THEN cc.commission END) +
                    MAX(CASE WHEN cc.month = '202605' THEN cc.commission END)
                ) / 3 AS UNSIGNED
            ) BETWEEN 60000 AND 119999 THEN 250000

            WHEN CAST(
                (
                    MAX(CASE WHEN cc.month = '202603' THEN cc.commission END) +
                    MAX(CASE WHEN cc.month = '202604' THEN cc.commission END) +
                    MAX(CASE WHEN cc.month = '202605' THEN cc.commission END)
                ) / 3 AS UNSIGNED
            ) BETWEEN 120000 AND 179999 THEN 500000

            WHEN CAST(
                (
                    MAX(CASE WHEN cc.month = '202603' THEN cc.commission END) +
                    MAX(CASE WHEN cc.month = '202604' THEN cc.commission END) +
                    MAX(CASE WHEN cc.month = '202605' THEN cc.commission END)
                ) / 3 AS UNSIGNED
            ) BETWEEN 180000 AND 249999 THEN 750000

            WHEN CAST(
                (
                    MAX(CASE WHEN cc.month = '202603' THEN cc.commission END) +
                    MAX(CASE WHEN cc.month = '202604' THEN cc.commission END) +
                    MAX(CASE WHEN cc.month = '202605' THEN cc.commission END)
                ) / 3 AS UNSIGNED
            ) BETWEEN 250000 AND 349999 THEN 1000000

            WHEN CAST(
                (
                    MAX(CASE WHEN cc.month = '202603' THEN cc.commission END) +
                    MAX(CASE WHEN cc.month = '202604' THEN cc.commission END) +
                    MAX(CASE WHEN cc.month = '202605' THEN cc.commission END)
                ) / 3 AS UNSIGNED
            ) BETWEEN 350000 AND 499999 THEN 1500000

            WHEN CAST(
                (
                    MAX(CASE WHEN cc.month = '202603' THEN cc.commission END) +
                    MAX(CASE WHEN cc.month = '202604' THEN cc.commission END) +
                    MAX(CASE WHEN cc.month = '202605' THEN cc.commission END)
                ) / 3 AS UNSIGNED
            ) BETWEEN 500000 AND 649999 THEN 2000000

            WHEN CAST(
                (
                    MAX(CASE WHEN cc.month = '202603' THEN cc.commission END) +
                    MAX(CASE WHEN cc.month = '202604' THEN cc.commission END) +
                    MAX(CASE WHEN cc.month = '202605' THEN cc.commission END)
                ) / 3 AS UNSIGNED
            ) BETWEEN 650000 AND 799999 THEN 2500000

            WHEN CAST(
                (
                    MAX(CASE WHEN cc.month = '202603' THEN cc.commission END) +
                    MAX(CASE WHEN cc.month = '202604' THEN cc.commission END) +
                    MAX(CASE WHEN cc.month = '202605' THEN cc.commission END)
                ) / 3 AS UNSIGNED
            ) BETWEEN 800000 AND 999999 THEN 3000000

            WHEN CAST(
                (
                    MAX(CASE WHEN cc.month = '202603' THEN cc.commission END) +
                    MAX(CASE WHEN cc.month = '202604' THEN cc.commission END) +
                    MAX(CASE WHEN cc.month = '202605' THEN cc.commission END)
                ) / 3 AS UNSIGNED
            ) BETWEEN 1000000 AND 1249999 THEN 4000000

            WHEN CAST(
                (
                    MAX(CASE WHEN cc.month = '202603' THEN cc.commission END) +
                    MAX(CASE WHEN cc.month = '202604' THEN cc.commission END) +
                    MAX(CASE WHEN cc.month = '202605' THEN cc.commission END)
                ) / 3 AS UNSIGNED
            ) >= 1250000 THEN 5000000
        END AS `Eligiblity`

    FROM cust_commissions cc
    WHERE cc.month IN ('202603','202604','202605')
    AND cc.country_code = 'UGA'
    GROUP BY cc.alt_acc_num
    HAVING `202603` IS NOT NULL
       AND `202604` IS NOT NULL
       AND `202605` IS NOT NULL;