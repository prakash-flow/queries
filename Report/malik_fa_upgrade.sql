WITH
reassessment AS (
    SELECT cust_id, prev_limit
    FROM reassessment_results
    WHERE type = 'batch_reassessment'
      AND country_code = 'RWA'
      AND DATE(created_at) = '2026-02-12'
),

limit_slabs AS (
    SELECT 70000 AS lmt UNION ALL
    SELECT 100000 UNION ALL
    SELECT 150000 UNION ALL
    SELECT 200000 UNION ALL
    SELECT 300000 UNION ALL
    SELECT 400000 UNION ALL
    SELECT 500000 UNION ALL
    SELECT 600000 UNION ALL
    SELECT 700000 UNION ALL
    SELECT 800000 UNION ALL
    SELECT 900000 UNION ALL
    SELECT 1000000 UNION ALL
    SELECT 1500000 UNION ALL
    SELECT 2000000 UNION ALL
    SELECT 2500000 UNION ALL
    SELECT 3000000
),

current_limit AS (
    SELECT
        a.cust_id,
        MAX(j.`limit`) AS cur_limit
    FROM accounts a
    JOIN JSON_TABLE(
        a.conditions,
        '$[*]' COLUMNS (
            type VARCHAR(50) PATH '$.type',
            `limit` DECIMAL(12) PATH '$.limit'
        )
    ) j
    WHERE a.is_removed = 0
      AND a.status = 'enabled'
      AND a.cust_id IN (SELECT cust_id FROM reassessment)
    GROUP BY a.cust_id
),

customer_repayment AS (
    SELECT cust_id, loan_repaid_date, current_limit
    FROM customer_repayment_limits
    WHERE status = 'enabled'
      AND cust_id IN (SELECT cust_id FROM reassessment)
),

repayment_limit_raw AS (
    SELECT
        r.cust_id,
        CASE
            WHEN b.category = 'Referral'
                THEN LEAST(COALESCE(cl.cur_limit,0), COALESCE(cr.current_limit,0), 400000)
            ELSE LEAST(COALESCE(cl.cur_limit,0), COALESCE(cr.current_limit,0))
        END AS raw_limit
    FROM reassessment r
    JOIN current_limit cl ON cl.cust_id = r.cust_id
    JOIN customer_repayment cr ON cr.cust_id = r.cust_id
    JOIN borrowers b ON b.cust_id = r.cust_id
),

repayment_limit_slab AS (
    SELECT
        rl.cust_id,
        COALESCE(MAX(ls.lmt), 70000) AS repayment_based_limit
    FROM repayment_limit_raw rl
    LEFT JOIN limit_slabs ls ON ls.lmt <= rl.raw_limit
    GROUP BY rl.cust_id
),

loan AS (
    SELECT *
    FROM (
        SELECT
            l.cust_id,
            l.loan_doc_id,
            l.loan_principal,
            l.disbursal_date,
            l.due_date,
            l.paid_date,
            CASE WHEN DATEDIFF(l.paid_date, l.due_date) <= 1 THEN 1 ELSE 0 END AS is_ontime,
            ROW_NUMBER() OVER (PARTITION BY l.cust_id ORDER BY l.disbursal_date DESC) rn
        FROM loans l
        JOIN customer_repayment cr ON cr.cust_id = l.cust_id
        WHERE l.disbursal_date > cr.loan_repaid_date
          AND (l.paid_date IS NOT NULL OR l.due_date <= (CURDATE() - INTERVAL 1 DAY))
          AND l.loan_purpose = 'float_advance'
          AND l.status NOT IN ('voided','hold','pending_disbursal','pending_mnl_dsbrsl')
          AND l.product_id NOT IN (
                SELECT id FROM loan_products WHERE product_type = 'float_vending'
          )
    ) t
    WHERE rn <= 5
),

