set @month = '202502';
set @country_code = 'UGA';

set @last_day = (LAST_DAY(DATE(CONCAT(@month, "01"))));
set @realization_date = (select closure_date from closure_date_records where country_code = @country_code and month = @month and status = 'enabled');

select @month, @country_code, @last_day, @realization_date;

SELECT 
  SUM(
    if(
      l.loan_principal - t.total_amount > 0, 
      l.loan_principal - t.total_amount, 
      0
    )
  ) * 0.01 total_os, 
  SUM(
    IF(
      DATEDIFF(@last_day, l.due_date) > 30, 
      if(
        l.loan_principal - t.total_amount > 0, 
        l.loan_principal - t.total_amount, 
        0
      ), 
      0
    )
  ) * 0.1 AS par_30, 
  SUM(
    IF(
      DATEDIFF(@last_day, l.due_date) > 60, 
      if(
        l.loan_principal - t.total_amount > 0, 
        l.loan_principal - t.total_amount, 
        0
      ), 
      0
    )
  ) * 0.5 AS par_60, 
  SUM(
    IF(
      DATEDIFF(@last_day, l.due_date) > 90, 
      if(
        l.loan_principal - t.total_amount > 0, 
        l.loan_principal - t.total_amount, 
        0
      ), 
      0
    )
  ) AS par_90
FROM 
  (
    SELECT 
      loan_doc_id, 
      SUM(
        if(txn_type = 'payment', principal, 0)
      ) AS total_amount 
    FROM 
      loan_txns 
    WHERE 
      DATE(txn_date) <= @last_day 
      AND realization_date <= @realization_date 
    GROUP BY 
      loan_doc_id
  ) t, 
  loans l 
WHERE 
  l.loan_doc_id = t.loan_doc_id 
  and (
    status not in (
      'voided', 'hold', 'pending_disbursal', 
      'pending_mnl_dsbrsl'
    )
  ) 
  AND DATE(l.disbursal_Date) <= @last_day 
  AND (
    product_id not in ('43', '75', '300')
  ) 
  AND (
    l.loan_doc_id not in (
      select 
        loan_doc_id 
      from 
        loan_write_off 
      where 
        write_off_date <= @last_day 
        and write_off_status in (
          'approved', 'partially_recovered', 
          'recovered'
        ) 
        and country_code = @country_code
    )
  ) 
  and l.country_code = @country_code;