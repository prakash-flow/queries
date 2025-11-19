SET @month = '202509';
SET @country_code = 'UGA';
SET @last_day = LAST_DAY(DATE(CONCAT(@month, '01')));

WITH recentReassignments AS (
    SELECT *
    FROM (
        SELECT
            cust_id,
            from_rm_id,
            rm_id,
            reason_for_reassign,
            DATE(from_date) AS from_date,
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
latest_txn AS (
    SELECT 
        l.cust_id,
        MAX(t.txn_date) AS last_txn_date
    FROM loans l
    JOIN loan_txns t 
      ON l.loan_doc_id = t.loan_doc_id
    LEFT JOIN (
        SELECT DISTINCT r1.record_code
        FROM record_audits r1
        JOIN (
            SELECT record_code, MAX(id) AS id
            FROM record_audits
            WHERE DATE(created_at) <= @last_day
            GROUP BY record_code
        ) r2 ON r1.id = r2.id
        WHERE JSON_EXTRACT(r1.data_after, '$.status') = 'disabled'
    ) disabled_cust 
      ON l.cust_id = disabled_cust.record_code
    WHERE DATE(t.txn_date) <= @last_day
      AND l.country_code = @country_code
      AND t.txn_type = 'disbursal'
      AND l.product_id NOT IN (43, 75, 300)
      AND l.status NOT IN ('voided','hold','pending_disbursal','pending_mnl_dsbrsl')
      AND disabled_cust.record_code IS NULL
    GROUP BY l.cust_id
),
customers_with_rm AS (
    SELECT
        COALESCE(r.from_rm_id, l.flow_rel_mgr_id) AS rm_id,
        lt.cust_id,
        lt.last_txn_date
    FROM latest_txn lt
    JOIN loans l 
      ON lt.cust_id = l.cust_id
    JOIN loan_txns t
      ON l.loan_doc_id = t.loan_doc_id
     AND t.txn_date = lt.last_txn_date  
    LEFT JOIN recentReassignments r ON r.cust_id = l.cust_id
)
SELECT
	@month `Month`,
    rm_id `RM ID`,
    p.full_name `Full Name`,
    COUNT(DISTINCT CASE WHEN DATEDIFF(@last_day, last_txn_date) <= 30 THEN cust_id END) AS `Active Customer`,
    COUNT(DISTINCT CASE WHEN DATEDIFF(@last_day, last_txn_date) > 30 THEN cust_id END) AS `Inactive Customer`
FROM customers_with_rm rm
LEFT JOIN persons p ON rm.rm_id = p.id
GROUP BY rm_id;