WITH params AS (
    SELECT 
        toDate('2026-04-02') AS start_date,
        toDate('2026-04-02') AS end_date,
        'UGA'                AS country_code
),
valid_specialists AS (
    SELECT
        au.person_id AS person_id,
        concat(p.first_name, ' ', COALESCE(p.middle_name, ''), ' ', p.last_name) AS visitor_name,
        CASE
            WHEN au.role_codes = 'recovery_specialist' THEN 'Collection Officer'
            WHEN au.role_codes = 'relationship_manager' THEN 'Relationship Manager'
            WHEN au.role_codes = 'rm_support' THEN 'RMS'
            ELSE 'Unknown'
        END AS designation
    FROM app_users au
    INNER JOIN persons p ON au.person_id = p.id
    WHERE au.status = 'enabled'
      AND au.country_code = (SELECT country_code FROM params)
      AND (au.role_codes = 'recovery_specialist' OR au.role_codes = 'relationship_manager' OR au.role_codes = 'rm_support')
      AND au.person_id NOT IN (33256, 35094, 42688, 1742, 2709, 2707, 2562, 3461, 42851, 12537, 11365, 42850, 2427, 2561, 5456, 13, 5457)
),
target_loans AS (
    SELECT cust_id, loan_doc_id, due_date, loan_status, loan_purpose
    FROM (
        SELECT cust_id, loan_doc_id, loan_purpose,
               toDateTime(due_date) AS due_date,
               if(status = 'settled' AND toDate(paid_date) <= (SELECT end_date FROM params), 'settled', 'overdue') AS loan_status,
               row_number() OVER (PARTITION BY cust_id, loan_purpose ORDER BY due_date ASC) AS rn
        FROM loans
        WHERE loan_purpose IN ('float_advance', 'adj_float_advance')
          AND (
              status IN ('overdue', 'due')
              OR (status = 'settled'
                  AND toDate(paid_date) >= (SELECT start_date FROM params))
          )
    )
    WHERE rn = 1
),
visits_raw AS (
    SELECT concat('v_', toString(fv.id)) AS visit_id,
           'visit' AS effort_type,
           vs.designation AS designation,
           fv.cust_id AS cust_id,
           fv.loan_doc_id AS sched_doc_id,
           fv.visitor_id AS visitor_id,
           fv.sub_type AS purpose,
           fv.sch_status AS sch_status,
           fv.visit_start_time AS visit_start_time,
           fv.visit_end_time AS visit_end_time,
           toDate(fv.sch_date) AS s_date,
           dateDiff('minute', fv.visit_start_time, fv.visit_end_time) AS time_spent_mins
    FROM field_visits fv
    INNER JOIN valid_specialists vs ON fv.visitor_id = vs.person_id
    WHERE fv.country_code = (SELECT country_code FROM params)
      AND fv.sch_status != 'cancelled'
      AND toDate(fv.sch_date) BETWEEN (SELECT start_date FROM params) AND (SELECT end_date FROM params)
      AND (
          fv.visit_start_time IS NULL 
          OR fv.visit_end_time IS NULL 
          OR toDate(fv.visit_start_time) = toDate(fv.visit_end_time)
      )

    UNION ALL

    SELECT concat('c_', toString(cl.id)) AS visit_id,
           'call' AS effort_type,
           vs.designation AS designation,
           cl.cust_id AS cust_id,
           cl.loan_doc_id AS sched_doc_id,
           cl.call_logger_id AS visitor_id,
           cl.call_purpose AS purpose,
           'completed' AS sch_status,
           toDateTime(cl.call_start_time) AS visit_start_time,
           toDateTime(cl.call_end_time) AS visit_end_time,
           toDate(cl.created_at) AS s_date,
           dateDiff('minute', toDateTime(cl.call_start_time), toDateTime(cl.call_end_time)) AS time_spent_mins
    FROM call_logs cl
    INNER JOIN valid_specialists vs ON cl.call_logger_id = vs.person_id
    WHERE cl.country_code = (SELECT country_code FROM params)
      AND cl.call_type = 'outgoing'
      AND cl.call_purpose LIKE '%overdue%'
      AND toDate(cl.created_at) BETWEEN (SELECT start_date FROM params) AND (SELECT end_date FROM params)
      AND toDateTime(cl.call_end_time) > toDateTime(cl.call_start_time)
      AND (
          (cl.device_type = 'physical_phone' AND dateDiff('second', toDateTime(cl.call_start_time), toDateTime(cl.call_end_time)) >= 5)
          OR (cl.device_type IS NULL AND dateDiff('second', toDateTime(cl.call_start_time), toDateTime(cl.call_end_time)) >= 5)
          OR (cl.device_type IS NOT NULL AND cl.device_type != 'physical_phone')
      )
      AND cl.cust_id IS NOT NULL 
      AND cl.cust_id != ''
),
visits_with_loan AS (
    SELECT vr.*,
           l.loan_purpose AS loan_type,
           l.loan_doc_id AS target_loan_doc_id,
           l.due_date,
           l.loan_status,
           dateDiff('day', toDate(l.due_date), toDate(vr.s_date)) AS overdue_days
    FROM visits_raw vr
    INNER JOIN target_loans l ON vr.cust_id = l.cust_id
    WHERE dateDiff('day', toDate(l.due_date), toDate(vr.s_date)) > 5
),
txns_augmented AS (
    SELECT *, row_number() OVER () AS tx_unique_id
    FROM loan_txns
    WHERE txn_type = 'payment'
      AND toDate(txn_date) BETWEEN (SELECT start_date FROM params) AND (SELECT end_date FROM params)
),
ranked_activities AS (
    SELECT tx.tx_unique_id,
           tx.amount AS amount_paid,
           toDateTime(tx.txn_date) AS txn_time,
           vwl.visit_id,
           vwl.target_loan_doc_id,
           row_number() OVER (
               PARTITION BY tx.tx_unique_id 
               ORDER BY 
                   CASE 
                       WHEN vwl.effort_type = 'visit' THEN 1
                       WHEN vwl.effort_type = 'call' AND vwl.designation = 'RMS' THEN 1
                       ELSE 2
                   END ASC,
                   vwl.visit_start_time DESC
           ) as priority_rank
    FROM txns_augmented tx
    INNER JOIN visits_with_loan vwl ON vwl.target_loan_doc_id = tx.loan_doc_id
    WHERE toDate(tx.txn_date) = vwl.s_date
      AND toDateTime(tx.txn_date) >= COALESCE(vwl.visit_start_time, toDateTime(vwl.s_date))
),
payment_txns AS (
    SELECT visit_id,
           target_loan_doc_id,
           sum(amount_paid) AS amount_paid,
           max(txn_time) AS last_txn_date
    FROM ranked_activities
    WHERE priority_rank = 1
    GROUP BY visit_id, target_loan_doc_id
),
visit_summary AS (
    SELECT 
        vwl.visit_id,
        vwl.effort_type,
        vwl.visitor_id,
        vwl.cust_id,
        vwl.sched_doc_id,
        vwl.sch_status,
        vwl.purpose,
        vwl.visit_start_time,
        vwl.visit_end_time,
        vwl.time_spent_mins,
        
        -- FA Columns
        MAX(CASE WHEN vwl.loan_type = 'float_advance' THEN vwl.target_loan_doc_id END) AS fa_doc_id,
        MAX(CASE WHEN vwl.loan_type = 'float_advance' THEN vwl.overdue_days END) AS fa_overdue_days,
        MAX(CASE WHEN vwl.loan_type = 'float_advance' THEN vwl.loan_status END) AS fa_loan_status,
        SUM(CASE WHEN vwl.loan_type = 'float_advance' THEN pt.amount_paid END) AS fa_amount_collected,
        
        -- Kula Columns
        MAX(CASE WHEN vwl.loan_type = 'adj_float_advance' THEN vwl.target_loan_doc_id END) AS kula_doc_id,
        MAX(CASE WHEN vwl.loan_type = 'adj_float_advance' THEN vwl.overdue_days END) AS kula_overdue_days,
        MAX(CASE WHEN vwl.loan_type = 'adj_float_advance' THEN vwl.loan_status END) AS kula_loan_status,
        SUM(CASE WHEN vwl.loan_type = 'adj_float_advance' THEN pt.amount_paid END) AS kula_amount_collected,

        MAX(vwl.overdue_days) AS max_overdue_days,
        MAX(pt.last_txn_date) AS last_txn_date
    FROM visits_with_loan vwl
    LEFT JOIN payment_txns pt ON pt.visit_id = vwl.visit_id AND pt.target_loan_doc_id = vwl.target_loan_doc_id
    GROUP BY 
        vwl.visit_id,
        vwl.effort_type,
        vwl.visitor_id,
        vwl.cust_id,
        vwl.sched_doc_id,
        vwl.sch_status,
        vwl.purpose,
        vwl.visit_start_time,
        vwl.visit_end_time,
        vwl.time_spent_mins
),
detailed_report AS (
    SELECT
        toDate(vsum.visit_start_time) AS `Visit Date`,
        vsum.visitor_id          AS `Visitor ID`,
        vs.visitor_name          AS `Collection Officer`,
        vs.designation           AS `Designation`,
        vsum.effort_type         AS `Effort Type`,
        vsum.cust_id             AS `Customer ID`,
        CASE 
            WHEN vsum.max_overdue_days <= 5 THEN '1-5'
            WHEN vsum.max_overdue_days > 5 AND vsum.max_overdue_days <= 10 THEN '>5-10'
            WHEN vsum.max_overdue_days > 10 AND vsum.max_overdue_days <= 20 THEN '>10-20'
            WHEN vsum.max_overdue_days > 20 AND vsum.max_overdue_days <= 30 THEN '>20-30'
            WHEN vsum.max_overdue_days > 30 THEN '>30'
            ELSE 'Unknown'
        END AS `bucket`,
        COALESCE(vsum.fa_amount_collected, 0) + COALESCE(vsum.kula_amount_collected, 0) AS `paid_amount`
    FROM visit_summary vsum
    INNER JOIN valid_specialists vs ON vsum.visitor_id = vs.person_id
)
SELECT 
    `Visit Date`,
    `Visitor ID`,
    `Collection Officer`,
    `Designation`,
    `Effort Type`,
    toUInt32(COUNT(`Customer ID`)) AS `Total Cust Count`,
    toUInt32(COUNT(DISTINCT `Customer ID`)) AS `Unique Cust Count`,
    toUInt32(SUM(CASE WHEN `bucket` = '>5-10' THEN 1 ELSE 0 END)) AS `>5-10`,
    toUInt32(SUM(CASE WHEN `bucket` = '>10-20' THEN 1 ELSE 0 END)) AS `>10-20`,
    toUInt32(SUM(CASE WHEN `bucket` = '>20-30' THEN 1 ELSE 0 END)) AS `>20-30`,
    toUInt32(SUM(CASE WHEN `bucket` = '>30' THEN 1 ELSE 0 END)) AS `>30`,
    SUM(`paid_amount`) AS `Total Amount Paid`
FROM detailed_report
GROUP BY 
    `Visit Date`,
    `Visitor ID`,
    `Collection Officer`,
    `Designation`,
    `Effort Type`
ORDER BY 
    `Visit Date` ASC,
    `Designation` DESC,
    `Collection Officer` ASC,
    `Effort Type` ASC
