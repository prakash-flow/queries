SET @country_code = 'UGA';
  SET @last_day = '2026-09-15';

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
  installment_os AS (
      SELECT
          li.loan_doc_id,
          li.due_date,
          li.principal_due,
          IF(li.fee_generated=1, li.fee_due, 0) AS fee_due,
          GREATEST(li.principal_due - COALESCE(paid.paid_principal,0), 0) AS os_amount,
          GREATEST(IF(DATE(li.due_date) <= @last_day AND li.fee_generated=1, li.fee_due,0) - COALESCE(paid.paid_fee,0), 0) AS fee_os
      FROM loan_installments li
      LEFT JOIN paid_as_of paid ON paid.installment_id = li.id
      WHERE li.country_code = @country_code
  ),
  loan_level AS (
      SELECT
          loan_doc_id,
          SUM(os_amount) AS loan_os,
          SUM(fee_os) AS fee_os,
          MIN(CASE WHEN (os_amount > 0 OR fee_os > 0) AND DATE(due_date) <= @last_day THEN due_date END) AS min_overdue_due_date
      FROM installment_os
      GROUP BY loan_doc_id
  )
  SELECT
      l.loan_purpose,
      COUNT(DISTINCT IF(ll.loan_os > 0 OR ll.fee_os > 0, ll.loan_doc_id, NULL)) AS cust_count_loan,
      COUNT(DISTINCT IF((ll.loan_os > 0 OR ll.fee_os > 0) AND DATEDIFF(@last_day, ll.min_overdue_due_date) > 1, ll.loan_doc_id, NULL)) AS overdue_count_loan,
      SUM(io.principal_due + io.fee_due) AS amount_due_for_month,
      COUNT(DISTINCT io.loan_doc_id) AS loans_due_during_month,
      COUNT(DISTINCT IF((ll.loan_os > 0 OR ll.fee_os > 0) AND DATEDIFF(@last_day, ll.min_overdue_due_date) > 1, ll.loan_doc_id, NULL)) AS loans_in_overdue
  FROM loan_level ll
  JOIN loans l ON l.loan_doc_id = ll.loan_doc_id
  LEFT JOIN installment_os io
      ON io.loan_doc_id = ll.loan_doc_id
     AND DATE_FORMAT(io.due_date,'%Y-%m') = DATE_FORMAT(@last_day,'%Y-%m')
  WHERE l.loan_purpose IN ('growth_financing','asset_financing')
  GROUP BY l.loan_purpose
  ORDER BY l.loan_purpose DESC;