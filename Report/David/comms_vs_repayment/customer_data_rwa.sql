WITH 
    -- Base limit
    IF(
        crl.cust_id IS NOT NULL,
        least(crl.current_limit, coalesce(ml.max_limit, 0)),
        coalesce(ml.max_limit, 0)
    ) AS base_limit,

    -- Apply referral cap
    IF(
        b.category = 'Referral',
        least(400000, base_limit),
        base_limit
    ) AS capped_limit,

    -- Slabs
    [70000,100000,150000,200000,300000,400000,500000,600000,
     700000,800000,900000,1000000,1500000,2000000,2500000,3000000] AS slabs,

    -- Final rounded limit
    coalesce(
        arrayMax(arrayFilter(x -> x <= capped_limit, slabs)),
        70000
    ) AS final_limit

SELECT
    b.cust_id AS `Customer ID`,
    p.full_name AS `Customer Name`,
    rm.full_name AS `RM Name`,

    -- Assessment date fallback
    coalesce(b.last_assessment_date, toDate(acc.acc_last_assessment_date)) AS `Last Assessment Date`,

    ml.max_limit AS `Actual Eligibility`,
    final_limit AS `Current FA Limit`,

    -- RMTN assessed accounts
    coalesce(acc.rmtn_count, 0) AS `RMTN Assessed Accounts`,

    -- ✅ Monthly commissions from EXACT max_limit row
    coalesce(ml.monthly_comms, 0) AS `Monthly Commissions`

FROM borrowers b

LEFT JOIN persons p
    ON p.id = b.owner_person_id

LEFT JOIN persons rm
    ON rm.id = b.flow_rel_mgr_id

-- ✅ Correct: pick exact row for max_limit
LEFT JOIN (
    SELECT
        cust_id,

        max(limit) AS max_limit,

        argMax(monthly_comms, (limit, last_assessment_date, id)) AS monthly_comms

    FROM
    (
        SELECT
            a.id,
            a.cust_id,
            a.last_assessment_date,

            -- extract limit per row
            arrayMax(
                arrayMap(
                    x -> JSONExtractInt(x, 'limit'),
                    JSONExtractArrayRaw(
                        replaceAll(
                            replaceAll(a.conditions, '""', '"'),
                            '''', '"'
                        )
                    )
                )
            ) AS limit,

            -- extract monthly_comms per row
            anyIf(
                JSONExtractFloat(y, 'g_val'),
                JSONExtractString(y, 'csf_type') = 'monthly_comms'
            ) AS monthly_comms

        FROM accounts a

        ARRAY JOIN JSONExtractArrayRaw(
            replaceAll(
                replaceAll(a.cust_score_factors, '""', '"'),
                '''', '"'
            )
        ) AS y

        WHERE a.status = 'enabled'
          AND a.is_removed = 0
          AND a.conditions LIKE '%limit%'
          AND a.conditions NOT LIKE '%object Object%'

        GROUP BY a.id, a.cust_id, a.last_assessment_date, a.conditions
    )

    GROUP BY cust_id
) ml
ON ml.cust_id = b.cust_id

-- Accounts aggregation (date + RMTN count)
LEFT JOIN (
    SELECT 
        cust_id,
        max(last_assessment_date) AS acc_last_assessment_date,

        countIf(
            acc_prvdr_code = 'RMTN'
            AND last_assessment_date IS NOT NULL
        ) AS rmtn_count

    FROM accounts
    WHERE status = 'enabled'
      AND is_removed = 0
    GROUP BY cust_id
) acc
ON acc.cust_id = b.cust_id

-- Repayment limit
LEFT JOIN (
    SELECT
        cust_id,
        any(current_limit) AS current_limit
    FROM customer_repayment_limits
    WHERE status = 'enabled'
    GROUP BY cust_id
) crl
ON crl.cust_id = b.cust_id

WHERE
    b.country_code = 'RWA'
    AND ml.max_limit IS NOT NULL;