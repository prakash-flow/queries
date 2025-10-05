SET
  @month = '202501';

SET
  @last_day = LAST_DAY(DATE(CONCAT(@month, '01')));

SET
  @country_code = 'UGA';

SET
  @prev_month = (
    SELECT
      DATE_FORMAT(
        DATE_SUB(
          STR_TO_DATE(CONCAT(@month, '01'), '%Y%m%d'),
          INTERVAL 1 MONTH
        ),
        '%Y%m'
      )
  );

WITH
  -- 1. RM Reassignment Data
  recentReassignments AS (
    SELECT
      cust_id,
      from_rm_id
    FROM (
      SELECT
        cust_id,
        from_rm_id,
        ROW_NUMBER() OVER (
          PARTITION BY cust_id
          ORDER BY from_date ASC
        ) rn
      FROM rm_cust_assignments rm_cust
      WHERE rm_cust.country_code = @country_code
        AND rm_cust.reason_for_reassign NOT IN ('initial_assignment')
        AND DATE(rm_cust.from_date) > @last_day
    ) t
    WHERE rn = 1
  ),

  -- 2. Customers
  customers AS (
    SELECT
      COALESCE(r.from_rm_id, b.flow_rel_mgr_id) AS rm_id,
      b.cust_id,
      b.owner_person_id,
      b.reg_date,
      b.conditions
    FROM borrowers b
    LEFT JOIN recentReassignments r ON r.cust_id = b.cust_id
    WHERE b.cust_id IN (
      SELECT cust_id
      FROM reassessment_accounts
      WHERE month = @month
    )
    AND b.country_code = @country_code
  ),

  customers_with_name AS (
    SELECT
      c.*,
      CONCAT_WS(' ', p.first_name, p.middle_name, p.last_name) AS customer_name
    FROM customers c
    LEFT JOIN persons p ON p.id = c.owner_person_id
  ),

  customers_with_rm AS (
    SELECT
      cwn.*,
      rm.id AS rm_person_id,
      CONCAT_WS(' ', rm.first_name, rm.middle_name, rm.last_name) AS rm_name
    FROM customers_with_name cwn
    LEFT JOIN persons rm ON rm.id = cwn.rm_id
  ),

  -- 3. Commission Data
  commission_data AS (
    SELECT
      c.identifier,
      MAX(
        IF(
          month = DATE_FORMAT(DATE_SUB(DATE(CONCAT(@month, '01')), INTERVAL 3 MONTH), '%Y%m'),
          commission,
          0
        )
      ) AS before_3_month,
      MAX(
        IF(
          month = DATE_FORMAT(DATE_SUB(DATE(CONCAT(@month, '01')), INTERVAL 2 MONTH), '%Y%m'),
          commission,
          0
        )
      ) AS before_2_month,
      MAX(
        IF(
          month = DATE_FORMAT(DATE_SUB(DATE(CONCAT(@month, '01')), INTERVAL 1 MONTH), '%Y%m'),
          commission,
          0
        )
      ) AS before_1_month,
      CAST(
        IFNULL((
          MAX(
            IF(
              month = DATE_FORMAT(DATE_SUB(DATE(CONCAT(@month, '01')), INTERVAL 3 MONTH), '%Y%m'),
              commission,
              0
            )
          ) +
          MAX(
            IF(
              month = DATE_FORMAT(DATE_SUB(DATE(CONCAT(@month, '01')), INTERVAL 2 MONTH), '%Y%m'),
              commission,
              0
            )
          ) +
          MAX(
            IF(
              month = DATE_FORMAT(DATE_SUB(DATE(CONCAT(@month, '01')), INTERVAL 1 MONTH), '%Y%m'),
              commission,
              0
            )
          )
        ) / 3, 0) AS UNSIGNED
      ) AS average_comms
    FROM cust_commissions c
    WHERE c.identifier IN (
      SELECT alt_acc_num
      FROM reassessment_accounts
      WHERE month = @month
    )
    GROUP BY c.identifier
  ),

  account_comms AS (
    SELECT
      r.month,
      r.cust_id,
      r.account_id,
      r.acc_prvdr_code,
      r.acc_number,
      r.alt_acc_num,
      r.acc_ownership,
      r.is_primary_acc,
      CASE
        WHEN r.acc_prvdr_code = 'UMTN' THEN COALESCE(c.average_comms, 0)
        ELSE r.monthly_comms
      END AS monthly_comms,
      IFNULL(c.before_3_month, 0) AS before_3_month,
      IFNULL(c.before_2_month, 0) AS before_2_month,
      IFNULL(c.before_1_month, 0) AS before_1_month
    FROM reassessment_accounts r
    LEFT JOIN commission_data c ON c.identifier = r.alt_acc_num
    WHERE r.month = @month
  ),

  primary_account_cte AS (
    SELECT
      a.cust_id,
      SUBSTRING_INDEX(
        GROUP_CONCAT(a.acc_prvdr_code ORDER BY a.is_primary_acc DESC, a.account_id ASC),
        ',', 1
      ) AS primary_acc_prvdr_code,
      SUBSTRING_INDEX(
        GROUP_CONCAT(a.acc_number ORDER BY a.is_primary_acc DESC, a.account_id ASC),
        ',', 1
      ) AS primary_acc_number,
      SUBSTRING_INDEX(
        GROUP_CONCAT(a.alt_acc_num ORDER BY a.is_primary_acc DESC, a.account_id ASC),
        ',', 1
      ) AS primary_alt_acc_num,
      SUBSTRING_INDEX(
        GROUP_CONCAT(a.acc_ownership ORDER BY a.is_primary_acc DESC, a.account_id ASC),
        ',', 1
      ) AS primary_acc_ownership,
      SUBSTRING_INDEX(
        GROUP_CONCAT(a.is_primary_acc ORDER BY a.is_primary_acc DESC, a.account_id ASC),
        ',', 1
      ) AS is_primary_acc,
      SUM(a.monthly_comms) AS total_commission
    FROM account_comms a
    GROUP BY a.cust_id
  ),

  -- 4. Assessment Limit
  assessment_limit_cte AS (
    SELECT
      pa.cust_id,
      pa.total_commission,
      pa.primary_acc_ownership,
      CASE
        WHEN pa.total_commission < 60000 THEN 0
        WHEN pa.total_commission BETWEEN 60000 AND 119999 THEN 250000
        WHEN pa.total_commission BETWEEN 120000 AND 179999 THEN 500000
        WHEN pa.total_commission BETWEEN 180000 AND 249999 THEN 750000
        WHEN pa.total_commission BETWEEN 250000 AND 349999 THEN 1000000
        WHEN pa.total_commission BETWEEN 350000 AND 499999 THEN 1500000
        WHEN pa.total_commission BETWEEN 500000 AND 649999 THEN 2000000
        WHEN pa.total_commission BETWEEN 650000 AND 799999 THEN 2500000
        WHEN pa.total_commission BETWEEN 800000 AND 999999 THEN 3000000
        WHEN pa.total_commission BETWEEN 1000000 AND 1249999 THEN 4000000
        WHEN pa.total_commission >= 1250000 THEN 5000000
        ELSE 0
      END AS assessment_limit
    FROM primary_account_cte pa
  ),

  -- 5. Loan Records
  loan_records AS (
    SELECT *
    FROM (
      SELECT
        l.cust_id,
        l.loan_doc_id,
        l.loan_principal,
        CASE
          WHEN paid_date IS NOT NULL AND DATE(paid_date) <= @last_day THEN 'settled'
          WHEN @last_day < DATE(due_date) THEN 'ongoing'
          WHEN @last_day > DATE(due_date) THEN 'overdue'
          WHEN @last_day = DATE(due_date) THEN 'due'
        END AS last_loan_status,
        l.disbursal_date,
        l.paid_date,
        l.due_date,
        EXTRACT(YEAR_MONTH FROM l.disbursal_date) AS loan_month,
        ROW_NUMBER() OVER (
          PARTITION BY l.cust_id
          ORDER BY l.disbursal_date DESC
        ) AS rn
      FROM loans l
      WHERE DATE(l.disbursal_date) <= @last_day
        AND l.cust_id IN (
          SELECT cust_id
          FROM reassessment_accounts
          WHERE month = @month
        )
        AND l.loan_purpose = 'float_advance'
        AND l.status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
        AND l.product_id NOT IN (43, 75, 300)
    ) ranked_loans
    WHERE rn = 1
  ),

  loan_txns AS (
    SELECT
      l.loan_doc_id,
      COUNT(
        CASE WHEN DATEDIFF(lt.txn_date, l.due_date) > 1 THEN 1 END
      ) AS late_payment_count
    FROM loans l
    JOIN loan_txns lt ON l.loan_doc_id = lt.loan_doc_id
    WHERE lt.txn_type = 'payment'
      AND l.loan_purpose = 'float_advance'
      AND DATE(lt.txn_date) <= @last_day
      AND l.status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
      AND l.product_id NOT IN (43, 75, 300)
    GROUP BY l.loan_doc_id
  ),

  par_loans AS (
    SELECT
      r.cust_id,
      COUNT(l.id) AS par_5
    FROM reassessment_accounts r
    LEFT JOIN loans l ON l.cust_id = r.cust_id
    WHERE l.status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
      AND l.product_id NOT IN (43, 75, 300)
      AND r.month = @month
      AND l.loan_purpose = 'float_advance'
      AND DATEDIFF(@last_day, l.due_date) > 5
      AND (l.paid_date IS NULL OR DATEDIFF(l.paid_date, l.due_date) > 5)
    GROUP BY r.cust_id
  ),

  total_loans AS (
    SELECT
      r.cust_id,
      COUNT(l.id) AS total_loan
    FROM reassessment_accounts r
    LEFT JOIN loans l ON l.cust_id = r.cust_id
    WHERE l.status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
      AND l.product_id NOT IN (43, 75, 300)
      AND EXTRACT(YEAR_MONTH FROM l.disbursal_date) <= @month
      AND l.loan_purpose = 'float_advance'
      AND r.month = @month
    GROUP BY r.cust_id
  ),

  upgrade_amount AS (
    SELECT
      c.cust_id,
      c.current_limit,
      DATE(c.loan_repaid_date) AS upgraded_date
    FROM (
      SELECT
        crl.cust_id,
        crl.current_limit,
        crl.loan_repaid_date,
        ROW_NUMBER() OVER (
          PARTITION BY crl.cust_id
          ORDER BY crl.loan_repaid_date DESC
        ) AS rn
      FROM customer_repayment_limits crl
      WHERE EXTRACT(YEAR_MONTH FROM crl.loan_repaid_date) = @month
        AND crl.is_removed = 0
        AND crl.country_code = @country_code
        AND crl.cust_id IN (
          SELECT cust_id
          FROM reassessment_accounts
          WHERE month = @month
        )
    ) c
    WHERE rn = 1
  ),

  latest_loan_per_month AS (
    SELECT
      l.cust_id,
      EXTRACT(YEAR_MONTH FROM l.disbursal_date) AS loan_month,
      MAX(l.loan_principal) AS max_loan_principal
    FROM loans l
    WHERE l.status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
      AND l.product_id NOT IN (43, 75, 300)
      AND l.loan_purpose = 'float_advance'
      AND EXTRACT(YEAR_MONTH FROM l.disbursal_date) IN (@month, @prev_month)
    GROUP BY l.cust_id, EXTRACT(YEAR_MONTH FROM l.disbursal_date)
  ),

  loan_upgrade_check AS (
    SELECT
      cur.cust_id,
      cur.max_loan_principal > prev.max_loan_principal AS is_utilized
    FROM latest_loan_per_month prev
    JOIN latest_loan_per_month cur ON cur.cust_id = prev.cust_id
      AND cur.loan_month = @month
      AND prev.loan_month = @prev_month
  ),

  -- 6. Actual Limit (New CTE)
  actual_limit_cte AS (
    SELECT
      cust_id,
      MAX(limit_value) AS actual_limit
    FROM (
      -- Extract limits from borrowers.conditions JSON
      SELECT
        b.cust_id,
        jt.limit_value
      FROM borrowers b
      JOIN JSON_TABLE(
        b.conditions,
        '$[*]' COLUMNS (
          limit_value INT PATH '$.limit'
        )
      ) jt ON TRUE
      WHERE b.country_code = @country_code
        AND jt.limit_value > 0
      	AND cust_id IN (
      SELECT cust_id
      FROM reassessment_accounts
      WHERE month = @month
    )

      UNION ALL

      SELECT
        a.cust_id AS cust_id,
        jt.limit_value
      FROM accounts a
      JOIN JSON_TABLE(
        a.conditions,
        '$[*]' COLUMNS (
          limit_value INT PATH '$.limit'
        )
      ) jt ON TRUE
      WHERE a.country_code = @country_code
        AND jt.limit_value > 0 
      	AND cust_id IN (
      SELECT cust_id
      FROM reassessment_accounts
      WHERE month = @month
    ) AND EXTRACT(YEAR_MONTH FROM created_at) <= @month AND status = 'enabled' AND is_removed = 0
    ) combined
    GROUP BY cust_id
  )

