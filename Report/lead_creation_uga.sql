WITH
commission_data AS (
    SELECT
        cc.alt_acc_num,

        -- Monthly commissions
        MAX(CASE WHEN cc.month = '202512' THEN cc.commission END) AS `202512`,
        MAX(CASE WHEN cc.month = '202601' THEN cc.commission END) AS `202601`,
        MAX(CASE WHEN cc.month = '202602' THEN cc.commission END) AS `202602`,

        -- Account status
        CASE
            WHEN a.alt_acc_num IS NOT NULL THEN 'account_exists'
            WHEN cc.alt_acc_num IS NOT NULL THEN 'lead_exists'
            ELSE 'new_lead'
        END AS account_status,

        -- Average commission (Oct–Dec 2025)
        CAST(
            (
                MAX(CASE WHEN cc.month = '202512' THEN cc.commission END) +
                MAX(CASE WHEN cc.month = '202601' THEN cc.commission END) +
                MAX(CASE WHEN cc.month = '202602' THEN cc.commission END)
            ) / 3 AS UNSIGNED
        ) AS avg_commission,

        -- Can Create
        CASE
            WHEN CAST(
                (
                    MAX(CASE WHEN cc.month = '202512' THEN cc.commission END) +
                    MAX(CASE WHEN cc.month = '202601' THEN cc.commission END) +
                    MAX(CASE WHEN cc.month = '202602' THEN cc.commission END)
                ) / 3 AS UNSIGNED
            ) > 60000
            THEN TRUE
            ELSE FALSE
        END AS can_create,

        -- Assessment Limit
        CASE
            WHEN CAST(
                (
                    MAX(CASE WHEN cc.month = '202512' THEN cc.commission END) +
                    MAX(CASE WHEN cc.month = '202601' THEN cc.commission END) +
                    MAX(CASE WHEN cc.month = '202602' THEN cc.commission END)
                ) / 3 AS UNSIGNED
            ) < 60000 THEN 'Ineligible'

            WHEN CAST(
                (
                    MAX(CASE WHEN cc.month = '202512' THEN cc.commission END) +
                    MAX(CASE WHEN cc.month = '202601' THEN cc.commission END) +
                    MAX(CASE WHEN cc.month = '202602' THEN cc.commission END)
                ) / 3 AS UNSIGNED
            ) BETWEEN 60000 AND 119999 THEN 250000

            WHEN CAST(
                (
                    MAX(CASE WHEN cc.month = '202512' THEN cc.commission END) +
                    MAX(CASE WHEN cc.month = '202601' THEN cc.commission END) +
                    MAX(CASE WHEN cc.month = '202602' THEN cc.commission END)
                ) / 3 AS UNSIGNED
            ) BETWEEN 120000 AND 179999 THEN 500000

            WHEN CAST(
                (
                    MAX(CASE WHEN cc.month = '202512' THEN cc.commission END) +
                    MAX(CASE WHEN cc.month = '202601' THEN cc.commission END) +
                    MAX(CASE WHEN cc.month = '202602' THEN cc.commission END)
                ) / 3 AS UNSIGNED
            ) BETWEEN 180000 AND 249999 THEN 750000

            WHEN CAST(
                (
                    MAX(CASE WHEN cc.month = '202512' THEN cc.commission END) +
                    MAX(CASE WHEN cc.month = '202601' THEN cc.commission END) +
                    MAX(CASE WHEN cc.month = '202602' THEN cc.commission END)
                ) / 3 AS UNSIGNED
            ) BETWEEN 250000 AND 349999 THEN 1000000

            WHEN CAST(
                (
                    MAX(CASE WHEN cc.month = '202512' THEN cc.commission END) +
                    MAX(CASE WHEN cc.month = '202601' THEN cc.commission END) +
                    MAX(CASE WHEN cc.month = '202602' THEN cc.commission END)
                ) / 3 AS UNSIGNED
            ) BETWEEN 350000 AND 499999 THEN 1500000

            WHEN CAST(
                (
                    MAX(CASE WHEN cc.month = '202512' THEN cc.commission END) +
                    MAX(CASE WHEN cc.month = '202601' THEN cc.commission END) +
                    MAX(CASE WHEN cc.month = '202602' THEN cc.commission END)
                ) / 3 AS UNSIGNED
            ) BETWEEN 500000 AND 649999 THEN 2000000

            WHEN CAST(
                (
                    MAX(CASE WHEN cc.month = '202512' THEN cc.commission END) +
                    MAX(CASE WHEN cc.month = '202601' THEN cc.commission END) +
                    MAX(CASE WHEN cc.month = '202602' THEN cc.commission END)
                ) / 3 AS UNSIGNED
            ) BETWEEN 650000 AND 799999 THEN 2500000

            WHEN CAST(
                (
                    MAX(CASE WHEN cc.month = '202512' THEN cc.commission END) +
                    MAX(CASE WHEN cc.month = '202601' THEN cc.commission END) +
                    MAX(CASE WHEN cc.month = '202602' THEN cc.commission END)
                ) / 3 AS UNSIGNED
            ) BETWEEN 800000 AND 999999 THEN 3000000

            WHEN CAST(
                (
                    MAX(CASE WHEN cc.month = '202512' THEN cc.commission END) +
                    MAX(CASE WHEN cc.month = '202601' THEN cc.commission END) +
                    MAX(CASE WHEN cc.month = '202602' THEN cc.commission END)
                ) / 3 AS UNSIGNED
            ) BETWEEN 1000000 AND 1249999 THEN 4000000

            WHEN CAST(
                (
                    MAX(CASE WHEN cc.month = '202512' THEN cc.commission END) +
                    MAX(CASE WHEN cc.month = '202601' THEN cc.commission END) +
                    MAX(CASE WHEN cc.month = '202602' THEN cc.commission END)
                ) / 3 AS UNSIGNED
            ) >= 1250000 THEN 5000000
        END AS assessment_limit

    FROM cust_commissions cc
    LEFT JOIN customer_statements cs on cs.alt_acc_num = cc.alt_acc_num
    LEFT JOIN leads l on l.id = cs.entity_id and cs.entity = 'lead' and cs.is_removed = 0 and l.is_removed = 0 and l.type = 'kyc' and l.status != '60_customer_onboarded' and profile_status = 'open'
    LEFT JOIN accounts a
        ON a.alt_acc_num = cc.alt_acc_num
        AND a.is_removed = 0
    WHERE cc.month IN ('202512','202601','202602')
    GROUP BY cc.alt_acc_num
    HAVING `202512` IS NOT NULL
       AND `202601` IS NOT NULL
       AND `202602` IS NOT NULL
),

