-- Set parameters
SET @country_code = 'UGA';
SET @month = '202509'; 
SET @last_day = LAST_DAY(DATE(CONCAT(@month, "01")));
SET @start_month = DATE_FORMAT(DATE_SUB(DATE(CONCAT(@month,'01')), INTERVAL 5 MONTH), '%Y%m');
SET @realization_date = IFNULL(
    (
        SELECT closure_date
        FROM closure_date_records
        WHERE month = @month
          AND status = 'enabled'
          AND country_code = @country_code
    ),
    NOW()
);

WITH recentReassignments AS (
    SELECT cust_id, from_rm_id
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
ranked_records AS (
    SELECT
        record_code,
        JSON_UNQUOTE(JSON_EXTRACT(data_after, '$.status')) AS `status`,
        ROW_NUMBER() OVER (
            PARTITION BY record_code
            ORDER BY created_at DESC
        ) AS rn
    FROM record_audits
    WHERE audit_type = 'status_change'
      AND country_code = @country_code
      AND DATE(created_at) <= @last_day
),
customers AS (
    SELECT
        COALESCE(r.from_rm_id, b.flow_rel_mgr_id) AS rm_id,
        SUM(CASE WHEN COALESCE(rr.status, b.status) IN ('disabled') THEN 1 ELSE 0 END) AS Disabled_Customers,
        SUM(CASE WHEN COALESCE(rr.status, b.status) IN ('enabled') THEN 1 ELSE 0 END) AS Enabled_Customers,
        COUNT(*) AS Total_Customers
    FROM borrowers b
    LEFT JOIN recentReassignments r ON r.cust_id = b.cust_id
    LEFT JOIN ranked_records rr ON rr.record_code = b.cust_id AND rr.rn = 1
    WHERE EXTRACT(YEAR_MONTH FROM b.reg_date) <= @month
      AND b.country_code = @country_code
    GROUP BY COALESCE(r.from_rm_id, b.flow_rel_mgr_id)
),
loan_principal AS (
    SELECT 
        COALESCE(rr.from_rm_id, l.flow_rel_mgr_id) AS rm_id,
        l.loan_doc_id,
        l.cust_id,
        l.loan_principal,
        l.due_date
    FROM loans l
    JOIN loan_txns lt ON lt.loan_doc_id = l.loan_doc_id
    LEFT JOIN recentReassignments rr ON rr.cust_id = l.cust_id
    WHERE lt.txn_type = 'disbursal'
      AND lt.realization_date <= @realization_date
      AND l.country_code = @country_code
      AND DATE(l.disbursal_date) <= @last_day
      AND l.product_id NOT IN (43, 75, 300)
      AND l.status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
      AND l.loan_doc_id NOT IN (
            SELECT loan_doc_id 
            FROM loan_write_off 
            WHERE write_off_date <= @last_day 
              AND write_off_status IN ('approved', 'partially_recovered', 'recovered') 
              AND country_code = @country_code
      )
),
loan_payments AS (
    SELECT 
        loan_doc_id,
        SUM(CASE WHEN txn_type = 'payment' THEN principal ELSE 0 END) AS total_paid_principal
    FROM loan_txns
    WHERE DATE(txn_date) <= @last_day
      AND realization_date <= @realization_date
    GROUP BY loan_doc_id
),
loan_os AS (
    SELECT
         lp.rm_id,
        SUM(GREATEST(lp.loan_principal - COALESCE(p.total_paid_principal,0),0)) AS Total_OS,
        SUM(IF(GREATEST(lp.loan_principal - COALESCE(p.total_paid_principal,0),0) > 0 
               AND DATEDIFF(@last_day, lp.due_date) > 1,
               GREATEST(lp.loan_principal - COALESCE(p.total_paid_principal,0),0),0)) AS Overdue_Amount,
        SUM(IF(GREATEST(lp.loan_principal - COALESCE(p.total_paid_principal,0),0) > 0 
               AND DATEDIFF(@last_day, lp.due_date) > 1,1,0)) AS Overdue_Count
    FROM loan_principal lp
    LEFT JOIN loan_payments p ON p.loan_doc_id = lp.loan_doc_id
    GROUP BY lp.rm_id
),
ontime_repayments AS (
  SELECT
    COALESCE(rr.from_rm_id, l.flow_rel_mgr_id) AS rm_id,
    ROUND(
      100 * SUM(
        CASE
          WHEN t.max_txn_date <= DATE_ADD(l.due_date, INTERVAL 1 DAY) THEN 1
          ELSE 0
        END
      ) / COUNT(l.loan_doc_id),
      2
    ) AS ontime_repayment_rate,
    SUM(
      CASE
        WHEN t.max_txn_date <= DATE_ADD(l.due_date, INTERVAL 1 DAY) THEN 1
        ELSE 0
      END
    ) AS ontime_settle_count,
    COUNT(l.loan_doc_id) AS total_loan_taken
  FROM loans l
  JOIN (
    SELECT
      loan_doc_id,
      MAX(txn_date) AS max_txn_date
    FROM loan_txns
    WHERE txn_type = 'payment'
      AND DATE(txn_date) <= @last_day
      AND DATE(realization_date) <= @realization_date
    GROUP BY loan_doc_id
  ) t ON l.loan_doc_id = t.loan_doc_id
  LEFT JOIN recentReassignments rr ON rr.cust_id = l.cust_id
  WHERE
    l.status = 'settled'
    AND l.disbursal_date >= EXTRACT(YEAR_MONTH FROM DATE_SUB(@last_day, INTERVAL 6 MONTH))
    AND l.loan_purpose = 'float_advance'
    AND DATE(l.paid_date) <= @last_day
    AND EXTRACT(YEAR_MONTH FROM l.disbursal_date) BETWEEN @start_month AND @month
    AND l.product_id NOT IN (43, 75, 300)
    AND l.status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
    AND l.country_code = @country_code
  GROUP BY COALESCE(rr.from_rm_id, l.flow_rel_mgr_id)
)
SELECT 
    UPPER(p.full_name) AS `RM Name`,
    c.Enabled_Customers,
    c.Disabled_Customers,
    c.Total_Customers,
    COALESCE(lo.Total_OS,0) AS `Total OS`,
    COALESCE(lo.Overdue_Amount,0) AS `Overdue Amount`,
    COALESCE(lo.Overdue_Count,0) AS `Overdue Count`,
    COALESCE(o.ontime_repayment_rate,0) AS `On-time Repayment %`,
    COALESCE(o.ontime_settle_count,0) AS `On-time Settled Loans`,
    COALESCE(o.total_loan_taken,0) AS `Total Loans Taken`
FROM customers c
LEFT JOIN loan_os lo ON c.rm_id = lo.rm_id
LEFT JOIN ontime_repayments o ON c.rm_id = o.rm_id
LEFT JOIN persons p ON p.id = c.rm_id
HAVING `RM Name` IS NOT NULL
ORDER BY `RM Name`;