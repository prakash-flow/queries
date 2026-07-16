set @country_code = 'RWA';
set @month = '202212';
SET @pre_month = (SELECT DATE_FORMAT(DATE_SUB(STR_TO_DATE(CONCAT(@month, '01'), '%Y%m%d'), INTERVAL 12 MONTH), '%Y%m'));
SET @start_month = (SELECT DATE_FORMAT(DATE_SUB(STR_TO_DATE(CONCAT(@month, '01'), '%Y%m%d'), INTERVAL 11 MONTH), '%Y%m'));
SET @start_date = (DATE(CONCAT(@start_month, '01')));
set @last_day = (LAST_DAY(DATE(CONCAT(@month, "01"))));
set @realization_date = (IFNULL((select closure_date from closure_date_records where month = @month and status = 'enabled' and country_code = @country_code), CONCAT(@last_day, ' 23:59:59')));
set @pre_realization_date = ((select closure_date from closure_date_records where month = @pre_month and status = 'enabled' and country_code = @country_code));

select @start_date,@last_day,@realization_date,@pre_realization_date,@pre_month,@start_month;


select 
  -- date(txn_date),
  -- l.loan_purpose,
  count(distinct l.cust_id),
  count(distinct l.loan_doc_id),
  sum(amount) disb 
  from loans l Join loan_txns t ON l.loan_doc_id = t.loan_doc_id
              where 
              date(disbursal_date) <= @last_day
              and product_id not in (select id from loan_products where product_type = 'float_vending')
              and (
                    (   extract(year_month from txn_date) <= @month and extract(year_month from txn_date) >= @start_month and realization_date <= @realization_date  )
                    or 
                    (   extract(year_month from txn_date) < @start_month and realization_date > @pre_realization_date and realization_date <= @realization_date   )
                )
              and date(txn_date) <= @last_day and l.country_code = @country_code
              AND l.status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
              and product_id not in (43, 75, 300)
              and txn_type in ('disbursal' ,'af_disbursal')
  -- group by date(txn_date)
  -- group by l.loan_purpose
  ;









