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
    b.reg_date AS `Registration Date`,
    b.distributor_code AS `Distributor Code`,

    p.full_name AS `Customer Name`,
    p.mobile_num AS `Mobile Number`,
    p.alt_biz_mobile_num_1 AS `Alt Mobile 1`,
    p.alt_biz_mobile_num_2 AS `Alt Mobile 2`,

    rm.full_name AS `RM Name`,

    ml.max_limit AS `Actual Eligibility`,

    -- ✅ Final FA Limit (after cap + slab)
    final_limit AS `Current FA Limit`,

    toDate(l.last_loan_date) AS `Last Loan Date`,
    l.recent_fa_amount AS `Recent FA Amount`,
    l.max_loan_amount AS `Maximum FA Amount Taken`,
    l.total_loans AS `No of FAs`,

    IF(b.category = 'Referral', 'Referral', 'Full KYC') 
        AS `Self Registered / Full KYC`,

    CASE 
        WHEN l.last_loan_date IS NULL THEN 'No Loan'
        WHEN dateDiff('day', l.last_loan_date, today()) > 30 THEN 'Inactive'
        ELSE 'Active'
    END AS `Activity Status`,

    -- ✅ Utilization
    IF(
        final_limit > coalesce(l.recent_fa_amount, 0),
        'Not Utilized',
        'Utilized'
    ) AS `Utilizing Upgraded Amount`,
  
    -- ✅ Eligibility comparison
    IF(
        final_limit != coalesce(ml.max_limit, 0),
        'Different',
        'Same'
    ) AS `Limit vs Eligibility`

FROM borrowers b

LEFT JOIN persons p
    ON p.id = b.owner_person_id

LEFT JOIN persons rm
    ON rm.id = b.flow_rel_mgr_id

-- ✅ FIXED accounts aggregation (NO any())
LEFT JOIN (
    SELECT
        cust_id,
        max(limit) AS max_limit
    FROM
    (
        SELECT
            cust_id,
            arrayJoin(
                arrayMap(
                    x -> JSONExtractInt(x, 'limit'),
                    JSONExtractArrayRaw(
                        replaceAll(
                            replaceAll(conditions, '""', '"'),
                            '''', '"'
                        )
                    )
                )
            ) AS limit
        FROM accounts
        WHERE status = 'enabled'
          AND is_removed = 0
          AND conditions LIKE '%limit%'
          AND conditions NOT LIKE '%object Object%'
    )
    GROUP BY cust_id
) ml 
ON ml.cust_id = b.cust_id

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

-- Loan aggregation
LEFT JOIN (
    SELECT
        l.cust_id,
        max(l.disbursal_date) AS last_loan_date,
        argMax(l.loan_principal, l.disbursal_date) AS recent_fa_amount,
        max(l.loan_principal) AS max_loan_amount,
        count(*) AS total_loans
    FROM loans l
    LEFT JOIN loan_products lp 
        ON l.product_id = lp.id
    WHERE
        l.loan_purpose = 'float_advance'
        AND (lp.product_type != 'float_vending' OR lp.id IS NULL)
        AND l.status NOT IN (
            'voided',
            'hold',
            'pending_disbursal',
            'pending_mnl_dsbrsl'
        )
    GROUP BY l.cust_id
) l
ON l.cust_id = b.cust_id

WHERE
    b.country_code = 'RWA'

HAVING 
    `Activity Status` = 'Active' 
    AND `Self Registered / Full KYC` != 'Referral';