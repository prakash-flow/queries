  set @country_code = 'RWA';
  set @month = '202612';
  SET @pre_month = (SELECT DATE_FORMAT(DATE_SUB(STR_TO_DATE(CONCAT(@month, '01'), '%Y%m%d'), INTERVAL 12 MONTH), '%Y%m'));
  SET @start_month = (SELECT DATE_FORMAT(DATE_SUB(STR_TO_DATE(CONCAT(@month, '01'), '%Y%m%d'), INTERVAL 11 MONTH), '%Y%m'));
  SET @start_date = (DATE(CONCAT(@start_month, '01')));
  set @last_day = (LAST_DAY(DATE(CONCAT(@month, "01"))));
  set @realization_date = (IFNULL((select closure_date from closure_date_records where month = @month and status = 'enabled' and country_code = @country_code), CONCAT(@last_day, ' 23:59:59')));
  set @pre_realization_date = ((select closure_date from closure_date_records where month = @pre_month and status = 'enabled' and country_code = @country_code));
  
  select @start_date,@last_day,@realization_date,@pre_realization_date,@pre_month,@start_month;
  
  
  WITH raw AS (
        SELECT
            acc.acc_number AS acc_number,
            t.amount AS amount,
            ifnull(t.principal,0) AS principal,
            ifnull(t.fee,0) AS fee,
            ifnull(t.charges,0) AS charges,
            ifnull(t.penalty,0) AS penalty,
            t.excess AS excess,
            lw.write_off_date AS write_off_date ,
            CASE
                WHEN lw.loan_doc_id IS NULL THEN 0
                WHEN lw.write_off_date IS NULL THEN 0
                ELSE date(t.realization_date) > lw.write_off_date
            END AS is_recovery
        FROM loans l
        JOIN loan_txns t ON l.loan_doc_id = t.loan_doc_id
        JOIN account_stmts ast ON t.txn_id = ast.stmt_txn_id
        JOIN accounts acc ON ast.account_id = acc.id
        LEFT JOIN loan_write_off lw ON lw.loan_doc_id = l.loan_doc_id
            AND lw.country_code = l.country_code and  date(write_off_date) <= @last_day
        WHERE
            l.loan_purpose IN ('float_advance','terminal_financing','adj_float_advance')
            and (
                      (   extract(year_month from txn_date) <= @month and extract(year_month from txn_date) >= @start_month and t.realization_date <= @realization_date  )
                      or 
                      (   extract(year_month from txn_date) < @start_month and t.realization_date > @pre_realization_date and t.realization_date <= @realization_date   )
                  )
            AND t.txn_type = 'payment'
            AND date(t.txn_date) <= @last_day
            AND ast.acc_txn_type = 'payment'
            AND t.country_code = @country_code
            AND ast.country_code = @country_code
            AND l.country_code = @country_code
            AND acc.country_code = @country_code
    )
    SELECT 
    -- SUM(IF(is_recovery = 0, principal +fee+charges, 0)) AS repayment_amt,
            SUM((principal + fee+ charges+penalty)) AS total_repaied_amt,
            SUM(IF(is_recovery = 0, principal , 0)) AS principal_recived,
            SUM(IF(is_recovery = 0, fee , 0)) AS fee_recived,
            SUM(IF(is_recovery = 0, charges , 0)) AS charges_recived,
            SUM(IF(is_recovery = 1, amount, 0)) AS recover_amt
    FROM raw
  
  
  
  
  
  
  
  
  
