WITH base_customers AS (
    SELECT DISTINCT cust_id
    FROM accounts
    WHERE acc_prvdr_code = 'UMTN'
      AND status = 'enabled'
      AND is_removed = 0
      AND (
            JSON_CONTAINS(acc_purpose, '"float_advance"')
         OR JSON_CONTAINS(acc_purpose, '"float_switch"')
      )
),

account_base AS (
    SELECT 
        a.cust_id,
        a.acc_number,
        a.alt_acc_num,
        a.acc_prvdr_code,
        a.is_primary_acc,
        a.last_assessment_date,
        IFNULL(MAX(jt.g_val), 0) AS average_comms,
        a.acc_ownership,

        -- flag for float_advance
        CASE
            WHEN JSON_CONTAINS(a.acc_purpose, '"float_advance"') THEN 1
            ELSE 0
        END AS has_float_advance

    FROM accounts a
    INNER JOIN base_customers bc
        ON bc.cust_id = a.cust_id
    LEFT JOIN JSON_TABLE(
        a.cust_score_factors,
        "$[*]" COLUMNS (
            csf_type VARCHAR(50) PATH "$.csf_type",
            g_val BIGINT PATH "$.g_val"
        )
    ) jt 
        ON jt.csf_type = 'monthly_comms'
    WHERE a.status = 'enabled'
      AND a.is_removed = 0
    GROUP BY 
        a.cust_id,
        a.acc_number,
        a.alt_acc_num,
        a.acc_prvdr_code,
        a.is_primary_acc,
        a.last_assessment_date,
        a.acc_ownership,
        has_float_advance
)

SELECT
    ab.cust_id,
    ab.acc_number,
    ab.alt_acc_num,
    ab.acc_prvdr_code,
    ab.is_primary_acc,
    ab.last_assessment_date,
    ab.average_comms,
    ab.acc_ownership,
    ab.has_float_advance,

    -- Monthly commissions (NA vs 0 distinction)
    CASE
        WHEN SUM(CASE WHEN cc.month = '202501' THEN 1 END) IS NULL THEN 'NA'
        ELSE CAST(SUM(CASE WHEN cc.month = '202501'
                           THEN CAST(cc.commission AS DECIMAL(15,2)) END) AS CHAR)
    END AS jan_commission,

    CASE
        WHEN SUM(CASE WHEN cc.month = '202502' THEN 1 END) IS NULL THEN 'NA'
        ELSE CAST(SUM(CASE WHEN cc.month = '202502'
                           THEN CAST(cc.commission AS DECIMAL(15,2)) END) AS CHAR)
    END AS feb_commission,

    CASE
        WHEN SUM(CASE WHEN cc.month = '202503' THEN 1 END) IS NULL THEN 'NA'
        ELSE CAST(SUM(CASE WHEN cc.month = '202503'
                           THEN CAST(cc.commission AS DECIMAL(15,2)) END) AS CHAR)
    END AS mar_commission,

    CASE
        WHEN SUM(CASE WHEN cc.month = '202504' THEN 1 END) IS NULL THEN 'NA'
        ELSE CAST(SUM(CASE WHEN cc.month = '202504'
                           THEN CAST(cc.commission AS DECIMAL(15,2)) END) AS CHAR)
    END AS apr_commission,

    CASE
        WHEN SUM(CASE WHEN cc.month = '202505' THEN 1 END) IS NULL THEN 'NA'
        ELSE CAST(SUM(CASE WHEN cc.month = '202505'
                           THEN CAST(cc.commission AS DECIMAL(15,2)) END) AS CHAR)
    END AS may_commission,

    CASE
        WHEN SUM(CASE WHEN cc.month = '202506' THEN 1 END) IS NULL THEN 'NA'
        ELSE CAST(SUM(CASE WHEN cc.month = '202506'
                           THEN CAST(cc.commission AS DECIMAL(15,2)) END) AS CHAR)
    END AS jun_commission,

    CASE
        WHEN SUM(CASE WHEN cc.month = '202507' THEN 1 END) IS NULL THEN 'NA'
        ELSE CAST(SUM(CASE WHEN cc.month = '202507'
                           THEN CAST(cc.commission AS DECIMAL(15,2)) END) AS CHAR)
    END AS jul_commission,

    CASE
        WHEN SUM(CASE WHEN cc.month = '202508' THEN 1 END) IS NULL THEN 'NA'
        ELSE CAST(SUM(CASE WHEN cc.month = '202508'
                           THEN CAST(cc.commission AS DECIMAL(15,2)) END) AS CHAR)
    END AS aug_commission,

    CASE
        WHEN SUM(CASE WHEN cc.month = '202509' THEN 1 END) IS NULL THEN 'NA'
        ELSE CAST(SUM(CASE WHEN cc.month = '202509'
                           THEN CAST(cc.commission AS DECIMAL(15,2)) END) AS CHAR)
    END AS sep_commission,

    CASE
        WHEN SUM(CASE WHEN cc.month = '202510' THEN 1 END) IS NULL THEN 'NA'
        ELSE CAST(SUM(CASE WHEN cc.month = '202510'
                           THEN CAST(cc.commission AS DECIMAL(15,2)) END) AS CHAR)
    END AS oct_commission,

    CASE
        WHEN SUM(CASE WHEN cc.month = '202511' THEN 1 END) IS NULL THEN 'NA'
        ELSE CAST(SUM(CASE WHEN cc.month = '202511'
                           THEN CAST(cc.commission AS DECIMAL(15,2)) END) AS CHAR)
    END AS nov_commission,

    CASE
        WHEN SUM(CASE WHEN cc.month = '202512' THEN 1 END) IS NULL THEN 'NA'
        ELSE CAST(SUM(CASE WHEN cc.month = '202512'
                           THEN CAST(cc.commission AS DECIMAL(15,2)) END) AS CHAR)
    END AS dec_commission

FROM account_base ab
LEFT JOIN cust_commissions cc
    ON cc.identifier = ab.alt_acc_num
   AND cc.month BETWEEN '202501' AND '202512'
   AND cc.country_code = 'UGA'

GROUP BY
    ab.cust_id,
    ab.acc_number,
    ab.alt_acc_num,
    ab.acc_prvdr_code,
    ab.is_primary_acc,
    ab.last_assessment_date,
    ab.average_comms,
    ab.acc_ownership,
    ab.has_float_advance;