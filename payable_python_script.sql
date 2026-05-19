SET @month = 202501;
    SET @country_code = 'UGA';

    SET @last_day = CONCAT(
        LAST_DAY(DATE(CONCAT(@month, '01'))),
        ' 23:59:59'
    );

    SET @prev_month_last_str = LAST_DAY(
        DATE_SUB(DATE(CONCAT(@month, '01')), INTERVAL 1 MONTH)
    );

    SET @closure_date = (
        SELECT closure_date
        FROM flow_api.closure_date_records
        WHERE status = 'enabled'
        AND month = @month
        AND country_code = @country_code
    );

    WITH disbursals AS (
        SELECT
            l.id entity_id,
            @last_day `As of`,
            UPPER(l.entity_type) `Source`,
            l.cust_id `Customer ID`,
            l.entity_id `Loan ID`,
            a.stmt_txn_id `Txn ID`,
            DATE(a.stmt_txn_date) `Txn Date`,
            DATEDIFF(DATE(@last_day), DATE(a.stmt_txn_date)) `PAR days`,
            l.obligation_amount `Excess Received`,
            IF(lw.write_off_date IS NOT NULL, 1, 0) `Is Written Off`,
            lw.write_off_date `Write Off Date`,
            l.os_amount `OS Amount`
        FROM financial_obligations l
        LEFT JOIN account_stmts a
            ON a.id = l.account_stmt_id
        LEFT JOIN financial_obligations_write_off lw
            ON lw.stmt_txn_id = l.stmt_txn_id
        AND lw.country_code = l.country_code
        AND EXTRACT(YEAR_MONTH FROM lw.write_off_date) = @month
        WHERE l.obligation_category IN ('payable')
        AND l.country_code = @country_code
        AND a.stmt_txn_date <= @last_day
        AND a.realization_date <= @closure_date
        AND l.id NOT IN (
                SELECT financial_obligation_id
                FROM financial_obligations_write_off
                WHERE write_off_date <= @prev_month_last_str
        )
    ),

    payments AS (
        SELECT
            l.entity_id,
            SUM(l.allocated_amount) recovered,
            SUM(l.principal_amount) reversal,
            SUM(l.excess_amount) excess
        FROM payment_allocation_items l
        LEFT JOIN account_stmts a
            ON a.id = l.account_stmt_id
        WHERE l.entity_type = 'financial_obligation'
        AND a.country_code = @country_code
        AND a.stmt_txn_date <= @last_day
        AND a.realization_date <= @closure_date
        GROUP BY l.entity_id
    ),

    parsedLoans AS (
        SELECT
            pri.`As of`,
            pri.`Source`,
            pri.`Customer ID`,
            pri.`Loan ID`,
            pri.`Txn ID`,
            pri.`Txn Date`,
            pri.`PAR days`,
            pri.`Excess Received`,
            IFNULL(pp.recovered, 0) `Recovered Amount`,
            IFNULL(pp.reversal, 0) `Reversal Amount`,
            IFNULL(pp.excess, 0) `Excess Amount`,
            (
                pri.`Excess Received`
                - IFNULL(pp.reversal, 0)
            ) `OS amount`,
            pri.`Is Written Off`,
            pri.`Write Off Date`
        FROM disbursals pri
        LEFT JOIN payments pp
            ON pri.entity_id = pp.entity_id
    )

    SELECT 
    SUM(`OS amount`) `OS amount`,
    SUM(CASE WHEN `Is Written Off` = 1 THEN `OS amount` END) `Written Off`
    FROM parsedLoans WHERE `OS amount` > 0;

    -- SELECT *
    -- FROM parsedLoans
    -- HAVING `OS amount` > 0
    -- ORDER BY `PAR days` DESC;