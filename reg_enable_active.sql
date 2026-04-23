    SET @month = 202603;
    SET @country_code = 'UGA';
    SET @last_day = LAST_DAY(DATE(CONCAT(@month, '01')));

    WITH disabled_cust AS (
        SELECT DISTINCT
            r1.record_code AS cust_id
        FROM
            record_audits r1
        JOIN (
            SELECT
                record_code,
                MAX(id) AS id
            FROM
                record_audits
            WHERE
                DATE(created_at) <= @last_day
                AND country_code = @country_code
            GROUP BY
                record_code
        ) r2 ON r1.id = r2.id
        WHERE
            JSON_EXTRACT(r1.data_after, '$.status') = 'disabled'
    ),

    active_cust AS (
        SELECT DISTINCT
            l.cust_id
        FROM
            loans l
        JOIN
            loan_txns t ON l.loan_doc_id = t.loan_doc_id
        LEFT JOIN
            disabled_cust d ON l.cust_id = d.cust_id
        WHERE
            DATEDIFF(@last_day, t.txn_date) <= 30
            AND DATE(t.txn_date) <= @last_day
            AND l.country_code = @country_code
            AND t.txn_type = 'disbursal'
            AND l.product_id NOT IN (43, 75, 300)
            AND l.status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
            AND d.cust_id IS NULL
    ),

    reg_cust AS (
        SELECT DISTINCT
            b.cust_id
        FROM
            borrowers b
        WHERE
            b.reg_date <= @last_day
            AND b.country_code = @country_code

    ),

    enabled_cust AS (
        SELECT DISTINCT
            b.cust_id
        FROM
            borrowers b
        LEFT JOIN
            disabled_cust d ON b.cust_id = d.cust_id
        WHERE
            b.reg_date <= @last_day
            AND b.country_code = @country_code
            AND d.cust_id IS NULL
    ),

    inactive_cust AS (
        SELECT
            l.cust_id
        FROM
            loans l
        -- The customer must exist in the audit records
        JOIN
            record_audits ra ON l.cust_id = ra.record_code
        LEFT JOIN
            disabled_cust d ON l.cust_id = d.cust_id
        -- Left join on recent disbursal transactions
        LEFT JOIN
            loan_txns t ON l.loan_doc_id = t.loan_doc_id
            AND DATEDIFF(@last_day, t.txn_date) <= 30
            AND DATE(t.txn_date) <= @last_day
            AND t.txn_type = 'disbursal'
        WHERE
            l.country_code = @country_code
            AND l.product_id NOT IN (43, 75, 300)
            AND l.status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
            -- Guarantee they exist in the audits valid for this period
            AND ra.country_code = @country_code
            AND DATE(ra.created_at) <= @last_day
            AND d.cust_id IS NULL
        GROUP BY
            l.cust_id
        -- Guarantee they have EXACTLY 0 disbursal transactions matching the criteria
        HAVING
            COUNT(t.id) = 0
    )

    SELECT
        l.loan_purpose,
        COUNT(DISTINCT r.cust_id) AS `Reg Customers`,
        COUNT(DISTINCT a.cust_id) AS `Active Customers`,
        COUNT(DISTINCT e.cust_id) AS `Enabled Customers`,
        COUNT(DISTINCT i.cust_id) AS `Inactive Customers`

    FROM
        borrowers b
    JOIN loans l ON b.cust_id = l.cust_id
    LEFT JOIN
        reg_cust r ON b.cust_id = r.cust_id
    LEFT JOIN
        enabled_cust e ON b.cust_id = e.cust_id
    LEFT JOIN
        active_cust a ON b.cust_id = a.cust_id
    LEFT JOIN
        inactive_cust i ON b.cust_id = i.cust_id

    WHERE
        b.reg_date <= @last_day
        AND l.country_code = @country_code
        AND b.country_code = @country_code
        AND l.product_id NOT IN (43, 75, 300)
        AND l.status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
    group by l.loan_purpose