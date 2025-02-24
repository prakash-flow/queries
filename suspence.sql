set
  @month = 202412;

set
  @country_code = 'UGA';

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

with
  debit as (
    select
      sum(dr_amt) amount
    from
      account_stmts a
    where
      year(stmt_txn_date) >= 2023
      and EXTRACT(
        YEAR_MONTH
        FROM
          stmt_txn_date
      ) <= @month
      and stmt_txn_type = 'debit'
      and country_code = @country_code
      and (
        realization_date > @realization_date
        or realization_date is null
      )
  ),
  credit as (
    select
      sum(cr_amt) amount
    from
      account_stmts a
    where
      year(stmt_txn_date) >= 2023
      and EXTRACT(
        YEAR_MONTH
        FROM
          stmt_txn_date
      ) <= @month
      and stmt_txn_type = 'credit'
      and country_code = @country_code
      and (
        realization_date > @realization_date
        or realization_date is null
      )
  )
select
  @month,
  (
    select
      *
    from
      credit
  ) credit,
  (
    select
      *
    from
      debit
  ) debit;