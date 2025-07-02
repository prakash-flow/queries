SET
  @month = '202503';

SET
  @country_code = 'UGA';

SET
  @last_day = LAST_DAY(DATE(CONCAT(@month, "01")));

SET
  @realization_date = (
    SELECT
      closure_date
    FROM
      closure_date_records
    WHERE
      country_code = @country_code
      AND month = @month
      AND status = 'enabled'
  );

WITH
  loan_payments AS (
    SELECT
      loan_doc_id,
      SUM(IFNULL(principal, 0)) total_amount
    FROM
      loan_txns
    WHERE
      DATE(txn_date) <= @last_day
      AND realization_date <= @realization_date
      AND txn_type = 'payment'
    GROUP BY
      loan_doc_id
  )

SELECT
  l.cust_id,
  l.loan_doc_id,
  l.cust_name,
  l.biz_name,
  l.flow_rel_mgr_name,
  l.acc_prvdr_code,
  DATE(l.disbursal_date) disbursal_date,
  YEAR(l.disbursal_date) year_of_disbursal_date,
  DATE(l.due_date) due_date,
  l.loan_principal,
  l.flow_fee,
  l.provisional_penalty,
  l.status,
  IFNULL(p.total_amount, 0) paid_amount,
  (l.loan_principal - IFNULL(p.total_amount, 0)) AS outstanding,
  DATEDIFF(@last_day, l.due_date) AS dpd
FROM
  loans l
  LEFT JOIN loan_payments p ON l.loan_doc_id = p.loan_doc_id
WHERE
  l.status NOT IN(
    'voided',
    'hold',
    'pending_disbursal',
    'pending_mnl_dsbrsl'
  )
  AND DATE(l.disbursal_Date) <= @last_day
  AND l.product_id NOT IN('43', '75', '300')
  AND l.country_code = @country_code
  AND (l.loan_principal - IFNULL(p.total_amount, 0)) > 0
  AND DATEDIFF(@last_day, l.due_date) > 60;