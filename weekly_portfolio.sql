set
  @last_day = '2024-09-09';

set
  @country_code = 'UGA';

set
  @month = (
    EXTRACT(
      YEAR_MONTH
      FROM
        @last_day
    )
  );

SET
  @header = (DATE_FORMAT(@last_day, '%M %d, %Y'));
  
-- Existing records are taken by using month end realization_date
set @realization_date = (select closure_date from closure_date_records where country_code = @country_code and month = @month and status = 'enabled');

select
  @month,
  @country_code,
  @last_day,
  @realization_date,
  @header;

with par as (
  SELECT 
    SUM(
      if(
        l.loan_principal - t.total_amount > 0, 
        l.loan_principal - t.total_amount, 
        0
      )
    ) total_os, 
    SUM(
      IF(
        DATEDIFF(@last_day, l.due_date) <= 1, 
        if(
          l.loan_principal - t.total_amount > 0, 
          l.loan_principal - t.total_amount, 
          0
        ), 
        0
      )
    ) AS no_arrear, 
    SUM(
      IF(
        DATEDIFF(@last_day, l.due_date) between 1 
        and 7, 
        if(
          l.loan_principal - t.total_amount > 0, 
          l.loan_principal - t.total_amount, 
          0
        ), 
        0
      )
    ) AS par_1_7, 
    SUM(
      IF(
        DATEDIFF(@last_day, l.due_date) between 8 
        and 15, 
        if(
          l.loan_principal - t.total_amount > 0, 
          l.loan_principal - t.total_amount, 
          0
        ), 
        0
      )
    ) AS par_7_15, 
    SUM(
      IF(
        DATEDIFF(@last_day, l.due_date) between 16 
        and 30, 
        if(
          l.loan_principal - t.total_amount > 0, 
          l.loan_principal - t.total_amount, 
          0
        ), 
        0
      )
    ) AS par_15_30, 
    SUM(
      IF(
        DATEDIFF(@last_day, l.due_date) <= 30, 
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
        DATEDIFF(@last_day, l.due_date) between 31 
        and 60, 
        if(
          l.loan_principal - t.total_amount > 0, 
          l.loan_principal - t.total_amount, 
          0
        ), 
        0
      )
    ) AS par_30_60, 
    SUM(
      IF(
        DATEDIFF(@last_day, l.due_date) between 61 
        and 90, 
        if(
          l.loan_principal - t.total_amount > 0, 
          l.loan_principal - t.total_amount, 
          0
        ), 
        0
      )
    ) AS par_60_90, 
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
    ) AS par_120 
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
      status not in(
        'voided', 'hold', 'pending_disbursal', 
        'pending_mnl_dsbrsl'
      )
    ) 
    AND DATE(l.disbursal_Date) <= @last_day 
    AND (
      product_id not in('43', '75', '300')
    ) 
    AND (
      l.loan_doc_id not in(
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
) 
select "Week", DATE_FORMAT(@last_day, '%M %d, %Y')
union all
select "Gross Portfolio", total_os from par
union all 
select "No Arrears", no_arrear from par 
union all 
select "1-7 days", par_1_7 from par 
union all 
select "7-15 days", par_7_15 from par 
union all 
select "15-30 days", par_15_30 from par 
union all 
select "< 30 days", par_30 from par 
union all 
select "30-60 days", par_30_60 from par 
union all 
select "60-90 days", par_60_90 from par 
union all 
select "> 90 days", par_90 from par 
union all 
select "> 120 days", par_120 from par;