WITH
  monthly_data AS (
    SELECT
      cc.acc_number,
      COALESCE(
        MAX(CASE WHEN cc.month = "202609" THEN cc.distributor_code END),
        MAX(CASE WHEN cc.month = "202608" THEN cc.distributor_code END),
        MAX(CASE WHEN cc.month = "202607" THEN cc.distributor_code END)
      ) AS distributor_code,
      UPPER(
        COALESCE(
          MAX(CASE WHEN cc.month = "202609" THEN cc.holder_name END),
          MAX(CASE WHEN cc.month = "202608" THEN cc.holder_name END),
          MAX(CASE WHEN cc.month = "202607" THEN cc.holder_name END)
        )
      ) AS holder_name,
      MAX(CASE WHEN cc.month = "202607" THEN cc.commission END) AS `202607`,
      MAX(CASE WHEN cc.month = "202608" THEN cc.commission END) AS `202608`,
      MAX(CASE WHEN cc.month = "202609" THEN cc.commission END) AS `202609`,
      CASE
        WHEN MAX(a.acc_number) IS NOT NULL THEN "account_exists"
        WHEN MAX(p.mobile_num) IS NOT NULL THEN "person_exists"
        WHEN MAX(pa1.id) IS NOT NULL THEN "alt_biz_mobile_1_exists"
        WHEN MAX(pa2.id) IS NOT NULL THEN "alt_biz_mobile_2_exists"
        WHEN MAX(l.account_num) IS NOT NULL THEN "lead_exists"
        ELSE "new_lead"
      END AS account_status,
      -- Latest lead status (statuses are number-prefixed, so MAX is the furthest stage)
      MAX(l.status) AS lead_status
    FROM
      cust_commissions cc
      LEFT JOIN leads l ON l.account_num = cc.acc_number
      AND l.is_removed = 0
      LEFT JOIN accounts a ON a.acc_number = cc.acc_number
      AND a.is_removed = 0
      LEFT JOIN persons p
        ON p.mobile_num = cc.acc_number
      LEFT JOIN persons pa1
        ON pa1.alt_biz_mobile_num_1 = cc.acc_number
      LEFT JOIN persons pa2
        ON pa2.alt_biz_mobile_num_2 = cc.acc_number
    WHERE
      cc.month IN ("202607", "202608", "202609")
    GROUP BY
      cc.acc_number
    HAVING
      `202607` IS NOT NULL
      AND `202608` IS NOT NULL
      AND `202609` IS NOT NULL
  ),
  commission_data AS (
    SELECT
      md.acc_number,
      md.distributor_code,
      md.holder_name,
      -- Identify if the account belongs to a partner distributor
      IF(
        md.distributor_code IN (
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
        md.distributor_code IN ("ETS_BART_MUSANZE", "ETS_BART_GICUMBI"),
        1,
        0
      ) AS is_special_distributor,
      md.`202607`,
      md.`202608`,
      md.`202609`,
      md.account_status,
      md.lead_status,
      -- Can Create Flag
      ac.avg_commission >= 15000 AS can_create,
      -- Average commission for 3 months (rounded down)
      ac.avg_commission,
      -- Assessment Limit
      CASE
        WHEN ac.avg_commission < 15000 THEN "Ineligible"
        WHEN ac.avg_commission < 25000 THEN 70000
        WHEN ac.avg_commission < 35000 THEN 100000
        WHEN ac.avg_commission < 50000 THEN 150000
        WHEN ac.avg_commission < 70000 THEN 200000
        WHEN ac.avg_commission < 90000 THEN 300000
        WHEN ac.avg_commission < 110000 THEN 400000
        WHEN ac.avg_commission < 130000 THEN 500000
        WHEN ac.avg_commission < 150000 THEN 600000
        WHEN ac.avg_commission < 170000 THEN 700000
        WHEN ac.avg_commission < 190000 THEN 800000
        WHEN ac.avg_commission < 210000 THEN 900000
        WHEN ac.avg_commission < 300000 THEN 1000000
        WHEN ac.avg_commission < 400000 THEN 1500000
        WHEN ac.avg_commission < 500000 THEN 2000000
        WHEN ac.avg_commission < 750000 THEN 2500000
        ELSE 3000000
      END AS assessment_limit
    FROM
      monthly_data md
      CROSS JOIN LATERAL (
        SELECT
          FLOOR((md.`202607` + md.`202608` + md.`202609`) / 3) AS avg_commission
      ) AS ac
  ),
  limit_steps AS (
    SELECT lim
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
  ),
  first_fa_limits AS (
    SELECT
      cd.acc_number,
      -- Final First FA Limit Logic
      CASE
        WHEN cd.assessment_limit = "Ineligible" THEN 0
        -- If assessment limit <= 150k
        WHEN al.lim <= 150000 THEN LEAST(al.lim, 100000)
        -- Special Distributor Rule (snapped down to a valid limit step)
        WHEN cd.is_special_distributor = 1 THEN (
          SELECT MAX(lim)
          FROM limit_steps
          WHERE lim <= LEAST(al.lim, GREATEST(400000, al.lim * 0.5))
        )
        WHEN cd.is_partner = 1 THEN (
          SELECT MAX(lim)
          FROM limit_steps
          WHERE lim <= LEAST(400000, al.lim * 0.5)
        )
        ELSE (
          SELECT MAX(lim)
          FROM limit_steps
          WHERE lim <= al.lim * 0.5
        )
      END AS first_fa_limit
    FROM
      commission_data cd
      -- assessment_limit is a string column ("Ineligible" or a number), so cast it before LEAST/GREATEST
      CROSS JOIN LATERAL (
        SELECT IF(cd.assessment_limit = "Ineligible", 0, CAST(cd.assessment_limit AS UNSIGNED)) AS lim
      ) AS al
  )
SELECT
  cd.*,
  ffl.first_fa_limit
FROM
  commission_data cd
  JOIN first_fa_limits ffl ON cd.acc_number = ffl.acc_number
WHERE cd.assessment_limit != "Ineligible";
