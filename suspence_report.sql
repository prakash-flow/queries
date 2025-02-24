select
      acc_number `Account Number`,
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
      ) <= '202412'
      and stmt_txn_type in ('debit', 'credit')
      and country_code = "UGA"
      and (
        realization_date > '2025-01-08 23:59:59'
        or realization_date is null
      )
      order by stmt_txn_type, acc_number, stmt_txn_date, amount;