set @report_date = '2025-01-07';
set @month = '202409';
set @country_code = 'RWA';

set @last_day = (LAST_DAY(DATE(CONCAT(@month, "01"))));
set @realization_date = (select closure_date from closure_date_records where country_code = @country_code and month = @month and status = 'enabled');

select @last_day, @realization_date, @country_code, @month, @report_date, @having_condition;

select 
  cust_name, 
  cust_id, 
  cust_mobile_num, 
  acc_number, 
  gender, 
  age, 
  'Customer' relationship, 
  '' annual_interest, 
  'Flat', 
  '' empty1, 
  field_2 district, 
  field_3 sector, 
  field_4 cell, 
  field_5 village, 
  disbursal_date, 
  principal, 
  due_date, 
  partial_pay, 
  par_loan_principal, 
  '' empty2, 
  write_off_amount, 
  write_off_date, 
  recovery_amount, 
  write_off_balance 
from 
  (
    select 
      sum(
        IF(
          principal - IFNULL(partial_pay, 0) < 0, 
          0, 
          principal - IFNULL(partial_pay, 0)
        )
      ) par_loan_principal, 
      TIMESTAMPDIFF(
        YEAR, 
        max(dob), 
        @last_day
      ) age, 
      pri.loan_doc_id, 
      pri.cust_id, 
      pri.cust_name, 
      pri.cust_mobile_num, 
      pri.acc_prvdr_code, 
      pri.acc_number, 
      pri.flow_rel_mgr_name, 
      pri.principal, 
      pri.fee, 
      pri.disbursal_date, 
      pri.due_date, 
      if(
        datediff(@last_day, due_date)< 0, 
        0, 
        datediff(@last_day, due_date)
      ) as od_days, 
      pri.status, 
      pri.paid_date, 
      max(pri.gender) as gender, 
      IFNULL(
        sum(partial_pay), 
        0
      ) partial_pay, 
      sum(recovery_amount) recovery_amount, 
      sum(write_off_amount) write_off_amount, 
      sum(write_off_amount) - sum(recovery_amount) write_off_balance, 
      max(write_off_date) write_off_date, 
      max(field_2) field_2, 
      max(field_3) field_3, 
      max(field_4) field_4, 
      max(field_5) field_5 
    from 
      (
        select 
          l.loan_doc_id, 
          loan_principal principal, 
          l.cust_id, 
          l.flow_fee as fee, 
          l.acc_prvdr_code, 
          l.cust_name, 
          l.cust_mobile_num, 
          l.flow_rel_mgr_name, 
          l.product_name, 
          l.disbursal_date, 
          l.due_date, 
          l.overdue_days, 
          l.acc_number, 
          l.status, 
          l.paid_date, 
          p.gender, 
          p.dob, 
          field_2, 
          field_3, 
          field_4, 
          field_5 
        from 
          loans l, 
          loan_txns lt, 
          borrowers b, 
          persons p, 
          address_info a 
        where 
          lt.loan_doc_id = l.loan_doc_id 
          and b.cust_id = l.cust_id 
          and p.id = b.owner_person_id 
          and b.owner_address_id = a.id 
          and lt.txn_type in ('disbursal') 
          and realization_date <= @realization_date 
          and l.country_code = @country_code 
          and date(disbursal_date) <= @last_day 
          and product_id not in (43, 75, 300) 
          and l.status not in (
            'voided', 'hold', 'pending_disbursal', 
            'pending_mnl_dsbrsl'
          ) 
          and l.loan_doc_id in (
            select 
              loan_doc_id 
            from 
              loan_write_off 
            where 
              l.country_code = @country_code 
              and date(write_off_date) <= @last_day
          )
      ) pri 
      left join (
        select 
          l.loan_doc_id, 
          sum(principal) partial_pay 
        from 
          loans l 
          join loan_txns t ON l.loan_doc_id = t.loan_doc_id 
        where 
          l.country_code = @country_code 
          and date(disbursal_Date) <= @last_day 
          and product_id not in (43, 75, 300) 
          and realization_date <= @realization_date 
          and date(txn_date) <= @last_day 
          and txn_type = 'payment' 
          and l.status not in (
            'voided', 'hold', 'pending_disbursal', 
            'pending_mnl_dsbrsl'
          ) 
          and l.loan_doc_id in (
            select 
              loan_doc_id 
            from 
              loan_write_off 
            where 
              l.country_code = @country_code 
              and date(write_off_date) <= @last_day
          ) 
        group by 
          l.loan_doc_id
      ) pp on pri.loan_doc_id = pp.loan_doc_id 
      left join (
        select 
          loan_doc_id, 
          write_off_date, 
          write_off_amount, 
          recovery_amount 
        from 
          loan_write_off 
        where 
          country_code = @country_code 
          and write_off_date <= @last_day
      ) wf on pri.loan_doc_id = wf.loan_doc_id 
    group by 
      pri.loan_doc_id
  ) t;