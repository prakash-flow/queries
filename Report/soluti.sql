select
  count(DISTINCT
    CASE
      WHEN date(txn_date) > lw.write_off_date THEN l.loan_doc_id
    END
  ) `count`,
  SUM(
    CASE
      WHEN date(txn_date) > lw.write_off_date THEN IFNULL(amount, 0)
    END
  ) amount
from
  loans l
  left join loan_write_off lw on lw.loan_doc_id = l.loan_doc_id
  left join loan_txns lt on lt.loan_doc_id = l.loan_doc_id
  and lt.txn_type = 'payment'
  and l.country_code = 'RWA'
  where year(lw.write_off_date) < 2025;


select sum(write_off_amount) from loan_write_off where year(write_off_date) = 2025 and country_code = 'RWA';