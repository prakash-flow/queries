SET
  @month = '202601';

SET
  @country_code = 'RWA';

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
  l.cust_id `Customer ID`,
  l.loan_doc_id `Loan ID`,
  l.cust_name `Customer Name`,
  l.biz_name `Biz Name`,
  l.flow_rel_mgr_name `RM Name`,
  l.acc_prvdr_code `Account Provider Code`,
  DATE(l.disbursal_date) `Disbursal Date`,
  DATE(l.due_date) `Due Date`,
  l.loan_principal `Loan Principal`,
  l.flow_fee `Flow Fee`,
  l.provisional_penalty `Provisional Penalty`,
  l.status `Status`,
  IFNULL(p.total_amount, 0) `Paid Amount`,
  (l.loan_principal - IFNULL(p.total_amount, 0)) AS `Outstanding`,
  b.category `Category`,
  CASE
      WHEN field_1 IS NULL
        OR field_2 IS NULL
        OR field_3 IS NULL
        OR field_4 IS NULL
      THEN CONCAT(
          CONCAT_WS(', ',
              CASE WHEN field_1 IS NULL THEN 'Province' END,
              CASE WHEN field_2 IS NULL THEN 'District' END,
              CASE WHEN field_3 IS NULL THEN 'Sector' END,
              CASE WHEN field_4 IS NULL THEN 'Cell' END
          ),
          ' is null'
      )
  END AS `Remarks`
FROM
  loans l
  LEFT JOIN borrowers b ON b.cust_id = l.cust_id
  LEFT JOIN address_info a ON a.id = b.owner_address_id
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
  AND DATEDIFF(@last_day, l.due_date) > 30;