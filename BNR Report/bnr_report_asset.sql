SET @report_date = '2025-12-31';
SET @month = '202512';
SET @country_code = 'RWA';

SET @last_day = LAST_DAY(DATE(CONCAT(@month,'01')));

SET @realization_date = (
  SELECT closure_date
  FROM closure_date_records
  WHERE country_code=@country_code
    AND month = @month
    AND status='enabled'
);

WITH disbursals AS (
    SELECT
        l.loan_doc_id,
        l.cust_id,
        l.cust_name,
        l.cust_mobile_num,
        l.flow_rel_mgr_name,
        l.loan_purpose,
        l.disbursal_date,
        l.due_date,
        l.paid_date,
        l.flow_fee,
        l.schedule_grace_period,
        l.schedule_part_period,
        l.loan_principal,
        l.number_of_installments
    FROM loans l
    JOIN loan_txns lt ON lt.loan_doc_id=l.loan_doc_id
    WHERE lt.txn_type='af_disbursal'
      AND l.loan_purpose IN ('growth_financing','asset_financing')
      AND lt.realization_date<=@realization_date
      AND l.country_code=@country_code
      AND DATE(l.disbursal_date)<=@last_day
      AND l.product_id NOT IN (
          SELECT id FROM loan_products WHERE product_type='float_vending'
      )
      AND l.status NOT IN ('voided','hold','pending_disbursal','pending_mnl_dsbrsl')
      AND l.loan_doc_id NOT IN (
          SELECT loan_doc_id
          FROM loan_write_off
          WHERE country_code=@country_code
            AND write_off_date<=@last_day
            AND write_off_status IN ('approved','partially_recovered','recovered')
      )
    GROUP BY l.loan_doc_id
),

loan_installment AS (
    SELECT loan_doc_id, installment_number, due_date, principal_due
    FROM loan_installments
    WHERE country_code=@country_code
),

payment_allocation AS (
    SELECT
        p.loan_doc_id,
        p.installment_number,
        SUM(p.principal_amount) paid_principal
    FROM payment_allocation_items p
    JOIN account_stmts a ON a.id=p.account_stmt_id
    WHERE p.country_code=@country_code
      AND a.country_code=@country_code
      AND DATE(a.stmt_txn_date)<=@last_day
      AND a.realization_date<=@realization_date
    GROUP BY p.loan_doc_id,p.installment_number
),

installment_os AS (
    SELECT
        li.loan_doc_id,
        li.due_date,
        IFNULL(p.paid_principal,0) `paid_principal`,
        GREATEST(li.principal_due-IFNULL(p.paid_principal,0),0) os_amount,
        IF(GREATEST(li.principal_due-IFNULL(p.paid_principal,0),0)=0,1,0) is_paid
    FROM loan_installment li
    LEFT JOIN payment_allocation p
      ON li.loan_doc_id=p.loan_doc_id
     AND li.installment_number=p.installment_number
),

paid_installment_count AS (
    SELECT
        loan_doc_id,
        SUM(is_paid) AS paid_installment_count,
        COUNT(CASE WHEN is_paid = 0 THEN 1 END) AS os_installment_count
    FROM installment_os
    GROUP BY loan_doc_id
),

first_due AS (
    SELECT loan_doc_id, MIN(due_date) first_due_date
    FROM loan_installment
    GROUP BY loan_doc_id
),

last_payment AS (
    SELECT
        p.loan_doc_id,
        MAX(a.stmt_txn_date) last_payment_date
    FROM payment_allocation_items p
    JOIN account_stmts a ON a.id=p.account_stmt_id
    WHERE p.country_code=@country_code
      AND a.country_code=@country_code
      AND DATE(a.stmt_txn_date)<=@last_day
    GROUP BY p.loan_doc_id
),

loan_level_os AS (
    SELECT
        loan_doc_id,
        SUM(paid_principal) paid_principal,
        SUM(os_amount) loan_os,
        MIN(CASE WHEN os_amount>0 THEN due_date END) min_overdue_due_date
    FROM installment_os
    GROUP BY loan_doc_id
)

SELECT
  d.cust_name,
  d.cust_id,
  d.cust_mobile_num,
  '' AS gender,
  '' AS age,
  'Customer' AS relationship,
  '' AS marital_status,
  '' AS is_ontime_repaid,
  'Growing Mobile Money Business' AS purpose_of_loan,
  '' AS branch_name,
  '' AS `Collateral Type`,
  '' AS `Guarantee(Collateral) Ammount`,
  '' AS district,
  '' AS sector,
  '' AS cell,
  '' AS village,
  ROUND((flow_fee/loan_principal) * 100) AS annual_interest,
  'FLAT' AS interest_rate_method,
  d.flow_rel_mgr_name,

  loan_principal AS principal,
  d.disbursal_date disbursal_date,
  d.due_date due_date,
  '' AS `Agreed Frequency of Repayment (Days)`,
  (d.schedule_grace_period + d.schedule_part_period)
        AS `Grace Period Accorded (Days)`,

  fd.first_due_date AS `Agreed Date of First Payment (Principal)`,
  lp.last_payment_date AS `Date of Last Payment (Principal)`,

  l.min_overdue_due_date AS arrear_start,
  @last_day AS report_date,
  number_of_installments,

  IFNULL(pic.paid_installment_count,0) AS paid_installment_count,
  IFNULL(pic.os_installment_count,0) AS os_installment_count,
  `paid_principal`,
  l.loan_os AS net_principal,
  '' `Eligible Collateral provided`,
  l.loan_os AS net_principal,
  CASE
    WHEN l.loan_os = 0 OR l.min_overdue_due_date IS NULL THEN 0
    ELSE DATEDIFF(@last_day,l.min_overdue_due_date)
  END AS od_days

FROM disbursals d
JOIN loan_level_os l ON d.loan_doc_id=l.loan_doc_id
LEFT JOIN paid_installment_count pic ON d.loan_doc_id=pic.loan_doc_id
LEFT JOIN first_due fd ON d.loan_doc_id=fd.loan_doc_id
LEFT JOIN last_payment lp ON d.loan_doc_id=lp.loan_doc_id

WHERE
  l.loan_os > 0
  AND CASE
        WHEN l.loan_os = 0 OR l.min_overdue_due_date IS NULL THEN 0
        ELSE DATEDIFF(@last_day,l.min_overdue_due_date)
      END BETWEEN 1 AND 89;