SET
  @country_code = 'UGA';

SET
  @month = '202512';

SET
  @last_date = LAST_DAY(DATE(CONCAT(@month, '01')));

SET
  @last_day = CONCAT(@last_date, ' 23:59:59');

SET
  @realization_date = IFNULL(
    (
      SELECT
        closure_date
      FROM
        closure_date_records
      WHERE
        month = @month
        AND status = 'enabled'
        AND country_code = @country_code
    ),
    @last_day
  );

SELECT
  @last_day,
  @realization_date;

WITH
  recentReassignments AS (
    SELECT
      cust_id,
      from_rm_id,
      rm_id,
      reason_for_reassign,
      from_date,
      ROW_NUMBER() OVER (
        PARTITION BY
          cust_id
        ORDER BY
          from_date ASC
      ) rn
    FROM
      rm_cust_assignments
    WHERE
      country_code = @country_code
      AND reason_for_reassign != 'initial_assignment'
      AND from_date > @last_day
  ),
  disbursal_loans AS (
    SELECT
      l.id,
      l.loan_purpose,
      l.country_code,
      l.acc_prvdr_code cust_dis_acc_prvdr_code,
      l.acc_number cust_dis_acc_number,
      l.cust_id,
      l.loan_doc_id,
      l.loan_approver_name,
      COALESCE(rr.from_rm_id, l.flow_rel_mgr_id) rm_id,
      l.disbursal_date,
      a.acc_prvdr_code Flow_disbursal_acc_prvdr_code,
      a.acc_number Flow_disbursal_acc_number,
      l.due_date,
      l.provisional_penalty,
      lt.disbursal_amount,
      l.due_amount,
      l.flow_fee
    FROM
      loans l
      JOIN (
        SELECT
          loan_doc_id,
          from_ac_id,
          SUM(amount) disbursal_amount
        FROM
          loan_txns
        WHERE
          txn_date <= @last_day
          AND realization_date <= @realization_date
          AND country_code = @country_code
          AND txn_type = 'disbursal'
        GROUP BY
          loan_doc_id,
          from_ac_id
      ) lt ON lt.loan_doc_id = l.loan_doc_id
      JOIN accounts a ON a.id = lt.from_ac_id
      LEFT JOIN recentReassignments rr ON rr.cust_id = l.cust_id
      AND rr.rn = 1
    WHERE
      l.country_code = @country_code
      AND l.disbursal_date <= @last_day
      AND l.status NOT IN(
        'voided',
        'hold',
        'pending_disbursal',
        'pending_mnl_dsbrsl'
      )
      AND l.product_id NOT IN(43, 75, 300)
  ),
  payments AS (
    SELECT
      loan_doc_id,
      MAX(txn_date) last_payment_date,
      SUM(IFNULL(principal, 0)) principal,
      SUM(IFNULL(fee, 0)) fee,
      SUM(IFNULL(charges, 0)) charges,
      SUM(IFNULL(excess, 0)) excess
    FROM
      loan_txns
    WHERE
      txn_date <= @last_day
      AND realization_date <= @realization_date
      AND country_code = @country_code
      AND txn_type = 'payment'
    GROUP BY
      loan_doc_id
  ),
  recived_payment_based_on_flow AS (
    SELECT
      loan_doc_id,
      SUM(
        IF(
          a.acc_prvdr_code = 'UDFC',
          IFNULL(principal, 0),
          0
        )
      ) Udfc_principal_recived,
      SUM(
        IF(
          a.acc_prvdr_code = 'UMTN',
          IFNULL(principal, 0),
          0
        )
      ) UMTN_principal_recived,
      SUM(
        IF(a.acc_prvdr_code = 'CCA', IFNULL(principal, 0), 0)
      ) CCA_principal_recived,
      SUM(
        IF(
          a.acc_prvdr_code = 'UATL',
          IFNULL(principal, 0),
          0
        )
      ) UATL_principal_recived,
      SUM(
        IF(
          a.acc_prvdr_code = 'UEZM',
          IFNULL(principal, 0),
          0
        )
      ) UEZM_principal_recived,
      SUM(
        IF(
          a.acc_prvdr_code = 'RBOK',
          IFNULL(principal, 0),
          0
        )
      ) RBOK_principal_recived,
      SUM(
        IF(
          a.acc_prvdr_code = 'RMTN',
          IFNULL(principal, 0),
          0
        )
      ) RMTN_principal_recived,
      SUM(
        IF(
          a.acc_prvdr_code = 'RATL',
          IFNULL(principal, 0),
          0
        )
      ) RATL_principal_recived,
      SUM(IF(a.acc_prvdr_code = 'UDFC', IFNULL(fee, 0), 0)) Udfc_fee_recived,
      SUM(IF(a.acc_prvdr_code = 'UMTN', IFNULL(fee, 0), 0)) UMTN_fee_recived,
      SUM(IF(a.acc_prvdr_code = 'CCA', IFNULL(fee, 0), 0)) CCA_fee_recived,
      SUM(IF(a.acc_prvdr_code = 'UATL', IFNULL(fee, 0), 0)) UATL_fee_recived,
      SUM(IF(a.acc_prvdr_code = 'UEZM', IFNULL(fee, 0), 0)) UEZM_fee_recived,
      SUM(IF(a.acc_prvdr_code = 'RBOK', IFNULL(fee, 0), 0)) RBOK_fee_recived,
      SUM(IF(a.acc_prvdr_code = 'RMTN', IFNULL(fee, 0), 0)) RMTN_fee_recived,
      SUM(IF(a.acc_prvdr_code = 'RATL', IFNULL(fee, 0), 0)) RATL_fee_recived,
      SUM(
        IF(a.acc_prvdr_code = 'UDFC', IFNULL(charges, 0), 0)
      ) Udfc_charges_recived,
      SUM(
        IF(a.acc_prvdr_code = 'UMTN', IFNULL(charges, 0), 0)
      ) UMTN_charges_recived,
      SUM(
        IF(a.acc_prvdr_code = 'CCA', IFNULL(charges, 0), 0)
      ) CCA_charges_recived,
      SUM(
        IF(a.acc_prvdr_code = 'UATL', IFNULL(charges, 0), 0)
      ) UATL_charges_recived,
      SUM(
        IF(a.acc_prvdr_code = 'UEZM', IFNULL(charges, 0), 0)
      ) UEZM_charges_recived,
      SUM(
        IF(a.acc_prvdr_code = 'RBOK', IFNULL(charges, 0), 0)
      ) RBOK_charges_recived,
      SUM(
        IF(a.acc_prvdr_code = 'RMTN', IFNULL(charges, 0), 0)
      ) RMTN_charges_recived,
      SUM(
        IF(a.acc_prvdr_code = 'RATL', IFNULL(charges, 0), 0)
      ) RATL_charges_recived,
      SUM(
        IF(a.acc_prvdr_code = 'UDFC', IFNULL(excess, 0), 0)
      ) Udfc_excess_recived,
      SUM(
        IF(a.acc_prvdr_code = 'UMTN', IFNULL(excess, 0), 0)
      ) UMTN_excess_recived,
      SUM(
        IF(a.acc_prvdr_code = 'CCA', IFNULL(excess, 0), 0)
      ) CCA_excess_recived,
      SUM(
        IF(a.acc_prvdr_code = 'UATL', IFNULL(excess, 0), 0)
      ) UATL_excess_recived,
      SUM(
        IF(a.acc_prvdr_code = 'UEZM', IFNULL(excess, 0), 0)
      ) UEZM_excess_recived,
      SUM(
        IF(a.acc_prvdr_code = 'RBOK', IFNULL(excess, 0), 0)
      ) RBOK_excess_recived,
      SUM(
        IF(a.acc_prvdr_code = 'RMTN', IFNULL(excess, 0), 0)
      ) RMTN_excess_recived,
      SUM(
        IF(a.acc_prvdr_code = 'RATL', IFNULL(excess, 0), 0)
      ) RATL_excess_recived
    FROM
      loan_txns lt
      JOIN accounts a ON a.id = lt.to_ac_id
    WHERE
      txn_date <= @last_day
      AND realization_date <= @realization_date
      AND lt.country_code = @country_code
      AND txn_type = 'payment'
    GROUP BY
      loan_doc_id
  ),
  waived_amounts AS (
    SELECT
      loan_doc_id,
      SUM(IFNULL(fee, 0)) fee_waive
    FROM
      loan_txns
    WHERE
      txn_date <= @last_day
      AND realization_date <= @realization_date
      AND country_code = @country_code
      AND txn_type = 'fee_waiver'
    GROUP BY
      loan_doc_id
  ),
  borrower_detailes AS (
    SELECT
      b.cust_id,
      p.gender,
      p.full_name,
      p.mobile_num,
      TIMESTAMPDIFF(YEAR, p.dob, @last_date) age,
      CASE
        WHEN TIMESTAMPDIFF(YEAR, p.dob, @last_date) < 35 THEN 'youth'
        ELSE 'elder'
      END age_bucket,
      b.reg_date
    FROM
      borrowers b
      JOIN persons p ON p.id = b.owner_person_id
      JOIN address_info ad ON ad.id = b.owner_address_id
    WHERE
      b.country_code = @country_code
      AND b.reg_date <= @last_date
  ),
  last_payment_amount AS (
    SELECT
      loan_doc_id,
      amount last_paid_amount,
      txn_date last_paid_date
    FROM
      (
        SELECT
          loan_doc_id,
          amount,
          txn_date,
          ROW_NUMBER() OVER (
            PARTITION BY
              loan_doc_id
            ORDER BY
              txn_date DESC
          ) rn
        FROM
          loan_txns
        WHERE
          txn_type = 'payment'
          AND (
            principal > 0
            OR fee > 0
          )
          AND country_code = @country_code
          AND txn_date <= @last_day
      ) t
    WHERE
      rn = 1
  ),
  last_visit AS (
    SELECT
      *
    FROM
      (
        SELECT
          cust_id,
          visitor_id,
          visit_end_time,
          type,
          remarks,
          ROW_NUMBER() OVER (
            PARTITION BY
              cust_id
            ORDER BY
              visit_start_time DESC
          ) rn
        FROM
          field_visits
        WHERE
          sch_status = 'checked_out'
          AND country_code = @country_code
          AND visit_end_time <= @last_day
      ) x
    WHERE
      rn = 1
  ),
  os AS (
    SELECT
      dl.loan_doc_id,
      (dl.disbursal_amount - IFNULL(p.principal, 0)) principal_os,
      (
        dl.flow_fee - (IFNULL(p.fee, 0) + IFNULL(w.fee_waive, 0))
      ) fee_os,
      IF(
        @last_day > dl.due_date
        AND (
          (dl.disbursal_amount - IFNULL(p.principal, 0)) > 0
          OR (
            dl.flow_fee - (IFNULL(p.fee, 0) + IFNULL(w.fee_waive, 0))
          ) > 0
        ),
        DATEDIFF(@last_day, dl.due_date),
        0
      ) dpd
    FROM
      disbursal_loans dl
      LEFT JOIN payments p ON p.loan_doc_id = dl.loan_doc_id
      LEFT JOIN waived_amounts w ON w.loan_doc_id = dl.loan_doc_id
  )
