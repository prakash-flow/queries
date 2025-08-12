set
  @month = 202401;

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

select
			@month `Month`,
      acc_number `Account Number`,
      acc_prvdr_code `Account Provider`,
      stmt_txn_type `Transaction Type`,
      stmt_txn_id `Tranaction ID`,
      date(stmt_txn_date) `Transaction Date`,
      if(stmt_txn_type = 'credit', cr_amt, dr_amt) `Amount`
    from
      account_stmts a
    where
      year(stmt_txn_date) >= 2023
      and EXTRACT(
        YEAR_MONTH
        FROM
          stmt_txn_date
      ) <= @month
      and stmt_txn_type in ('debit', 'credit')
      and country_code = "UGA"
      and (
        realization_date > @realization_date
        or realization_date is null
      )
      order by stmt_txn_type, acc_number, stmt_txn_date, amount;