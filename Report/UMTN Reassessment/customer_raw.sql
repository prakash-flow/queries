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

customer_base AS (
    SELECT
        b.cust_id,
        b.crnt_fa_limit,
        b.tot_loans,
        b.reg_date,
        b.last_assessment_date,

        -- Customer name
        p.full_name AS customer_name,

        -- RM name
        rm.full_name AS rm_name,

        -- Address
        ai.field_1 AS region,
        ai.field_2 AS district

    FROM borrowers b
    INNER JOIN base_customers bc
        ON bc.cust_id = b.cust_id

    LEFT JOIN persons p
        ON p.id = b.owner_person_id

    LEFT JOIN persons rm
        ON rm.id = b.flow_rel_mgr_id

    LEFT JOIN address_info ai
        ON ai.id = b.owner_address_id
    WHERE b.category NOT IN ('Referral', 'float_switch')
),

loan_summary AS (
    SELECT
        l.cust_id,

        MAX(l.loan_principal) AS max_loan_principal,

        -- Loans taken in last 1 / 3 / 6 months
        SUM(CASE
                WHEN l.disbursal_date >= DATE_SUB(CURDATE(), INTERVAL 1 MONTH)
                THEN 1 ELSE 0
            END) AS loan_last_1_month,

        SUM(CASE
                WHEN l.disbursal_date >= DATE_SUB(CURDATE(), INTERVAL 3 MONTH)
                THEN 1 ELSE 0
            END) AS loan_last_3_months,

        SUM(CASE
                WHEN l.disbursal_date >= DATE_SUB(CURDATE(), INTERVAL 6 MONTH)
                THEN 1 ELSE 0
            END) AS loan_last_6_months,
        SUM(CASE
                WHEN l.disbursal_date >= DATE_SUB(CURDATE(), INTERVAL 12 MONTH)
                THEN 1 ELSE 0
            END) AS loan_last_12_months

    FROM loans l
    INNER JOIN base_customers bc
        ON bc.cust_id = l.cust_id
    WHERE l.status NOT IN ('voided', 'hold', 'pending_disbursal','pending_mnl_dsbrsl')
    AND loan_purpose not in ('asset_financing', 'growth_financing')
    GROUP BY l.cust_id
),

loan_app_summary AS (
    SELECT
        la.cust_id,
        MAX(la.loan_appl_date) AS max_loan_appl_date
    FROM loan_applications la
    INNER JOIN base_customers bc
        ON bc.cust_id = la.cust_id
    WHERE status = 'approved'
    GROUP BY la.cust_id
)

SELECT
    cb.cust_id,
    cb.customer_name,
    cb.rm_name,
    cb.region,
    cb.district,
    cb.crnt_fa_limit,
    cb.tot_loans,
    cb.last_assessment_date,
    cb.reg_date,

    IFNULL(ls.max_loan_principal, 0) AS max_loan_principal,
    IFNULL(ls.loan_last_1_month, 0) AS loan_last_1_month,
    IFNULL(ls.loan_last_3_months, 0) AS loan_last_3_months,
    IFNULL(ls.loan_last_6_months, 0) AS loan_last_6_months,
    IFNULL(ls.loan_last_12_months, 0) AS loan_last_12_months,

    DATE(las.max_loan_appl_date) max_loan_appl_date

FROM customer_base cb
LEFT JOIN loan_summary ls
    ON ls.cust_id = cb.cust_id
LEFT JOIN loan_app_summary las
    ON las.cust_id = cb.cust_id;