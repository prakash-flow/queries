WITH
  commission_data AS (
    SELECT
      cc.acc_number,
            COALESCE(
        MAX(
          CASE
            WHEN cc.month = "202606" THEN cc.distributor_code
          END
        ),
        MAX(
          CASE
            WHEN cc.month = "202605" THEN cc.distributor_code
          END
        ),
        MAX(
          CASE
            WHEN cc.month = "202604" THEN cc.distributor_code
          END
        )
      ) AS distributor_code,
      UPPER(
        COALESCE(
          MAX(
            CASE
              WHEN cc.month = "202606" THEN cc.holder_name
            END
          ),
          MAX(
            CASE
              WHEN cc.month = "202605" THEN cc.holder_name
            END
          ),
          MAX(
            CASE
              WHEN cc.month = "202604" THEN cc.holder_name
            END
          )
        )
      ) AS holder_name,
      IF(
        MAX(
          CASE
            WHEN cc.month = "202606" THEN cc.distributor_code
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
      -- Commissions per month
      MAX(
        CASE
          WHEN cc.month = "202604" THEN cc.commission
        END
      ) AS `202604`,
      MAX(
        CASE
          WHEN cc.month = "202605" THEN cc.commission
        END
      ) AS `202605`,
      MAX(
        CASE
          WHEN cc.month = "202606" THEN cc.commission
        END
      ) AS `202606`,
      -- Average commission for 3 months
      CAST(
        (
          MAX(
            CASE
              WHEN cc.month = "202604" THEN cc.commission
            END
          ) + MAX(
            CASE
              WHEN cc.month = "202605" THEN cc.commission
            END
          ) + MAX(
            CASE
              WHEN cc.month = "202606" THEN cc.commission
            END
          )
        ) / 3 AS UNSIGNED
      ) AS avg_commission,
      -- Assessment Limit
      CASE
        WHEN CAST(
          (
            MAX(
              CASE
                WHEN cc.month = "202604" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202605" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202606" THEN cc.commission
              END
            )
          ) / 3 AS UNSIGNED
        ) < 15000 THEN "Ineligible"
        WHEN CAST(
          (
            MAX(
              CASE
                WHEN cc.month = "202604" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202605" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202606" THEN cc.commission
              END
            )
          ) / 3 AS UNSIGNED
        ) BETWEEN 15000 AND 24999  THEN 70000
        WHEN CAST(
          (
            MAX(
              CASE
                WHEN cc.month = "202604" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202605" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202606" THEN cc.commission
              END
            )
          ) / 3 AS UNSIGNED
        ) BETWEEN 25000 AND 34999  THEN 100000
        WHEN CAST(
          (
            MAX(
              CASE
                WHEN cc.month = "202604" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202605" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202606" THEN cc.commission
              END
            )
          ) / 3 AS UNSIGNED
        ) BETWEEN 35000 AND 49999  THEN 150000
        WHEN CAST(
          (
            MAX(
              CASE
                WHEN cc.month = "202604" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202605" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202606" THEN cc.commission
              END
            )
          ) / 3 AS UNSIGNED
        ) BETWEEN 50000 AND 69999  THEN 200000
        WHEN CAST(
          (
            MAX(
              CASE
                WHEN cc.month = "202604" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202605" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202606" THEN cc.commission
              END
            )
          ) / 3 AS UNSIGNED
        ) BETWEEN 70000 AND 89999  THEN 300000
        WHEN CAST(
          (
            MAX(
              CASE
                WHEN cc.month = "202604" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202605" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202606" THEN cc.commission
              END
            )
          ) / 3 AS UNSIGNED
        ) BETWEEN 90000 AND 109999  THEN 400000
        WHEN CAST(
          (
            MAX(
              CASE
                WHEN cc.month = "202604" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202605" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202606" THEN cc.commission
              END
            )
          ) / 3 AS UNSIGNED
        ) BETWEEN 110000 AND 129999  THEN 500000
        WHEN CAST(
          (
            MAX(
              CASE
                WHEN cc.month = "202604" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202605" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202606" THEN cc.commission
              END
            )
          ) / 3 AS UNSIGNED
        ) BETWEEN 130000 AND 149999  THEN 600000
        WHEN CAST(
          (
            MAX(
              CASE
                WHEN cc.month = "202604" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202605" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202606" THEN cc.commission
              END
            )
          ) / 3 AS UNSIGNED
        ) BETWEEN 150000 AND 169999  THEN 700000
        WHEN CAST(
          (
            MAX(
              CASE
                WHEN cc.month = "202604" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202605" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202606" THEN cc.commission
              END
            )
          ) / 3 AS UNSIGNED
        ) BETWEEN 170000 AND 189999  THEN 800000
        WHEN CAST(
          (
            MAX(
              CASE
                WHEN cc.month = "202604" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202605" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202606" THEN cc.commission
              END
            )
          ) / 3 AS UNSIGNED
        ) BETWEEN 190000 AND 209999  THEN 900000
        WHEN CAST(
          (
            MAX(
              CASE
                WHEN cc.month = "202604" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202605" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202606" THEN cc.commission
              END
            )
          ) / 3 AS UNSIGNED
        ) BETWEEN 210000 AND 299999  THEN 1000000
        WHEN CAST(
          (
            MAX(
              CASE
                WHEN cc.month = "202604" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202605" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202606" THEN cc.commission
              END
            )
          ) / 3 AS UNSIGNED
        ) BETWEEN 300000 AND 399999  THEN 1500000
        WHEN CAST(
          (
            MAX(
              CASE
                WHEN cc.month = "202604" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202605" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202606" THEN cc.commission
              END
            )
          ) / 3 AS UNSIGNED
        ) BETWEEN 400000 AND 499999  THEN 2000000
        WHEN CAST(
          (
            MAX(
              CASE
                WHEN cc.month = "202604" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202605" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202606" THEN cc.commission
              END
            )
          ) / 3 AS UNSIGNED
        ) BETWEEN 500000 AND 749999  THEN 2500000
        WHEN CAST(
          (
            MAX(
              CASE
                WHEN cc.month = "202604" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202605" THEN cc.commission
              END
            ) + MAX(
              CASE
                WHEN cc.month = "202606" THEN cc.commission
              END
            )
          ) / 3 AS UNSIGNED
        ) >= 750000 THEN 3000000
        ELSE NULL
      END AS assessment_limit,
      MAX(field_1) `Province`,
      MAX(field_2) `District`,
      MAX(field_3) `Sector`,
      MAX(field_4) `Cell`,
      MAX(field_5) `Village`,
      MAX(field_6) `Location`,
      MAX(field_10) `GPS`,
      MAX(field_8) `Territory`,
      MAX(field_9) `Landmark`
    FROM
      cust_commissions cc
      LEFT JOIN accounts a ON a.acc_number = cc.acc_number
      AND a.is_removed = 0
      LEFT JOIN borrowers b on b.cust_id = a.cust_id
      LEFT JOIN address_info ai on ai.id = b.owner_address_id
    WHERE
      cc.month IN ("202604", "202605", "202606")
    GROUP BY
      cc.acc_number
    HAVING
      `202604` IS NOT NULL
      AND `202605` IS NOT NULL
      AND `202606` IS NOT NULL
  )
select
  *
from
  commission_data;