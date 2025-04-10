set @report_date = '2024-12-31';
set @month = '202412';
set @country_code = 'RWA';

set @last_day = (LAST_DAY(DATE(CONCAT(@month, "01"))));;
set @realization_date = (select closure_date from closure_date_records where country_code = @country_code and month = @month and status = 'enabled');

select @last_day, @realization_date, @country_code, @month, @report_date;

select 
  count(loan_doc_id) count, 
  sum(par_loan_principal) value,
  gender 
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
      max(pri.gender) as gender 
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
          p.gender 
        from 
          loans l, 
          loan_txns lt, 
          borrowers b, 
          persons p 
        where 
          lt.loan_doc_id = l.loan_doc_id 
          and b.cust_id = l.cust_id 
          and p.id = b.owner_person_id 
          and lt.txn_type in ('disbursal') 
          and realization_date <= @realization_date 
          and l.country_code = @country_code
          and date(disbursal_date) <= @last_day 
          and product_id not in (43, 75, 300) 
          and l.status not in (
            'voided', 'hold', 'pending_disbursal', 
            'pending_mnl_dsbrsl'
          ) 
          and l.loan_doc_id not in (
            select 
              loan_doc_id 
            from 
              loan_write_off 
            where 
              l.country_code = @country_code
              and date(write_off_date) <= @last_day 
              and write_off_status in (
                'approved', 'partially_recovered', 
                'recovered'
              )
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
          and l.loan_doc_id not in (
            select 
              loan_doc_id 
            from 
              loan_write_off 
            where 
              l.country_code = @country_code
              and date(write_off_date) <= @last_day 
              and write_off_status in (
                'approved', 'partially_recovered', 
                'recovered'
              )
          ) 
        group by 
          l.loan_doc_id
      ) pp on pri.loan_doc_id = pp.loan_doc_id 
    group by 
      pri.loan_doc_id 
    having 
      par_loan_principal > 0
  ) as t 
group by 
  t.gender;