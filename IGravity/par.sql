set @month = '202503';
set @country_code = 'UGA';

set @last_day = (LAST_DAY(DATE(CONCAT(@month, "01"))));
set @realization_date = (select closure_date from closure_date_records where country_code = @country_code and month = @month and status = 'enabled');

select @month, @country_code, @last_day, @realization_date;

SELECT 
  SUM(
    IF(
      DATEDIFF(@last_day, l.due_date) <= 0, 
      if(
        l.loan_principal - t.total_amount > 0, 
        l.loan_principal - t.total_amount, 
        0
      ), 
      0
    )
  ) AS not_overdue,
  SUM(
    IF(
      DATEDIFF(@last_day, l.due_date) between 1 and 30, 
      if(
        l.loan_principal - t.total_amount > 0, 
        l.loan_principal - t.total_amount, 
        0
      ), 
      0
    )
  ) AS par_1_30, 
  SUM(
    IF(
      DATEDIFF(@last_day, l.due_date) between 31 and 60, 
      if(
        l.loan_principal - t.total_amount > 0, 
        l.loan_principal - t.total_amount, 
        0
      ), 
      0
    )
  ) AS par_31_60, 
  SUM(
    IF(
      DATEDIFF(@last_day, l.due_date) between 61 and 90, 
      if(
        l.loan_principal - t.total_amount > 0, 
        l.loan_principal - t.total_amount, 
        0
      ), 
      0
    )
  ) AS par_61_90,
  SUM(
    IF(
      DATEDIFF(@last_day, l.due_date) between 91 and 120, 
      if(
        l.loan_principal - t.total_amount > 0, 
        l.loan_principal - t.total_amount, 
        0
      ), 
      0
    )
  ) AS par_91_120, 
  SUM(
    IF(
      DATEDIFF(@last_day, l.due_date) between 121 and 180, 
      if(
        l.loan_principal - t.total_amount > 0, 
        l.loan_principal - t.total_amount, 
        0
      ), 
      0
    )
  ) AS par_121_180, 
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
  ) AS par_180
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