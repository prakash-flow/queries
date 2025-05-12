set @country_code = 'UGA';
set @month = '202501';

set @prev_month = (SELECT DATE_FORMAT(DATE_SUB(STR_TO_DATE(CONCAT(@month, '01'), '%Y%m%d'), INTERVAL 1 MONTH), '%Y%m'));
SET @start_date = DATE(CONCAT(@month, '01'));
set @last_day = (LAST_DAY(DATE(CONCAT(@month, "01"))));
set @realization_date = (IFNULL((select closure_date from closure_date_records where month = @month and status = 'enabled' and country_code = @country_code), now()));
set @pre_realization_date = ((select closure_date from closure_date_records where month = @prev_month and status = 'enabled' and country_code = @country_code));

select @start_date,@last_day,@realization_date,@pre_realization_date;

SELECT 
    (SUM(IF(t.txn_type = 'float_in', t.amount, 0)) - 
    SUM(IF(t.txn_type = 'float_out', IF(l.prvdr_charges > 0, t.amount - l.prvdr_charges, t.amount), 0))) AS sw_revenue,
    l.country_code AS country_code  
FROM 
    sales l 
JOIN 
    sales_txns t ON l.sales_doc_id = t.sales_doc_id  
WHERE 
    t.sales_doc_id IN (
        SELECT sales_doc_id 
        FROM sales_txns 
        WHERE 
            txn_type = 'float_out'  
            and (
               (date(txn_date) >= @start_date and date(txn_date)<= @last_day  and realization_date <= @realization_date)
                or 
               (date(txn_date) < @start_date and realization_date > @pre_realization_date and realization_date <= @realization_date)
          )
            AND country_code = @country_code
    )
    AND l.country_code = @country_code  
    AND l.status = 'delivered' 
GROUP BY 
    l.country_code