SELECT
  d.loan_purpose,
  d.country_code,
  d.cust_id,
  d.loan_doc_id,
  bd.gender,
  bd.full_name,
  bd.mobile_num,
  bd.age,
  bd.age_bucket,
  bd.reg_date,
  d.loan_approver_name,
  d.cust_dis_acc_prvdr_code,
  d.Flow_disbursal_acc_prvdr_code,
  d.Flow_disbursal_acc_number,
  rm.full_name AS `RM Name`,
  rm.id AS `RM ID`,
  IFNULL(tm.full_name, rm.full_name) `TM Name`,
  vm.full_name visitor_name,
  ap.role_codes vistior_role,
  lp.last_paid_amount,
  lp.last_paid_date,
  pa.principal,
  pa.fee,
  os.principal_os,
  os.fee_os,
  IF(os.dpd <= 0, 0, os.dpd) `Overdue Days`,
  rpf.Udfc_principal_recived,
  rpf.UMTN_principal_recived,
  rpf.CCA_principal_recived,
  rpf.UATL_principal_recived,
  rpf.UEZM_principal_recived,
  rpf.RBOK_principal_recived,
  rpf.RMTN_principal_recived,
  rpf.RATL_principal_recived,
  rpf.Udfc_fee_recived,
  rpf.UMTN_fee_recived,
  rpf.CCA_fee_recived,
  rpf.UATL_fee_recived,
  rpf.UEZM_fee_recived,
  rpf.RBOK_fee_recived,
  rpf.RMTN_fee_recived,
  rpf.RATL_fee_recived,
  rpf.Udfc_charges_recived,
  rpf.UMTN_charges_recived,
  rpf.CCA_charges_recived,
  rpf.UATL_charges_recived,
  rpf.UEZM_charges_recived,
  rpf.RBOK_charges_recived,
  rpf.RMTN_charges_recived,
  rpf.RATL_charges_recived,
  rpf.Udfc_excess_recived,
  rpf.UMTN_excess_recived,
  rpf.CCA_excess_recived,
  rpf.UATL_excess_recived,
  rpf.UEZM_excess_recived,
  rpf.RBOK_excess_recived,
  rpf.RMTN_excess_recived,
  rpf.RATL_excess_recived,
  CASE
    WHEN os.dpd = 1 THEN '1 day'
    WHEN os.dpd BETWEEN 2 AND 5  THEN '2-5 days'
    WHEN os.dpd BETWEEN 6 AND 15  THEN '6-15 days'
    WHEN os.dpd BETWEEN 16 AND 30  THEN '16-30 days'
    WHEN os.dpd BETWEEN 31 AND 90  THEN '31-90 days'
    WHEN os.dpd > 90 THEN 'above 90 days'
  END `Arrear Bucket`,
  CASE
      when principal_os = 0 and fee_os = 0 Then 'Settled'
      WHEN os.dpd > 1 THEN 'overdue'
      WHEN os.dpd  between 0 and 1 Then 'due'
      WHEN os.dpd < 0 THen 'Ongoing'
  end AS `Status`,
  lv.visit_end_time `Last RM Visit Date`,
  lv.type `Last RM Visit Type`,
  lv.remarks `Last RM Visit Remarks`,
  lw.appr_date `Write Off Approved`,
  lw.write_off_date `Write Off Date`
FROM
  disbursal_loans d
  JOIN os ON os.loan_doc_id = d.loan_doc_id
  LEFT JOIN payments pa on pa.loan_doc_id = d.loan_doc_id 
  LEFT JOIN persons rm ON rm.id = d.rm_id
  LEFT JOIN persons tm ON tm.id = rm.report_to
  LEFT JOIN borrower_detailes bd ON bd.cust_id = d.cust_id
  LEFT JOIN last_payment_amount lp ON lp.loan_doc_id = d.loan_doc_id
  LEFT JOIN last_visit lv ON lv.cust_id = d.cust_id
  LEFT JOIN persons vm ON vm.id = lv.visitor_id
  LEFT JOIN loan_write_off lw ON lw.loan_doc_id = d.loan_doc_id
  LEFT JOIN app_users ap ON ap.person_id = vm.id
  LEFT JOIN recived_payment_based_on_flow rpf ON rpf.loan_doc_id = d.loan_doc_id
WHERE
  os.principal_os > 0
  OR os.fee_os > 0;