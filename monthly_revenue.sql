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
        SUM(
            CASE 
                WHEN w.loan_doc_id IS NULL THEN IFNULL(t.fee, 0) + IFNULL(t.penalty, 0)
                ELSE 0
            END
        ) +
        SUM(
            CASE 
                WHEN w.loan_doc_id IS NOT NULL THEN IFNULL(t.amount, 0)
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