SET @country_code = 'RWA';
SET @loan_purpose = 'float_advance';

WITH loan_performance AS (
    SELECT
        cust_id,
        COUNT(*) AS total_fas,
        SUM(paid_date <= due_date) AS on_time_paid_count
    FROM loans
    WHERE country_code = @country_code
      AND status = 'settled'
      AND loan_purpose = @loan_purpose
    GROUP BY cust_id
),

distributor_cust AS (
    SELECT cust_id
    FROM accounts
    WHERE country_code = @country_code
      AND parent_acc_id IS NOT NULL
      AND cust_id IS NOT NULL
      AND is_primary_acc = TRUE
),

last_fa AS (
    SELECT
        cust_id,
        MAX(id) AS loan_id
    FROM loans
    WHERE country_code = @country_code
      AND loan_purpose = @loan_purpose
      AND status NOT IN ('voided','hold','pending_disbursal','pending_mnl_dsbrsl')
    GROUP BY cust_id
)

SELECT
    b.cust_id                AS 'Customer ID',
    p.full_name              AS 'Customer Name',
    rm.full_name             AS 'RM Name',
    lp.total_fas             AS 'Total Fas',
    b.crnt_fa_limit          AS 'Fa Limit',
    l.loan_principal         AS 'Last Fa Amount',
    b.reg_date               AS 'Registered Date',
    DATE(l.disbursal_date)   AS 'Last Fa Date',
    ai.field_2               AS 'District',
    ai.field_8               AS 'Territory',
    p.mobile_num             AS 'Registered Mobile Num',
    p.alt_biz_mobile_num_1   AS 'Alternate Mobile Num 1',
    p.alt_biz_mobile_num_2   AS 'Alternate Mobile Num 2'

FROM loan_performance lp

JOIN borrowers b
    ON b.cust_id = lp.cust_id

JOIN last_fa lf
    ON lf.cust_id = lp.cust_id

JOIN loans l
    ON l.id = lf.loan_id

LEFT JOIN persons rm
    ON rm.id = b.flow_rel_mgr_id

LEFT JOIN persons p
    ON p.id = b.owner_person_id

LEFT JOIN address_info ai
    ON ai.id = b.owner_address_id

WHERE b.country_code = @country_code
  AND lp.total_fas > 12
  AND (lp.on_time_paid_count / lp.total_fas) >= 0.97
  AND DATEDIFF(CURDATE(), l.disbursal_date) > 30
  AND NOT EXISTS (
        SELECT 1
        FROM distributor_cust dc
        WHERE dc.cust_id = b.cust_id
  )

ORDER BY lp.total_fas DESC;


-- Distributor cust list

SET @country_code = 'RWA';
SET @loan_purpose = 'float_advance';

WITH loan_performance AS (
    SELECT
        cust_id,
        COUNT(*) AS total_fas,
        SUM(paid_date <= due_date) AS on_time_paid_count
    FROM loans
    WHERE country_code = @country_code
      AND status = 'settled'
      AND loan_purpose = @loan_purpose
    GROUP BY cust_id
),

distributor_cust AS (
    SELECT 
        cust_id,
        distributor_code,
    FROM accounts
    WHERE country_code = @country_code
      AND parent_acc_id IS NOT NULL
      AND cust_id IS NOT NULL
      AND is_primary_acc = TRUE
),

last_fa AS (
    SELECT
        cust_id,
        MAX(id) AS loan_id
    FROM loans
    WHERE country_code = @country_code
      AND loan_purpose = @loan_purpose
      AND status NOT IN ('voided','hold','pending_disbursal','pending_mnl_dsbrsl')
    GROUP BY cust_id
)

SELECT
    b.cust_id                AS 'Customer ID',
    p.full_name              AS 'Customer Name',
    rm.full_name             AS 'RM Name',
    dc.distributor_code      AS 'Distributor Code'
    lp.total_fas             AS 'Total Fas',
    b.crnt_fa_limit          AS 'Fa Limit',
    l.loan_principal         AS 'Last Fa Amount',
    b.reg_date               AS 'Registered Date',
    DATE(l.disbursal_date)   AS 'Last Fa Date',
    ai.field_2               AS 'District',
    ai.field_8               AS 'Territory',
    p.mobile_num             AS 'Registered Mobile Num',
    p.alt_biz_mobile_num_1   AS 'Alternate Mobile Num 1',
    p.alt_biz_mobile_num_2   AS 'Alternate Mobile Num 2'

FROM loan_performance lp

JOIN borrowers b
    ON b.cust_id = lp.cust_id

JOIN distributor_cust dc
    ON dc.cust_id = b.cust_id

JOIN last_fa lf
    ON lf.cust_id = lp.cust_id

JOIN loans l
    ON l.id = lf.loan_id

LEFT JOIN persons rm
    ON rm.id = b.flow_rel_mgr_id

LEFT JOIN persons p
    ON p.id = b.owner_person_id

LEFT JOIN address_info ai
    ON ai.id = b.owner_address_id

WHERE b.country_code = @country_code
  AND lp.total_fas >= 1
  AND DATEDIFF(CURDATE(), l.disbursal_date) > 30

ORDER BY lp.total_fas DESC;