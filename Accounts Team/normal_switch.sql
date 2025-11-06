-- CROSS CHECK
-- DR Amount - SUM(DR-float_out, DR-float_in_reversed) in Account Report
-- CR Amount - SUM(CR-float_in, CR-float_in(incomplete)) in Account Report

SET @month = '202510';
SET @country_code = 'UGA';

SET @month_date = DATE(CONCAT(@month, '01'));
SET @start_date = CONCAT(@month_date, ' 00:00:00');
SET @end_date   = CONCAT(LAST_DAY(@month_date), ' 23:59:59');

SET @closure_date = (
    SELECT closure_date
    FROM closure_date_records
    WHERE country_code = @country_code
      AND status = 'enabled'
      AND month = @month
);

SET @prev_closure_date = (
    SELECT closure_date
    FROM closure_date_records
    WHERE country_code = @country_code
      AND status = 'enabled'
      AND month = DATE_FORMAT(DATE_SUB(@month_date, INTERVAL 1 MONTH), '%Y%m')
);

WITH revenue AS (
    SELECT 
        l.sales_doc_id,
        l.product_fee,
        l.reward_amt
    FROM sales l
    JOIN sales_txns t ON l.sales_doc_id = t.sales_doc_id
    WHERE l.country_code = @country_code
      AND l.status = 'delivered'
      AND l.sales_doc_id IN (
          SELECT sales_doc_id
          FROM sales_txns t
          WHERE (
                (t.txn_date BETWEEN @start_date AND @end_date AND t.realization_date <= @closure_date)
                OR (t.txn_date < @start_date AND t.realization_date > @prev_closure_date AND t.realization_date <= @closure_date)
          )
          AND txn_type = 'float_out'
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
            (a.stmt_txn_date BETWEEN @start_date AND @end_date AND a.realization_date <= @closure_date)
            OR (a.stmt_txn_date < @start_date AND a.realization_date > @prev_closure_date AND a.realization_date <= @closure_date)
      )
      AND a.acc_txn_type IN (
            'float_in','duplicate_float_out_reversal','float_out',
            'float_in_reversed','float_in_refunded',
            'duplicate_float_in_refunded','duplicate_float_out',
            'wrong_float_in'
      )
),
temp AS (
    SELECT 
        ra.loan_doc_id `Loan Doc ID`,
        ra.id `ID`,
        ra.stmt_txn_id `Transaction ID`,
        ra.stmt_txn_date `Transaction Date`,
        ra.realization_date `Realization Date`,
        ra.account_id `Account ID`,
        ra.acc_prvdr_code `Account Provider Code`,
        ra.acc_number `Account Number`,
        ra.acc_txn_type `Account Txn Type`,
        ra.cr_amt `CR Amount`,
        ra.dr_amt `DR Amount`,
        IF(ra.acc_txn_type='float_out',IFNULL(product_fee,0),0) AS Fee,
        IF(ra.acc_txn_type='float_out',IFNULL(reward_amt,0),0) AS Cashback
    FROM raw ra
    LEFT JOIN revenue fee ON ra.loan_doc_id = fee.sales_doc_id
)
SELECT t.*, (t.Fee - t.Cashback) AS Revenue
FROM temp t;