WITH 
[100000,250000,500000,750000,1000000,1500000,2000000,2500000,3000000,4000000,5000000] AS slabs

SELECT
    b.cust_id AS `Customer ID`,
    p.full_name AS `Customer Name`,
    rm.full_name AS `RM Name`,
    coalesce(b.last_assessment_date, toDate(acc_agg.acc_last_assessment_date)) AS `Last Assessment Date`,
    ml.max_limit AS `Actual Eligibility`,
    ml.limit_source AS `Limit Source`,

    -- ✅ IMPROVED CURRENT FA LIMIT LOGIC
    coalesce(
        arrayMax(
            arrayFilter(
                x -> x <= IF(
                    crl.cust_id IS NOT NULL AND length(crl.cust_id) > 0, 
                    least(
                        toFloat64(crl.current_limit), 
                        toFloat64(coalesce(crl.downgrade_cycle_limit, crl.current_limit)), 
                        toFloat64(coalesce(ml.max_limit, 0))
                    ), 
                    toFloat64(coalesce(ml.max_limit, 0))
                ),
                slabs
            )
        ),
        ml.max_limit
    ) AS `Current FA Limit`,

    coalesce(acc_agg.mtn_count, 0) AS `MTN Assessed Accounts`,
    coalesce(acc_agg.uatl_count, 0) AS `Airtel Assessed Accounts`,
    coalesce(acc_agg.cca_count, 0) AS `CCA Assessed Accounts`,
    coalesce(ml.monthly_comms, 0) AS `Monthly Commissions`

FROM borrowers b
LEFT JOIN persons p ON p.id = b.owner_person_id
LEFT JOIN persons rm ON rm.id = b.flow_rel_mgr_id

LEFT JOIN (
    SELECT
        cust_id,
        if(has_b_limit, b_limit, a_limit) AS max_limit,
        if(has_b_limit, a_sum_monthly_comms, a_monthly_comms) AS monthly_comms,
        if(has_b_limit, 'Borrower', 'Account') AS limit_source
    FROM (
        SELECT 
            b.cust_id,
            (b.conditions LIKE '%"limit"%' AND b.conditions NOT LIKE '%object Object%') AS has_b_limit,
            arrayMax(arrayMap(x -> JSONExtractInt(x, 'limit'), JSONExtractArrayRaw(replaceAll(replaceAll(b.conditions, '""', '"'), '''', '"')))) AS b_limit,
            coalesce(acc.a_limit, 0) AS a_limit,
            coalesce(acc.a_monthly_comms, 0) AS a_monthly_comms,
            coalesce(acc.a_sum_monthly_comms, 0) AS a_sum_monthly_comms
        FROM borrowers b
        LEFT JOIN (
            SELECT 
                cust_id,
                max(limit) AS a_limit,
                argMax(monthly_comms, (limit, last_assessment_date, id)) AS a_monthly_comms,
                sum(monthly_comms) AS a_sum_monthly_comms
            FROM (
                SELECT
                    a.id, a.cust_id, a.last_assessment_date,
                    arrayMax(arrayMap(x -> JSONExtractInt(x, 'limit'), JSONExtractArrayRaw(replaceAll(replaceAll(a.conditions, '""', '"'), '''', '"')))) AS limit,
                    anyIf(JSONExtractFloat(y, 'g_val'), JSONExtractString(y, 'csf_type') = 'monthly_comms') AS monthly_comms
                FROM accounts a
                LEFT ARRAY JOIN JSONExtractArrayRaw(replaceAll(replaceAll(a.cust_score_factors, '""', '"'), '''', '"')) AS y
                WHERE a.status = 'enabled' AND a.is_removed = 0 
                  AND a.conditions LIKE '%limit%' AND a.conditions NOT LIKE '%object Object%'
                GROUP BY a.id, a.cust_id, a.last_assessment_date, a.conditions
            )
            GROUP BY cust_id
        ) acc ON acc.cust_id = b.cust_id
    )
) ml ON ml.cust_id = b.cust_id

LEFT JOIN (
    SELECT 
        cust_id,
        max(last_assessment_date) AS acc_last_assessment_date,
        countIf(acc_prvdr_code = 'UMTN' AND last_assessment_date IS NOT NULL) AS mtn_count,
        countIf(acc_prvdr_code = 'UATL' AND last_assessment_date IS NOT NULL) AS uatl_count,
        countIf(acc_prvdr_code = 'CCA' AND last_assessment_date IS NOT NULL) AS cca_count
    FROM accounts
    WHERE status = 'enabled' AND is_removed = 0
    GROUP BY cust_id
) acc_agg ON acc_agg.cust_id = b.cust_id

LEFT JOIN (
    SELECT 
        cust_id, 
        any(current_limit) AS current_limit,
        any(downgrade_cycle_limit) AS downgrade_cycle_limit
    FROM customer_repayment_limits 
    WHERE status = 'enabled' 
    GROUP BY cust_id
) crl ON crl.cust_id = b.cust_id

WHERE b.country_code = 'UGA'
  AND b.category IS NOT NULL
  AND ml.max_limit IS NOT NULL;