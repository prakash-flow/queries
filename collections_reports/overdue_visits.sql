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
            ELSE 'Unknown'
        END AS designation
    FROM app_users au
    INNER JOIN persons p ON au.person_id = p.id
    WHERE au.status = 'enabled'
      AND au.country_code = (SELECT country_code FROM params)
      AND (au.role_codes = 'recovery_specialist' OR au.role_codes = 'relationship_manager')
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
                  AND toDate(paid_date) >= (SELECT start_date FROM params)
                  AND toDate(paid_date) <= (SELECT end_date FROM params))
          )
    )
    WHERE rn = 1
),
visits_raw AS (
    SELECT fv.id AS visit_id,
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
    and fv.sch_status != 'cancelled'
      AND toDate(fv.sch_date) BETWEEN (SELECT start_date FROM params) AND (SELECT end_date FROM params)
      AND (
          fv.visit_start_time IS NULL 
          OR fv.visit_end_time IS NULL 
          OR toDate(fv.visit_start_time) = toDate(fv.visit_end_time)
      )
),
visits_with_loan AS (
    SELECT vr.*,
           l.loan_purpose AS loan_type,
           l.loan_doc_id AS target_loan_doc_id,
           l.due_date,
           l.loan_status,
           intDiv(dateDiff('second', l.due_date, toDateTime(vr.s_date)), 86400) AS overdue_days
    FROM visits_raw vr
    INNER JOIN target_loans l ON vr.cust_id = l.cust_id
    WHERE intDiv(dateDiff('second', l.due_date, toDateTime(vr.s_date)), 86400) > 5
),
next_visits AS (
    SELECT nv1.visit_id AS visit_id, 
           nv1.target_loan_doc_id AS target_loan_doc_id, 
           min(vr.visit_start_time) AS next_time
    FROM visits_with_loan nv1
    INNER JOIN visits_raw vr ON vr.sched_doc_id = nv1.target_loan_doc_id
    WHERE vr.visit_start_time > nv1.visit_start_time
    GROUP BY nv1.visit_id, nv1.target_loan_doc_id
),
payment_txns AS (
    SELECT ptx_vwl.visit_id AS visit_id,
           ptx_vwl.target_loan_doc_id AS target_loan_doc_id, 
           sum(tx.amount) AS amount_paid,
           max(toDateTime(tx.txn_date)) AS last_txn_date
    FROM visits_with_loan ptx_vwl
    INNER JOIN loan_txns tx ON tx.loan_doc_id = ptx_vwl.target_loan_doc_id
    LEFT JOIN next_visits nv ON nv.visit_id = ptx_vwl.visit_id AND nv.target_loan_doc_id = ptx_vwl.target_loan_doc_id
    WHERE tx.txn_type = 'payment'
      AND toDate(tx.txn_date) = ptx_vwl.s_date
      AND toDateTime(tx.txn_date) >= COALESCE(ptx_vwl.visit_start_time, toDateTime(ptx_vwl.s_date))
      AND (nv.next_time IS NULL OR toDateTime(tx.txn_date) < nv.next_time)
    GROUP BY ptx_vwl.visit_id, ptx_vwl.target_loan_doc_id
),
visit_summary AS (
    SELECT 
        vwl.visit_id,
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
        vwl.visitor_id,
        vwl.cust_id,
        vwl.sched_doc_id,
        vwl.sch_status,
        vwl.purpose,
        vwl.visit_start_time,
        vwl.visit_end_time,
        vwl.time_spent_mins
)
SELECT
    toDate(vsum.visit_start_time) AS `Visit Date`,
    vsum.cust_id             AS `Customer ID`,
    COALESCE(nullIf(vsum.sched_doc_id, ''), vsum.fa_doc_id, vsum.kula_doc_id) AS `Visited Loan Doc ID`,
    vsum.max_overdue_days    AS `Overdue Days`,
    vsum.visitor_id          AS `Visitor ID`,
    vs.visitor_name          AS `Collection Officer`,
    vsum.time_spent_mins     AS `Time Spent`,
    vsum.purpose             AS `Purpose`,
    
    -- FA Details
    vsum.fa_doc_id           AS `FA Loan Doc ID`,
    vsum.fa_overdue_days     AS `FA Overdue Days`,
    COALESCE(vsum.fa_amount_collected, 0) AS `FA Paid Amt`,
    vsum.fa_loan_status      AS `FA Loan Status`,

    -- Kula Details
    vsum.kula_doc_id         AS `Kula Loan Doc ID`,
    vsum.kula_overdue_days   AS `Kula Overdue Days`,
    COALESCE(vsum.kula_amount_collected, 0) AS `Kula Paid Amt`,
    vsum.kula_loan_status    AS `Kula Loan Status`,

    COALESCE(vsum.fa_amount_collected, 0) + COALESCE(vsum.kula_amount_collected, 0) AS `Total Paid Amt`,

    -- Optional / Extra Details
    vs.designation           AS `Designation`,
    vsum.visit_id            AS `Visit ID`,
    vsum.sch_status          AS `Visit Status`,
    vsum.visit_start_time    AS `Start Time`,
    vsum.visit_end_time      AS `End Time`,
    vsum.last_txn_date       AS `Latest Txn Timestamp`
FROM visit_summary vsum
INNER JOIN valid_specialists vs ON vsum.visitor_id = vs.person_id
ORDER BY vs.designation DESC, vs.visitor_name ASC, vsum.visit_start_time ASC, vsum.cust_id ASC
