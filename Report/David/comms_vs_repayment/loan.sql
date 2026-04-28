select
  loan_doc_id `Loan Doc ID`,
  cust_id `Customer ID`,
  loan_principal `Principal`,
  flow_fee `Fee`,
  status `Status`,
  duration `Duration`,
  toDate (disbursal_date) `Disbursal Date`,
  toDate (due_date) `Due Date`,
  toDate (paid_date) `Paid Date`
from
  loans
where
  loan_purpose = 'float_advance'
  and country_code = 'UGA'
  and disbursal_date >= '2026-01-01 00:00:00'
order by disbursal_date;


-- https://docs.google.com/spreadsheets/d/1xbZH1U8f0g3Av0uHi6blON04Es0m2Bh7svvYo8-iGDw/edit?usp=sharing
-- https://docs.google.com/spreadsheets/d/1gO1jLiGbk4Otk3OfSU5xkQyDJ9-0vS5EimHpYTfFjIk/edit?usp=sharing