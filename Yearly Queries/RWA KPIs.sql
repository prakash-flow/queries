-- Customer Base
SET @month = 202501;
SET @country_code = 'UGA';

SET @prev_month = DATE_FORMAT(DATE_SUB(DATE(CONCAT(@month, '01')), INTERVAL 1 MONTH), '%Y%m');
SET @last_day = LAST_DAY(DATE(CONCAT(@month, '01')));

SET @closure_date = (
    SELECT closure_date 
    FROM flow_api.closure_date_records 
    WHERE status = 'enabled' 
      AND month = @month 
      AND country_code = @country_code
);

SET @prev_closure_date = (
    SELECT closure_date 
    FROM flow_api.closure_date_records 
    WHERE status = 'enabled' 
      AND month = @prev_month 
      AND country_code = @country_code
);

SELECT @month, @prev_month, @last_day, @closure_date, @prev_closure_date;

WITH active_cust AS (
    SELECT 
        loan_purpose,
        COUNT(DISTINCT l.cust_id) cust_id
    FROM
        loans l
    JOIN
        loan_txns t ON l.loan_doc_id = t.loan_doc_id
    LEFT JOIN (
        SELECT DISTINCT
            r1.record_code
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
            GROUP BY
                record_code
        ) r2 ON r1.id = r2.id
        WHERE
            JSON_EXTRACT(r1.data_after, '$.status') = 'disabled'
    ) disabled_cust ON l.cust_id = disabled_cust.record_code
    WHERE
        DATEDIFF(@last_day, t.txn_date) <= 30
        AND DATE(t.txn_date) <= @last_day
        AND l.country_code = @country_code
        AND t.txn_type = 'disbursal'
        AND l.product_id NOT IN (43, 75, 300)
        AND l.status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
        AND disabled_cust.record_code IS NULL
    group by loan_purpose
)
select * from active_cust;

-- Disbursement

SET @month = 202501;
SET @country_code = 'UGA';

SET @prev_month = DATE_FORMAT(DATE_SUB(DATE(CONCAT(@month, '01')), INTERVAL 1 MONTH), '%Y%m');
SET @last_day = LAST_DAY(DATE(CONCAT(@month, '01')));

SET @closure_date = (
    SELECT closure_date 
    FROM flow_api.closure_date_records 
    WHERE status = 'enabled' 
      AND month = @month 
      AND country_code = @country_code
);

SET @prev_closure_date = (
    SELECT closure_date 
    FROM flow_api.closure_date_records 
    WHERE status = 'enabled' 
      AND month = @prev_month 
      AND country_code = @country_code
);


SELECT
    loan_purpose,
    COUNT(1) loan_count,
    COUNT(DISTINCT cust_id) customer_count,
    SUM(loan_principal) disbursal_amount,
    MIN(loan_principal) min_loan_principal,
    MAX(loan_principal) max_loan_principal
FROM loans l
JOIN loan_txns t 
    ON l.loan_doc_id = t.loan_doc_id
WHERE 
    l.status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
    AND l.product_id NOT IN (43, 75, 300)
    AND t.txn_type = 'disbursal'
    AND (
        (EXTRACT(YEAR_MONTH FROM t.txn_date) = @month 
            AND t.realization_date <= @closure_date)
        OR 
        (EXTRACT(YEAR_MONTH FROM t.txn_date) < @month 
            AND t.realization_date > @prev_closure_date 
            AND t.realization_date <= @closure_date)
    )
    AND l.country_code = @country_code
GROUP by 
    loan_purpose

-- revenue

SET @month = 202502;
SET @country_code = 'UGA';

SELECT IF(@country_code = 'UGA', 'UGX', 'RWF') INTO @currency;

SET @prev_month = DATE_FORMAT(DATE_SUB(DATE(CONCAT(@month, '01')), INTERVAL 1 MONTH), '%Y%m');
SET @last_day = LAST_DAY(DATE(CONCAT(@month, '01')));

SET @closure_date = (
    SELECT closure_date 
    FROM flow_api.closure_date_records 
    WHERE status = 'enabled' 
      AND month = @month 
      AND country_code = @country_code
);

SET @prev_closure_date = (
    SELECT closure_date 
    FROM flow_api.closure_date_records 
    WHERE status = 'enabled' 
      AND month = @prev_month 
      AND country_code = @country_code
);

SELECT @currency, @month, @prev_month, @last_day, @closure_date, @prev_closure_date;


