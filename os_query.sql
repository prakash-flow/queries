  set @country_code = 'RWA';
  set @month = '202401';

  set @last_day = (LAST_DAY(DATE(CONCAT(@month, "01"))));
  set @realization_date = (IFNULL((select closure_date from closure_date_records where month = @month and status = 'enabled' and country_code = @country_code), now()));

  select @last_day, @realization_date;


  select 
    sum(
      IF(
        principal - IFNULL(partial_pay, 0) < 0, 
        0, 
        principal - IFNULL(partial_pay, 0)
      )
    ) par_loan_principal, 
    sum(
      IF(
        partial_pay > principal, principal, 
        partial_pay
      )
    ) partial_paid 
  from 
    (
      select 
        l.loan_doc_id, 
        sum(amount) principal 
      from 
        loans l 
        JOIN loan_txns lt ON lt.loan_doc_id = l.loan_doc_id 
      where 
        lt.txn_type in ('disbursal') 
        and realization_date <= @realization_date 
        and l.country_code = @country_code 
        and date(disbursal_date) <= @last_day 
        and product_id not in (43, 75, 300) 
        and l.status not in (
          'voided', 'hold', 'pending_disbursal', 
          'pending_mnl_dsbrsl'
        ) 
        group by loan_doc_id
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
      group by 
        l.loan_doc_id
    ) pp on pri.loan_doc_id = pp.loan_doc_id;