-- Final Output
SELECT
  cwr.cust_id AS `Customer ID`,
  cwr.customer_name AS `Customer Name`,
  cwr.reg_date AS `Registration Date`,
  cwr.rm_name AS `RM Name`,
  COALESCE(tl.total_loan, 0) AS `Total Loan Count`,
  IFNULL(alcte.actual_limit, 0) AS `Actual Limit`,
  IF(al.assessment_limit = 0, 'Ineligible', al.assessment_limit) AS `Reassessed Limit`,
  lr.loan_principal AS `Last Loan Amount`,
  lr.last_loan_status AS `Last Loan Status`,
  CASE
    WHEN lr.last_loan_status = 'overdue' THEN DATEDIFF(@last_day, lr.due_date)
    ELSE 0
  END AS `Overdue Days`,
  COALESCE(lt.late_payment_count, 0) AS `Late Repayments`,
  COALESCE(pl.par_5, 0) AS `PAR >5 Count`,
  ua.current_limit AS `Upgraded Amount`,
  ua.upgraded_date AS `Upgraded Date`,
  IFNULL(luc.is_utilized, 0) AS `Utilized Upgrade`,
  pa.primary_acc_prvdr_code,
  pa.primary_acc_number,
  pa.primary_alt_acc_num,
  pa.primary_acc_ownership,
  pa.total_commission,
  lr.loan_doc_id,
  lr.disbursal_date,
  lr.due_date,
  lr.paid_date,
  lr.loan_month
FROM customers_with_rm cwr
LEFT JOIN primary_account_cte pa ON pa.cust_id = cwr.cust_id
LEFT JOIN assessment_limit_cte al ON al.cust_id = cwr.cust_id
LEFT JOIN actual_limit_cte alcte ON alcte.cust_id = cwr.cust_id
LEFT JOIN loan_records lr ON lr.cust_id = cwr.cust_id
LEFT JOIN loan_txns lt ON lt.loan_doc_id = lr.loan_doc_id
LEFT JOIN par_loans pl ON pl.cust_id = cwr.cust_id
LEFT JOIN total_loans tl ON tl.cust_id = cwr.cust_id
LEFT JOIN upgrade_amount ua ON ua.cust_id = cwr.cust_id
LEFT JOIN loan_upgrade_check luc ON luc.cust_id = cwr.cust_id
ORDER BY cwr.cust_id;