SELECT
		l.loan_purpose,
        COUNT(DISTINCT l.cust_id) customer_count,
        SUM(
            CASE 
                WHEN w.loan_doc_id IS NULL THEN IFNULL(t.fee, 0) + IFNULL(t.penalty, 0)
                ELSE 0
            END
        ) +
        SUM(
            CASE 
                WHEN w.loan_doc_id IS NOT NULL AND DATE(txn_date) > write_off_date THEN IFNULL(t.amount, 0)
                WHEN w.loan_doc_id IS NOT NULL AND DATE(txn_date) <= write_off_date THEN IFNULL(t.fee, 0) + IFNULL(t.penalty, 0)
                ELSE 0
            END
        ) AS revenue
    FROM 
        loans l
    JOIN 
        loan_txns t ON l.loan_doc_id = t.loan_doc_id
    LEFT JOIN 
        loan_write_off w ON l.loan_doc_id = w.loan_doc_id AND DATE(w.write_off_date) <= @last_day
    WHERE 
        l.status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
        AND l.product_id NOT IN (43, 75, 300)
        AND t.txn_type = 'payment'
        AND (
            (EXTRACT(YEAR_MONTH FROM t.txn_date) = @month AND t.realization_date <= @closure_date)
            OR 
            (EXTRACT(YEAR_MONTH FROM t.txn_date) < @month AND t.realization_date > @prev_closure_date AND t.realization_date <= @closure_date)
        )
        AND l.country_code = @country_code
    GROUP BY l.loan_purpose;


-- Ontime Repayment
SELECT 
    loan_purpose,
                  COUNT(id) due_loans_in_month, 
                  COUNT(
                    CASE WHEN DATE(paid_date) <= DATE_ADD(due_date, INTERVAL 1 DAY) THEN loan_doc_id END
                  ) ontime_repaid_loans_in_month, 
                FROM 
                  loans 
                WHERE 
                  DATE(due_date) BETWEEN '2025-01-01'
                  AND '2025-01-31'
                  AND country_code = 'UGA' 
                    AND status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
        AND product_id NOT IN (43, 75, 300) group by loan_purpose


-- par count 
SET @month = '202510';
SET @country_code = 'UGA';

SET @last_day = LAST_DAY(DATE(CONCAT(@month, "01")));
SET @realization_date = (
    SELECT closure_date 
    FROM closure_date_records 
    WHERE country_code = @country_code 
      AND month = @month 
      AND status = 'enabled'
);

SELECT @month, @country_code, @last_day, @realization_date;

WITH loan_principal AS (
    SELECT 
        l.loan_doc_id,
        l.loan_purpose,
        l.loan_principal,
        l.flow_fee,
        l.due_date
    FROM loans l
    JOIN loan_txns lt ON lt.loan_doc_id = l.loan_doc_id
    WHERE lt.txn_type = 'disbursal'
      AND lt.realization_date <= @realization_date
      AND l.country_code = @country_code
      AND DATE(l.disbursal_date) <= @last_day
      AND l.product_id NOT IN (43, 75, 300)
      AND l.status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
      AND l.loan_doc_id NOT IN (
            SELECT loan_doc_id 
            FROM loan_write_off 
            WHERE write_off_date <= @last_day 
              AND write_off_status IN ('approved', 'partially_recovered', 'recovered') 
              AND country_code = @country_code
      )
    GROUP BY l.loan_doc_id, l.loan_purpose
),

loan_payments AS (
    SELECT 
        loan_doc_id,
        SUM(CASE WHEN txn_type = 'payment' THEN principal ELSE 0 END) AS total_paid_principal,
        SUM(CASE WHEN txn_type = 'payment' THEN fee ELSE 0 END) AS total_paid_fee
    FROM loan_txns
    WHERE DATE(txn_date) <= @last_day
      AND realization_date <= @realization_date
    GROUP BY loan_doc_id
),

loan_os AS (
    SELECT
        lp.loan_doc_id,
        lp.loan_purpose,
        lp.loan_principal,
        lp.flow_fee,
        lp.due_date,
        COALESCE(p.total_paid_principal, 0) AS paid_principal,
        COALESCE(p.total_paid_fee, 0) AS paid_fee,
        GREATEST(lp.loan_principal - COALESCE(p.total_paid_principal, 0), 0) AS os_principal,
        GREATEST(lp.flow_fee - COALESCE(p.total_paid_fee, 0), 0) AS os_fee
    FROM loan_principal lp
    LEFT JOIN loan_payments p ON p.loan_doc_id = lp.loan_doc_id
)

