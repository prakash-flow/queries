SET @country_code = 'UGA';
SET @month = '202504';

SET @prev_month = (
    SELECT DATE_FORMAT(
        DATE_SUB(STR_TO_DATE(CONCAT(@month, '01'), '%Y%m%d'), INTERVAL 1 MONTH),
        '%Y%m'
    )
);
SET @start_date = DATE(CONCAT(@month, '01'));
SET @last_day = LAST_DAY(@start_date);
SET @realization_date = IFNULL(
    (
        SELECT closure_date
        FROM closure_date_records
        WHERE month = @month 
          AND status = 'enabled' 
          AND country_code = @country_code
    ),
    NOW()
);
SET @pre_realization_date = (
    SELECT closure_date
    FROM closure_date_records
    WHERE month = @prev_month 
      AND status = 'enabled' 
      AND country_code = @country_code
);

WITH received_fee AS (
    SELECT l.loan_doc_id, l.loan_purpose, SUM(t.fee) AS fees
    FROM loans l 
    JOIN loan_txns t ON l.loan_doc_id = t.loan_doc_id  
    WHERE l.status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')   
      AND l.product_id NOT IN (43, 75, 300) 
      AND t.txn_type = 'payment'
      AND (
        (DATE(txn_date) BETWEEN @start_date AND @last_day AND realization_date <= @realization_date)
        OR 
        (DATE(txn_date) < @start_date AND realization_date > @pre_realization_date AND realization_date <= @realization_date)
      )
      AND l.country_code = @country_code
      AND t.fee IS NOT NULL AND t.fee != 0
      AND l.loan_doc_id NOT IN (
          SELECT loan_doc_id 
          FROM loan_write_off
          WHERE DATE(write_off_date) < @last_day
            AND country_code = @country_code
      )
    GROUP BY l.loan_doc_id, l.loan_purpose
),
current_generated_rcvd_fee AS (
    SELECT l.loan_doc_id, l.loan_purpose, l.flow_fee AS feess
    FROM loans l 
    JOIN loan_txns t ON l.loan_doc_id = t.loan_doc_id  
    WHERE l.status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')   
      AND l.product_id NOT IN (43, 75, 300) 
      AND t.txn_type = 'disbursal'
      AND (
        (DATE(txn_date) BETWEEN @start_date AND @last_day AND realization_date <= @realization_date)
        OR 
        (DATE(txn_date) < @start_date AND realization_date > @pre_realization_date AND realization_date <= @realization_date)
      )
      AND l.country_code = @country_code
      AND l.loan_doc_id NOT IN (
          SELECT loan_doc_id 
          FROM loan_write_off
          WHERE DATE(write_off_date) < @last_day
            AND country_code = @country_code
      )
    GROUP BY l.loan_doc_id, l.loan_purpose
),
open_loans_fee AS (
    SELECT 
        @last_day AS date,
        rf.loan_purpose,
        COUNT(rf.loan_doc_id) AS total_loans,
        SUM(rf.fees) AS total_fees,
        SUM(CASE WHEN ol.loan_doc_id IS NULL THEN rf.fees ELSE 0 END) AS old_fees,
        SUM(CASE WHEN ol.loan_doc_id IS NOT NULL THEN rf.fees ELSE 0 END) AS current_generated_fees
    FROM received_fee rf
    LEFT JOIN current_generated_rcvd_fee ol 
        ON ol.loan_doc_id = rf.loan_doc_id 
       AND ol.loan_purpose = rf.loan_purpose
    GROUP BY rf.loan_purpose
),
written_off_loans_fee AS (
    SELECT 
        @last_day AS date,
        l.loan_purpose,
        COUNT(DISTINCT l.loan_doc_id) AS written_off_fee_received_loans,
        SUM(t.fee) AS written_off_fee_received
    FROM loans l 
    JOIN loan_txns t ON l.loan_doc_id = t.loan_doc_id  
    WHERE l.status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')   
      AND l.product_id NOT IN (43, 75, 300) 
      AND t.txn_type = 'payment'
      AND (
        (DATE(txn_date) BETWEEN @start_date AND @last_day AND realization_date <= @realization_date)
        OR 
        (DATE(txn_date) < @start_date AND realization_date > @pre_realization_date AND realization_date <= @realization_date)
      )
      AND l.country_code = @country_code
      AND t.fee IS NOT NULL AND t.fee != 0
      AND l.loan_doc_id IN (
          SELECT loan_doc_id 
          FROM loan_write_off
          WHERE DATE(write_off_date) < @last_day
            AND country_code = @country_code
      )
    GROUP BY l.loan_purpose
),
fee_generate AS (
    SELECT 
        l.loan_purpose,
        COUNT(l.loan_doc_id) AS count,
        SUM(l.flow_fee) AS expected_flow_fee
    FROM loans l
    JOIN loan_txns t ON l.loan_doc_id = t.loan_doc_id
    WHERE l.status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
      AND l.product_id NOT IN (43,75,300)
      AND t.txn_type = 'disbursal'
      AND (
          (DATE(t.txn_date) BETWEEN @start_date AND @last_day AND t.realization_date <= @realization_date)
          OR 
          (DATE(t.txn_date) < @start_date AND t.realization_date > @pre_realization_date AND t.realization_date <= @realization_date)
      )
      AND l.country_code = @country_code 
    GROUP BY l.loan_purpose
)

SELECT 
    @month AS `Month`,
    f.loan_purpose AS `Loan Purpose`,
    fg.count AS `FAs with Fee Generated`,
    fg.expected_flow_fee `Value of Fee Generated`,
    total_loans AS `FAs with Fee Received`,
    total_fees AS `Value of Fee Received`,
    old_fees AS `Value of Previously Generated Fee Received`,
    current_generated_fees `Value of Currently Generated Fee Received`,
    w.written_off_fee_received_loans `FAs with Recovered Fee`,
    w.written_off_fee_received `Value of Recovered Fee`
FROM open_loans_fee f
LEFT JOIN written_off_loans_fee w ON f.loan_purpose = w.loan_purpose
LEFT JOIN fee_generate fg ON fg.loan_purpose = f.loan_purpose;