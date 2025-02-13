set
  @year = 2024;

set
  @country_code = 'UGA';

set
  @closure_date = (
    select
      closure_date
    from
      closure_date_records
    where
      country_code = @country_code
      and status = 'enabled'
      and month = concat(@year, "12")
  );

set
  @prev_closure_date = (
    select
      closure_date
    from
      closure_date_records
    where
      country_code = @country_code
      and status = 'enabled'
      and month = DATE_FORMAT(
        DATE_SUB(DATE(CONCAT(@month, '01')), INTERVAL 1 MONTH),
        '%Y%m'
      )
  );


select @country_code, @year, @closure_date, @prev_closure_date;

WITH
  pri AS (
    SELECT
      l.sales_doc_id,
      SUM(lt.amount) AS duplicate,
      l.country_code
    FROM
      sales l
      JOIN sales_txns lt ON lt.sales_doc_id = l.sales_doc_id
    WHERE
      lt.txn_type IN (
        'duplicate_disbursal',
        'duplicate_payment_reversal'
      )
      AND l.country_code = @country_code
      AND (
        (
          year(txn_date) = @year
          AND realization_date <= @closure_date
        )
        OR (
          year(txn_date) < @year
          AND realization_date > @prev_closure_date
          AND realization_date <= @closure_date
        )
      )
    GROUP BY
      l.sales_doc_id
  ),
  sec as (
    SELECT
      l.sales_doc_id,
      IFNULL(SUM(lt.amount), 0) AS duplicate_reversal,
      l.country_code
    FROM
      sales l
      JOIN sales_txns lt ON lt.sales_doc_id = l.sales_doc_id
    WHERE
      lt.txn_type IN ('dup_disb_rvrsl', 'duplicate_payment')
      AND l.country_code = @country_code
      AND (
        (
          year(txn_date) = @year
          AND realization_date <= @closure_date
        )
        OR (
          year(txn_date) < @year
          AND realization_date > @prev_closure_date
          AND realization_date <= @closure_date
        )
      )
      AND status NOT IN(
        'voided',
        'hold',
        'pending_disbursal',
        'pending_mnl_dsbrsl'
      )
    GROUP BY
      l.sales_doc_id
  ),
  metricByLoan as (
    SELECT
    	pri.sales_doc_id,
      pri.duplicate dup,
      ifnull(sec.duplicate_reversal, 0) rev,
      if(pri.duplicate - ifnull(sec.duplicate_reversal, 0) > 0, pri.duplicate - ifnull(sec.duplicate_reversal, 0), 0) unrev
    FROM
      pri
      LEFT JOIN sec ON pri.sales_doc_id = sec.sales_doc_id
    WHERE
      pri.country_code = @country_code
    UNION
    SELECT
    	sec.sales_doc_id,
      pri.duplicate dup,
      ifnull(sec.duplicate_reversal, 0) rev,
      if(pri.duplicate - ifnull(sec.duplicate_reversal, 0) > 0, pri.duplicate - ifnull(sec.duplicate_reversal, 0), 0) unrev
    FROM
      pri
      RIGHT JOIN sec ON pri.sales_doc_id = sec.sales_doc_id
    WHERE
      sec.country_code = @country_code
  ),
loan_date as (
    select
      m.sales_doc_id `Sales ID`,
    	l.cust_id `Customer ID`,
    	b.acc_prvdr_code `Account Provider Code`,
    	concat_ws(' ', p.first_name, p.middle_name, p.last_name) `Customer Name`,
    	b.acc_number `Account Number`,
    	concat_ws(' ', rm.first_name, rm.middle_name, rm.last_name) `RM Name`,
    	m.dup `Duplicate Disbursal`,
    	m.rev `Reversal`,
    	m.unrev `Unreversed`
    from
      sales l
      join metricByLoan m on l.sales_doc_id = m.sales_doc_id
      join borrowers b on l.cust_id = b.cust_id
      left join persons p on p.id = b.owner_person_id
      left join persons rm on rm.id = b.flow_rel_mgr_id
  )
  select * from loan_date;