SELECT * FROM (
    -- PRINCIPAL ROWS
    SELECT
        loan_purpose,
        'principal' AS type,
        SUM(CASE WHEN os_principal > 0 THEN 1 ELSE 0 END) AS os_count,
        SUM(os_principal) AS total_os_amount,
        SUM(IF(DATEDIFF(@last_day, due_date) > 1,  os_principal, 0)) AS par_1,
        SUM(IF(DATEDIFF(@last_day, due_date) > 5,  os_principal, 0)) AS par_5,
        SUM(IF(DATEDIFF(@last_day, due_date) > 10, os_principal, 0)) AS par_10,
        SUM(IF(DATEDIFF(@last_day, due_date) > 15, os_principal, 0)) AS par_15,
        SUM(IF(DATEDIFF(@last_day, due_date) > 30, os_principal, 0)) AS par_30,
        SUM(IF(DATEDIFF(@last_day, due_date) > 60, os_principal, 0)) AS par_60,
        SUM(IF(DATEDIFF(@last_day, due_date) > 90, os_principal, 0)) AS par_90,
        SUM(IF(DATEDIFF(@last_day, due_date) > 120,os_principal, 0)) AS par_120,
        SUM(IF(DATEDIFF(@last_day, due_date) > 180,os_principal, 0)) AS par_180,
        SUM(IF(DATEDIFF(@last_day, due_date) > 270,os_principal, 0)) AS par_270,
        SUM(IF(DATEDIFF(@last_day, due_date) > 360,os_principal, 0)) AS par_360
    FROM loan_os
    GROUP BY loan_purpose
) t
ORDER BY loan_purpose;


-- write_off_count
select loan_purpose, sum(write_off_amount) write_off_amount from loan_write_off lw left join loans l on l.loan_doc_id = lw.loan_doc_id  where l.country_code = 'UGA' and extract(year_month from write_off_date) = 202501 group by loan_purpose;

SET @month = '202510';
SET @country_code = 'UGA';

SET @last_day = LAST_DAY(DATE(CONCAT(@month, "01")));
SET @realization_date = (
    SELECT closure_date 
    FROM closure_date_records 
    WHERE country_code = @country_code 
      AND month = @month 
      AND status = 'enabled'
);

SELECT @month, @country_code, @last_day, @realization_date;

WITH loan_principal AS (
    SELECT 
        l.loan_doc_id,
        l.loan_purpose,
        l.loan_principal,
        l.flow_fee,
        l.due_date
    FROM loans l
    JOIN loan_txns lt ON lt.loan_doc_id = l.loan_doc_id
    WHERE lt.txn_type = 'disbursal'
      AND lt.realization_date <= @realization_date
      AND l.country_code = @country_code
      AND DATE(l.disbursal_date) <= @last_day
      AND l.product_id NOT IN (43, 75, 300)
      AND l.status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
      AND l.loan_doc_id NOT IN (
            SELECT loan_doc_id 
            FROM loan_write_off 
            WHERE write_off_date < @last_day 
              AND write_off_status IN ('approved', 'partially_recovered', 'recovered') 
              AND country_code = @country_code
      )
    GROUP BY l.loan_doc_id, l.loan_purpose
),

loan_payments AS (
    SELECT 
        loan_doc_id,
        SUM(CASE WHEN txn_type = 'payment' THEN principal ELSE 0 END) AS total_paid_principal,
        SUM(CASE WHEN txn_type = 'payment' THEN fee ELSE 0 END) AS total_paid_fee
    FROM loan_txns
    WHERE DATE(txn_date) <= @last_day
      AND realization_date <= @realization_date
    GROUP BY loan_doc_id
),

loan_os AS (
    SELECT
        lp.loan_doc_id,
        lp.loan_purpose,
        lp.loan_principal,
        lp.flow_fee,
        lp.due_date,
        COALESCE(p.total_paid_principal, 0) AS paid_principal,
        COALESCE(p.total_paid_fee, 0) AS paid_fee,
        GREATEST(lp.loan_principal - COALESCE(p.total_paid_principal, 0), 0) AS os_principal,
        GREATEST(lp.flow_fee - COALESCE(p.total_paid_fee, 0), 0) AS os_fee
    FROM loan_principal lp
    LEFT JOIN loan_payments p ON p.loan_doc_id = lp.loan_doc_id
)

SELECT * FROM (
    SELECT
        loan_purpose,
        SUM(os_principal) AS total_os_amount,
    FROM loan_os
    GROUP BY loan_purpose
) t
ORDER BY loan_purpose;