loan_summary AS (
    SELECT
        c.cust_id,
        COUNT(l.cust_id) AS total_loans,
        COALESCE(MIN(l.loan_principal), c.cur_limit) min_loan_principal,
        COALESCE(SUM(is_ontime),0) AS ontime_loans,
        COALESCE(5 - COALESCE(SUM(is_ontime),0),0) AS loans_needed_for_upgrade
    FROM current_limit c
    LEFT JOIN loan l ON l.cust_id = c.cust_id
    GROUP BY c.cust_id, c.cur_limit
),

loan_stats AS (
    SELECT
        l.cust_id,
        COUNT(*) total_loans_all,
        MAX(l.disbursal_date) last_disbursal_date
    FROM loans l
    JOIN reassessment r ON r.cust_id = l.cust_id
    WHERE l.status NOT IN ('voided','hold','pending_disbursal','pending_mnl_dsbrsl')
      AND l.product_id NOT IN (
            SELECT id FROM loan_products WHERE product_type = 'float_vending'
      )
    GROUP BY l.cust_id
),

last_loan AS (
    SELECT
        l.cust_id,
        l.loan_principal last_loan_amount,
        ls.last_disbursal_date
    FROM loans l
    JOIN loan_stats ls
      ON ls.cust_id = l.cust_id
     AND ls.last_disbursal_date = l.disbursal_date
)

SELECT
    b.distributor_code AS `Distributor Code`,
    b.cust_id AS `Customer ID`,
    UPPER(CONCAT_WS(' ', p.first_name, p.middle_name, p.last_name)) AS `Customer Name`,
    p.mobile_num AS `Customer Mobile Number`,
    b.reg_date AS `Registration Date`,
    CASE WHEN b.category = 'Referral' THEN 'Referral' ELSE 'Full KYC' END AS `Category`,
    COALESCE(ls_all.total_loans_all,0) AS `Total Loans`,
    prev_limit AS `Previous Assessed Limit`,
    COALESCE(cl.cur_limit,0) AS `Current Limit`,

    rls.repayment_based_limit AS `Repayment Based Limit`,

    COALESCE(ll.last_loan_amount,0) AS `Last Loan Amount`,
    ll.last_disbursal_date AS `Last Loan Date`,

    CASE
        WHEN ll.last_disbursal_date IS NULL
          OR DATEDIFF(CURDATE(), ll.last_disbursal_date) > 30
        THEN 'Inactive'
        ELSE 'Active'
    END AS `Activity Status`,

    CASE
        WHEN
            CASE
                WHEN b.category = 'Referral'
                    THEN LEAST(COALESCE(cl.cur_limit,0), 400000)
                ELSE COALESCE(cl.cur_limit,0)
            END = rls.repayment_based_limit
        THEN 0
        ELSE ls.loans_needed_for_upgrade
    END AS `Repayment Based Eligibility (Ontime payments required)`,

    cr.loan_repaid_date AS `Last Upgraded Date`,
    UPPER(b.territory) AS `Territory`,
    UPPER(b.district) AS `District`,
    UPPER(b.location) AS `Location`,
    UPPER(CONCAT_WS(' ', rm.first_name, rm.middle_name, rm.last_name)) AS `RM Name`,
    rm.mobile_num AS `RM Mobile Number`

FROM reassessment r
JOIN borrowers b ON b.cust_id = r.cust_id
JOIN persons p ON p.id = b.owner_person_id
JOIN persons rm ON rm.id = b.flow_rel_mgr_id
JOIN current_limit cl ON cl.cust_id = r.cust_id
JOIN customer_repayment cr ON cr.cust_id = r.cust_id
JOIN repayment_limit_slab rls ON rls.cust_id = r.cust_id
LEFT JOIN loan_summary ls ON ls.cust_id = r.cust_id
LEFT JOIN loan_stats ls_all ON ls_all.cust_id = r.cust_id
LEFT JOIN last_loan ll ON ll.cust_id = r.cust_id;