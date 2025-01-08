set @month = '202412';
set @country_code = 'RWA';

set @last_day = (LAST_DAY(DATE(CONCAT(@month, "01"))));;
set @realization_date = (select closure_date from closure_date_records where country_code = @country_code and month = @month and status = 'enabled');

select @month, @country_code, @last_day, @realization_date;

SELECT 
  l.acc_prvdr_code, 
  SUM(
    if(
      l.loan_principal - t.total_amount > 0, 
      l.loan_principal - t.total_amount, 
      0
    )
  ) total_os, 
  SUM(
    IF(
      DATEDIFF(@last_day, l.due_date) > 1, 
      if(
        l.loan_principal - t.total_amount > 0, 
        l.loan_principal - t.total_amount, 
        0
      ), 
      0
    )
  ) AS par_1, 
  SUM(
    IF(
      DATEDIFF(@last_day, l.due_date) > 5, 
      if(
        l.loan_principal - t.total_amount > 0, 
        l.loan_principal - t.total_amount, 
        0
      ), 
      0
    )
  ) AS par_5, 
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
  ) AS par_30, 
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
  ) AS par_60, 
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
  ) AS par_90, 
  SUM(
    IF(
      DATEDIFF(@last_day, l.due_date) > 120, 
      if(
        l.loan_principal - t.total_amount > 0, 
        l.loan_principal - t.total_amount, 
        0
      ), 
      0
    )
  ) AS par_120, 
  SUM(
    IF(
      DATEDIFF(@last_day, l.due_date) > 180, 
      if(
        l.loan_principal - t.total_amount > 0, 
        l.loan_principal - t.total_amount, 
        0
      ), 
      0
    )
  ) AS par_180, 
  SUM(
    IF(
      DATEDIFF(@last_day, l.due_date) > 270, 
      if(
        l.loan_principal - t.total_amount > 0, 
        l.loan_principal - t.total_amount, 
        0
      ), 
      0
    )
  ) AS par_270, 
  SUM(
    IF(
      DATEDIFF(@last_day, l.due_date) > 360, 
      if(
        l.loan_principal - t.total_amount > 0, 
        l.loan_principal - t.total_amount, 
        0
      ), 
      0
    )
  ) AS par_360 
FROM 
  (
    SELECT 
      loan_doc_id, 
      SUM(
        if(txn_type = 'payment', amount, 0)
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
  and l.country_code = @country_code 
group by 
  l.acc_prvdr_code;