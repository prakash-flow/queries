SET @country_code = 'UGA';
SET @month = '202604';

SET @pre_month = (
  SELECT DATE_FORMAT(
    DATE_SUB(STR_TO_DATE(CONCAT(@month, '01'), '%Y%m%d'), INTERVAL 1 MONTH),
    '%Y%m'
  )
);

-- Start / End of month
SET @start_date = STR_TO_DATE(CONCAT(@month, '01 00:00:00'), '%Y%m%d %H:%i:%s');
SET @last_day = CONCAT(LAST_DAY(STR_TO_DATE(CONCAT(@month, '01'), '%Y%m%d')), ' 23:59:59');

-- Realization dates
SET @realization_date = (
  SELECT COALESCE(
    (SELECT closure_date
     FROM closure_date_records
     WHERE month = @month AND status = 'enabled' AND country_code = @country_code
     LIMIT 1),
    NOW()
  )
);

SET @pre_realization_date = (
  SELECT closure_date
  FROM closure_date_records
  WHERE month = @pre_month AND status = 'enabled' AND country_code = @country_code
  LIMIT 1
);

WITH revenue AS (
    SELECT 
        l.sales_doc_id,
        (SUM(IF(t.txn_type = 'float_in', t.amount, 0)) - 
        SUM(IF(t.txn_type = 'float_out', IF(l.prvdr_charges > 0, t.amount + l.prvdr_charges, t.amount), 0))
        ) AS sw_revenue
    FROM sales l
    JOIN sales_txns t
      ON l.sales_doc_id = t.sales_doc_id
    WHERE l.country_code = @country_code
      AND l.status = 'delivered'
      AND (
            (t.txn_date BETWEEN @start_date AND @last_day AND t.realization_date <= @realization_date)
         OR (t.txn_date < @start_date AND t.realization_date > @pre_realization_date AND t.realization_date <= @realization_date)
      )
    GROUP BY l.sales_doc_id
),
raw AS (
    SELECT 
        a.id,
        a.loan_doc_id,
        a.stmt_txn_id,
        a.stmt_txn_date,
        a.realization_date,
        a.acc_txn_type,
        a.cr_amt,
        a.dr_amt,
        a.account_id,
        a.acc_prvdr_code,
        a.acc_number
    FROM account_stmts a
    WHERE a.country_code = @country_code
      AND (
            (a.stmt_txn_date BETWEEN @start_date AND @last_day AND a.realization_date <= @realization_date)
         OR (a.stmt_txn_date < @start_date AND a.realization_date > @pre_realization_date AND a.realization_date <= @realization_date)
      )
      AND a.acc_txn_type IN (
          'float_in','duplicate_float_out_reversal','float_out',
          'wrong_switch','wrong_switch_reversal',
          'float_in_reversed','float_in_refunded',
          'duplicate_float_in_refunded','duplicate_float_out',
          'wrong_float_in'
      )
),
temp AS (
    SELECT 
        ra.loan_doc_id,
        ra.id,
        ra.stmt_txn_id,
        ra.stmt_txn_date,
        ra.realization_date,
        ra.acc_txn_type,
        ra.cr_amt,
        ra.dr_amt,
        ra.account_id,
        ra.acc_prvdr_code,
        ra.acc_number,
        ABS(COALESCE(if(ra.acc_txn_type = 'float_out',fee.sw_revenue,0), 0)) AS sw_revenue
    FROM raw ra
    LEFT JOIN revenue fee 
      ON ra.loan_doc_id = fee.sales_doc_id
),
temp_agg AS (
    SELECT 
        loan_doc_id,
        SUM(cr_amt) AS credit,
        SUM(dr_amt) AS debit,
        MAX(sw_revenue) AS rev,
        SUM(cr_amt) - SUM(dr_amt) - MAX(sw_revenue) AS suspense
    FROM temp
    GROUP BY loan_doc_id
)
SELECT t.*,suspense
FROM temp t
JOIN temp_agg ta 
  ON t.loan_doc_id = ta.loan_doc_id
WHERE ta.suspense != 0;

