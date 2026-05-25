SET @country_code = 'UGA';

WITH disabled_customers AS (
    SELECT 
        DISTINCT r1.record_code AS cust_id,
        r1.created_by,r1.created_at,r1.remarks,
        JSON_UNQUOTE(JSON_EXTRACT(r1.data_after, '$.reason')) AS reason
    FROM record_audits r1
    JOIN (
        SELECT record_code, MAX(id) AS id
        FROM record_audits
        WHERE created_at <= NOW()
        GROUP BY record_code
    ) r2 ON r1.id = r2.id
    WHERE JSON_EXTRACT(r1.data_after, '$.status') = 'disabled'
      AND r1.country_code = @country_code
),

valid_loans AS (
    SELECT l.loan_doc_id, l.cust_id, l.due_date, l.paid_date, l.loan_appl_date,l.status,l.disbursal_date
    FROM loans l
    WHERE l.country_code = @country_code
#       AND l.product_id NOT IN (43, 75, 300)
      AND l.status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
),

loan_disbursals AS (
    SELECT l.cust_id, MAX(t.txn_date) AS txn_date
    FROM valid_loans l
    JOIN loan_txns t ON l.loan_doc_id = t.loan_doc_id
    WHERE t.txn_type = 'disbursal'
      AND t.txn_date <= NOW()
    GROUP BY l.cust_id
),

switch_disbursals AS (
    SELECT b.cust_id, MAX(t.txn_date) AS txn_date,max(l.delivery_date) as delivery_date
    FROM sales l
    JOIN sales_txns t ON l.sales_doc_id = t.sales_doc_id
    JOIN borrowers b ON b.cust_id = l.cust_id
    WHERE b.country_code = @country_code
      AND l.status = 'delivered'
      AND t.txn_date <= NOW()
    GROUP BY b.cust_id
),

fa_categorized_disabled_customers AS (
    SELECT ld.cust_id, 
           CASE WHEN ld.txn_date >= DATE_SUB(NOW(), INTERVAL 30 DAY) THEN 'active' ELSE 'inactive' END AS status
    FROM loan_disbursals ld
    JOIN disabled_customers dc ON ld.cust_id = dc.cust_id
),

sw_categorized_disabled_customers AS (
    SELECT sd.cust_id,
           CASE WHEN sd.txn_date >= DATE_SUB(NOW(), INTERVAL 30 DAY) THEN 'active' ELSE 'inactive' END AS status,sd.delivery_date
    FROM switch_disbursals sd
    JOIN disabled_customers dc ON sd.cust_id = dc.cust_id
),

latest_loan_per_cust AS (
    SELECT l.*
    FROM valid_loans l
    JOIN (
        SELECT cust_id, MAX(disbursal_date) AS max_disbursal_date
        FROM valid_loans
        GROUP BY cust_id
    ) sub ON l.cust_id = sub.cust_id AND l.disbursal_date = sub.max_disbursal_date
),

late_payment AS (
    SELECT l.cust_id, COUNT(l.loan_doc_id) AS late_payment
    FROM valid_loans l
    LEFT JOIN (
        SELECT loan_doc_id, MAX(txn_date) AS max_txn_date
        FROM loan_txns
        WHERE txn_type = 'payment'
        GROUP BY loan_doc_id
    ) t ON l.loan_doc_id = t.loan_doc_id
    WHERE l.status = 'settled' AND DATEDIFF(t.max_txn_date, l.due_date) > 1
    GROUP BY l.cust_id
),

ontime_repayment AS (
    SELECT l.cust_id,
           ROUND(SUM(IF(DATE(t.max_txn_date) <= DATE_ADD(l.due_date, INTERVAL 1 DAY), 1, 0)) / COUNT(l.loan_doc_id), 2) AS ontime_repayment_rate
    FROM valid_loans l
    LEFT JOIN (
        SELECT loan_doc_id, MAX(txn_date) AS max_txn_date
        FROM loan_txns
        WHERE txn_type = 'payment'
        GROUP BY loan_doc_id
    ) t ON l.loan_doc_id = t.loan_doc_id
    WHERE l.status = 'settled' AND l.paid_date <= NOW()
    GROUP BY l.cust_id
)

# select *  from (

SELECT 
    b.cust_id AS `Cust ID`,
    CASE 
        WHEN l.status = 'overdue' THEN 'overdue'
        WHEN c.status IS NOT NULL THEN c.status
        ELSE 'N/A'
    END AS `Activity Status`,
    b.reg_date AS `Reg date`,
    IFNULL(date(l.disbursal_date) ,'N/A') AS `Churn date`,
    IFNULL(date(d.created_at) ,'N/A') AS `Disable date`,
    IF(l.disbursal_date IS NOT NULL AND d.created_at IS NOT NULL,DATEDIFF(d.created_at, l.disbursal_date),'N/A') AS `Diff between churn and disable`,
    CASE 
        WHEN d.created_by <> 0 THEN 'Manual Disable'
        WHEN d.reason IN ('90_day_inactivity','inactive') THEN 'In-active'
        WHEN d.reason = 'agreement_expired' THEN 'Agreement expiry'
        WHEN d.reason = 'more_than_30_day_overdue' THEN 'Overdue'
        ELSE 'Others'
    END AS `Reason for disable`,
    reason AS `Source Disable Reason`,
    d.remarks AS `Disable Remarks`,
    IFNULL(date(sw.delivery_date) ,'N/A') AS `Switch Delivery Date`,
    IFNULL(sw.status, 'N/A') AS `Float Switch status`,
    b.tot_loans AS `Total loans`,
    IF(lp.late_payment IS NULL, 0, lp.late_payment) AS `Total late loans`,
    IFNULL(o.ontime_repayment_rate, 'N/A') AS `Ontime repayment percentage`
FROM borrowers b
LEFT JOIN fa_categorized_disabled_customers c ON c.cust_id = b.cust_id
LEFT JOIN latest_loan_per_cust l ON l.cust_id = b.cust_id
LEFT JOIN disabled_customers d ON d.cust_id = b.cust_id
LEFT JOIN sw_categorized_disabled_customers sw ON sw.cust_id = b.cust_id
LEFT JOIN late_payment lp ON lp.cust_id = b.cust_id
LEFT JOIN ontime_repayment o ON o.cust_id = b.cust_id
WHERE d.cust_id IS NOT NULL
# ) as aa where   `Activity Status` is not null 
  ;