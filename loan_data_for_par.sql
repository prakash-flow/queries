set
  @month = '202312';

set
  @country_code = 'UGA';

set
  @last_day = (LAST_DAY(DATE(CONCAT(@month, "01"))));

set
  @realization_date = (
    select
      closure_date
    from
      closure_date_records
    where
      country_code = @country_code
      and month = @month
      and status = 'enabled'
  );

select
  @month,
  @country_code,
  @last_day,
  @realization_date;

with
  par_loans AS (
    SELECT
      l.loan_doc_id,
      SUM(
        if(
          l.loan_principal - t.total_amount > 0,
          l.loan_principal - t.total_amount,
          0
        )
      ) par
    FROM
      (
        SELECT
          loan_doc_id,
          SUM(if(txn_type = 'payment', amount, 0)) AS total_amount
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
          'voided',
          'hold',
          'pending_disbursal',
          'pending_mnl_dsbrsl'
        )
      )
      AND DATE(l.disbursal_Date) <= @last_day
      AND (product_id not in('43', '75', '300'))
      AND (
        l.loan_doc_id not in(
          select
            loan_doc_id
          from
            loan_write_off
          where
            write_off_date <= @last_day
            and write_off_status in ('approved', 'partially_recovered', 'recovered')
            and country_code = @country_code
        )
      )
      and l.country_code = @country_code
    group by
      l.loan_doc_id
    having
      par > 0
  )
select
  pl.loan_doc_id `Loan Doc ID`,
  l.acc_prvdr_code `Account Provider Code`,
  concat_ws(' ', p.first_name, p.middle_name, p.last_name) `Customer Name`,
  concat_ws(' ', rm.first_name, rm.middle_name, rm.last_name) `RM Name`,
  l.product_name `Product Name`,
  l.disbursal_date `Disbursal Date`,
  l.due_date `Due Date`,
  l.loan_principal `Principal`,
  l.flow_fee `Fee`,
  l.overdue_days,
  pl.par `OS Amount`
from
  loans l
  join par_loans pl on l.loan_doc_id = pl.loan_doc_id
  join borrowers b on b.cust_id = l.cust_id
  left join persons p on p.id = b.owner_person_id
  left join persons rm on rm.id = b.flow_rel_mgr_id;