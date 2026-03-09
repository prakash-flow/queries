WITH
  commission_data AS (
    SELECT
      cc.acc_number,
      MAX(
        CASE
          WHEN cc.month = "202512" THEN cc.distributor_code
        END
      ) AS distributor_code,
      UPPER(
        MAX(
          CASE
            WHEN cc.month = "202512" THEN cc.holder_name
          END
        )
      ) AS holder_name,
      -- Identify if the account belongs to a partner distributor
      IF(
        MAX(
          CASE
            WHEN cc.month = "202512" THEN cc.distributor_code
          END
        ) IN (
          "PHONECOM_NYARUGENGE",
          "PHONECOM_SOUTH",
          "ETS_BART_MUSANZE",
          "ETS_BART_GICUMBI"
        ),
        1,
        0
      ) AS is_partner,
      -- Special Distributor
      IF(
        MAX(
          CASE
            WHEN cc.month = "202512" THEN cc.distributor_code
          END
        ) IN ("ETS_BART_MUSANZE", "ETS_BART_GICUMBI"),
        1,
        0
      ) AS is_special_distributor,
      -- Commissions per month
      MAX(
        CASE
          WHEN cc.month = "202510" THEN cc.commission
        END
      ) AS `202510`,
      MAX(
        CASE
          WHEN cc.month = "202511" THEN cc.commission
        END
      ) AS `202511`,
      MAX(
        CASE
          WHEN cc.month = "202512" THEN cc.commission
        END
      ) AS `202512`,
      CASE
        WHEN a.acc_number IS NOT NULL THEN "account_exists"
        WHEN l.account_num IS NOT NULL THEN "lead_exists"
        WHEN p.mobile_num IS NOT NULL THEN "person_exists"
        ELSE "new_lead"
      END AS account_status,
      -- Can Create Flag
      CASE
        WHEN  (CAST(
            (
              MAX(
                CASE
                  WHEN cc.month = "202510" THEN cc.commission
                END
              ) + MAX(
                CASE
                  WHEN cc.month = "202511" THEN cc.commission
                END
              ) + MAX(
                CASE
                  WHEN cc.month = "202512" THEN cc.commission
                END
              )
            ) / 3
            AS UNSIGNED
          ) > 15000
        ) THEN TRUE
        ELSE FALSE
      END AS can_create,
      -- Average commission for 3 months
      CAST(
        (
          MAX(
            CASE
              WHEN cc.month = "202510" THEN cc.commission
            END
          ) + MAX(
            CASE
              WHEN cc.month = "202511" THEN cc.commission
            END
          ) + MAX(
            CASE
              WHEN cc.month = "202512" THEN cc.commission
            END
          )
        ) / 3
        AS UNSIGNED
      ) AS avg_commission,
      -- Assessment Limit
      CASE
        WHEN CAST(
          (
            MAX(
              CASE
                WHEN cc.month = "202510" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202511" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202512" THEN cc.commission
              END
            )
          ) / 3
          AS UNSIGNED
        ) < 15000 THEN "Ineligible"
        WHEN CAST(
          (
            MAX(
              CASE
                WHEN cc.month = "202510" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202511" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202512" THEN cc.commission
              END
            )
          ) / 3
          AS UNSIGNED
        ) BETWEEN 15000 AND 24999  THEN 70000
        WHEN CAST(
          (
            MAX(
              CASE
                WHEN cc.month = "202510" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202511" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202512" THEN cc.commission
              END
            )
          ) / 3
          AS UNSIGNED
        ) BETWEEN 25000 AND 34999  THEN 100000
        WHEN CAST(
          (
            MAX(
              CASE
                WHEN cc.month = "202510" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202511" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202512" THEN cc.commission
              END
            )
          ) / 3
		  AS UNSIGNED
        ) BETWEEN 35000 AND 49999  THEN 150000
        WHEN CAST(
          (
            MAX(
              CASE
                WHEN cc.month = "202510" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202511" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202512" THEN cc.commission
              END
            )
          ) / 3
		  AS UNSIGNED
        ) BETWEEN 50000 AND 69999  THEN 200000
        WHEN CAST(
          (
            MAX(
              CASE
                WHEN cc.month = "202510" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202511" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202512" THEN cc.commission
              END
            )
          ) / 3
		  AS UNSIGNED
        ) BETWEEN 70000 AND 89999  THEN 300000
        WHEN CAST(
          (
            MAX(
              CASE
                WHEN cc.month = "202510" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202511" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202512" THEN cc.commission
              END
            )
          ) / 3
		  AS UNSIGNED
        ) BETWEEN 90000 AND 109999  THEN 400000
        WHEN CAST(
          (
            MAX(
              CASE
                WHEN cc.month = "202510" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202511" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202512" THEN cc.commission
              END
            )
          ) / 3
		  AS UNSIGNED
        ) BETWEEN 110000 AND 129999  THEN 500000
        WHEN CAST(
          (
            MAX(
              CASE
                WHEN cc.month = "202510" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202511" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202512" THEN cc.commission
              END
            )
          ) / 3
		  AS UNSIGNED
        ) BETWEEN 130000 AND 149999  THEN 600000
        WHEN CAST(
          (
            MAX(
              CASE
                WHEN cc.month = "202510" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202511" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202512" THEN cc.commission
              END
            )
          ) / 3
		  AS UNSIGNED
        ) BETWEEN 150000 AND 169999  THEN 700000
        WHEN CAST(
          (
            MAX(
              CASE
                WHEN cc.month = "202510" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202511" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202512" THEN cc.commission
              END
            )
          ) / 3
		  AS UNSIGNED
        ) BETWEEN 170000 AND 189999  THEN 800000
        WHEN CAST(
          (
            MAX(
              CASE
                WHEN cc.month = "202510" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202511" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202512" THEN cc.commission
              END
            )
          ) / 3
		  AS UNSIGNED
        ) BETWEEN 190000 AND 209999  THEN 900000
        WHEN CAST(
          (
            MAX(
              CASE
                WHEN cc.month = "202510" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202511" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202512" THEN cc.commission
              END
            )
          ) / 3
		  AS UNSIGNED
        ) BETWEEN 210000 AND 299999  THEN 1000000
        WHEN CAST(
          (
            MAX(
              CASE
                WHEN cc.month = "202510" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202511" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202512" THEN cc.commission
              END
            )
          ) / 3
		  AS UNSIGNED
        ) BETWEEN 300000 AND 399999  THEN 1500000
        WHEN CAST(
          (
            MAX(
              CASE
                WHEN cc.month = "202510" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202511" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202512" THEN cc.commission
              END
            )
          ) / 3
		  AS UNSIGNED
        ) BETWEEN 400000 AND 499999  THEN 2000000
        WHEN CAST(
          (
            MAX(
              CASE
                WHEN cc.month = "202510" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202511" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202512" THEN cc.commission
              END
            )
          ) / 3
		  AS UNSIGNED
        ) BETWEEN 500000 AND 749999  THEN 2500000
        WHEN CAST(
          (
            MAX(
              CASE
                WHEN cc.month = "202510" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202511" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202512" THEN cc.commission
              END
            )
          ) / 3
		  AS UNSIGNED
        ) >= 750000 THEN 3000000
        ELSE NULL
      END AS assessment_limit
    FROM
      cust_commissions cc
      LEFT JOIN leads l ON l.account_num = cc.acc_number
      AND l.is_removed = 0
      AND l.self_reg_status = "pending_self_reg"
      AND l.status <= "40_pending_kyc"
      LEFT JOIN accounts a ON a.acc_number = cc.acc_number
      AND a.is_removed = 0
      LEFT JOIN persons p
        ON p.mobile_num = cc.acc_number
    WHERE
      cc.month IN ("202510", "202511", "202512")
    GROUP BY
      cc.acc_number
    HAVING
      `202510` IS NOT NULL
      AND `202511` IS NOT NULL
      AND `202512` IS NOT NULL
  ),
  first_fa_limits AS (
    SELECT
      cd.acc_number,
      cd.assessment_limit,
      cd.is_special_distributor,
      -- Calculate cycle limit
      cd.assessment_limit * 0.5 AS cycle_limit,
      -- Find the max available limit below cycle_limit
      (
        SELECT
          MAX(lim)
        FROM
          (
            VALUES
              ROW (70000),
              ROW (100000),
              ROW (150000),
              ROW (200000),
              ROW (300000),
              ROW (400000),
              ROW (500000),
              ROW (600000),
              ROW (700000),
              ROW (800000),
              ROW (900000),
              ROW (1000000),
              ROW (1500000),
              ROW (2000000),
              ROW (2500000),
              ROW (3000000)
          ) AS limits (lim)
        WHERE
          lim <= cd.assessment_limit * 0.5
      ) AS max_limit_below_cycle_limit,
      -- Final First FA Limit Logic
      CASE
        WHEN cd.assessment_limit = 'Ineligible' THEN 0
        -- Special Distributor Rule
        WHEN cd.is_special_distributor = 1 THEN LEAST(
          CAST(cd.assessment_limit AS UNSIGNED),
          GREATEST(400000, cd.assessment_limit * 0.5)
        )
        -- If assessment limit <= 150k
        WHEN CAST(cd.assessment_limit AS UNSIGNED) <= 150000 THEN LEAST(CAST(cd.assessment_limit AS UNSIGNED), 100000)
        WHEN is_partner = 1 THEN LEAST(
          400000,
          cd.assessment_limit * 0.5,
          (
            SELECT
              MAX(lim)
            FROM
              (
                VALUES
                  ROW (70000),
                  ROW (100000),
                  ROW (150000),
                  ROW (200000),
                  ROW (300000),
                  ROW (400000),
                  ROW (500000),
                  ROW (600000),
                  ROW (700000),
                  ROW (800000),
                  ROW (900000),
                  ROW (1000000),
                  ROW (1500000),
                  ROW (2000000),
                  ROW (2500000),
                  ROW (3000000)
              ) AS limits (lim)
            WHERE
              lim <= cd.assessment_limit * 0.5
          )
        )
        ELSE LEAST(
          cd.assessment_limit * 0.5,
          (
            SELECT
              MAX(lim)
            FROM
              (
                VALUES
                  ROW (70000),
                  ROW (100000),
                  ROW (150000),
                  ROW (200000),
                  ROW (300000),
                  ROW (400000),
                  ROW (500000),
                  ROW (600000),
                  ROW (700000),
                  ROW (800000),
                  ROW (900000),
                  ROW (1000000),
                  ROW (1500000),
                  ROW (2000000),
                  ROW (2500000),
                  ROW (3000000)
              ) AS limits (lim)
            WHERE
              lim <= cd.assessment_limit * 0.5
          )
        )
      END AS first_fa_limit
    FROM
      commission_data cd
  )
SELECT
  cd.*,
  ffl.first_fa_limit
FROM
  commission_data cd
  JOIN first_fa_limits ffl ON cd.acc_number = ffl.acc_number;