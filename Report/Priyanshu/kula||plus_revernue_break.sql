SET @country_code = 'UGA';
  SET @month = '202609';
  SET @first_day = STR_TO_DATE(CONCAT(@month,'01'), '%Y%m%d');
  SET @last_day = LEAST(LAST_DAY(@first_day), CURDATE());

  WITH paid_as_of AS (
      SELECT
          p.installment_id,
          SUM(COALESCE(p.principal_amount,0)) AS paid_principal,
          SUM(COALESCE(p.fee_amount,0)) AS paid_fee
      FROM payment_allocation_items p
      JOIN loan_txns a ON a.id = p.loan_txn_id
      WHERE p.is_reversed = 0
        AND DATE(a.txn_date) <= @last_day
        AND a.txn_type IN ('af_payment','fee_waiver')
      GROUP BY p.installment_id
  ),
  paid_this_month AS (
      SELECT
          p.installment_id,
          SUM(COALESCE(p.principal_amount,0)) AS principal_paid_this_month,
          SUM(COALESCE(p.fee_amount,0)) AS fee_collected_this_month
      FROM payment_allocation_items p
      JOIN loan_txns a ON a.id = p.loan_txn_id
      WHERE p.is_reversed = 0
        AND DATE(a.txn_date) BETWEEN @first_day AND @last_day
        AND a.txn_type = 'af_payment'
      GROUP BY p.installment_id
  ),
  installment_os AS (
      SELECT
          li.loan_doc_id,
          li.due_date,
          GREATEST(li.principal_due - COALESCE(paid.paid_principal,0), 0) AS os_amount,
          GREATEST(IF(li.fee_generated = 1, li.fee_due, 0) - COALESCE(paid.paid_fee,0), 0) AS
  fee_os
      FROM loan_installments li
      JOIN loans l ON l.loan_doc_id = li.loan_doc_id
      LEFT JOIN paid_as_of paid ON paid.installment_id = li.id
      WHERE li.country_code = @country_code
        AND l.loan_purpose = 'growth_financing'
        AND DATE(l.disbursal_date) <= @last_day
  ),
  loan_level AS (
      SELECT
          loan_doc_id,
          SUM(os_amount) AS loan_os,
          SUM(fee_os) AS fee_os
      FROM installment_os
      GROUP BY loan_doc_id
  )
  SELECT
      @month AS month,
      (SELECT SUM(pm.principal_paid_this_month)
       FROM paid_this_month pm
       JOIN loan_installments li2 ON li2.id = pm.installment_id
       JOIN loans l2 ON l2.loan_doc_id = li2.loan_doc_id
       WHERE li2.country_code = @country_code AND l2.loan_purpose = 'growth_financing'
         AND DATE(l2.disbursal_date) <= @last_day) AS principal_paid,
      (SELECT SUM(pm.fee_collected_this_month)
       FROM paid_this_month pm
       JOIN loan_installments li2 ON li2.id = pm.installment_id
       JOIN loans l2 ON l2.loan_doc_id = li2.loan_doc_id
       WHERE li2.country_code = @country_code AND l2.loan_purpose = 'growth_financing'
         AND DATE(l2.disbursal_date) <= @last_day) AS revenue_collected,
      SUM(ll.fee_os) AS revenue_os,
      (SELECT SUM(io.fee_os)
       FROM installment_os io
       WHERE DATE(io.due_date) <= @last_day
         AND io.fee_os > 0) AS revenue_overdue
  FROM loan_level ll
  JOIN loans l ON l.loan_doc_id = ll.loan_doc_id
  WHERE l.loan_purpose = 'growth_financing'
    AND DATE(l.disbursal_date) <= @last_day;