first_fa_limits AS (
    SELECT
        cd.alt_acc_num,
        cd.assessment_limit,

        CASE
            WHEN cd.assessment_limit = 'Ineligible' THEN 0
            WHEN cd.assessment_limit = 250000 THEN 250000
            WHEN cd.assessment_limit = 500000 THEN 500000
            WHEN cd.assessment_limit = 750000 THEN 750000
            WHEN cd.assessment_limit = 1000000 THEN 1000000
            WHEN cd.assessment_limit = 1500000 THEN 1000000
            ELSE LEAST(
                cd.assessment_limit * 0.5,
                (
                    SELECT MAX(lim)
                    FROM (
                        VALUES
                            ROW (250000),
                            ROW (500000),
                            ROW (750000),
                            ROW (1000000),
                            ROW (1500000),
                            ROW (2000000),
                            ROW (2500000),
                            ROW (3000000),
                            ROW (4000000),
                            ROW (5000000)
                    ) AS limits(lim)
                    WHERE lim <= cd.assessment_limit * 0.5
                )
            )
        END AS first_fa_limit
    FROM commission_data cd
)

SELECT
    cd.*,
    ffl.first_fa_limit
FROM commission_data cd
JOIN first_fa_limits ffl
  ON cd.alt_acc_num = ffl.alt_acc_num having first_fa_limit > 0;