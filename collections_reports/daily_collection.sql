-- the query runs only for one day, without considering the raization date only for fa and Kula


WITH params AS (
    SELECT toDate('2026-03-01') AS start_date, toDate('2026-03-01') AS end_date
),

loan_base AS (
    SELECT l.loan_doc_id AS loan_doc_id,
        multiIf(l.country_code = 'UGA', 'UGA (UGX)', l.country_code = 'RWA', 'RWA (RWF)',l.country_code = 'MDG', 'MDG (MGA)', l.country_code) AS market,
        l.country_code AS country_code,
        toDate(l.due_date) AS due_date,
        l.loan_principal AS loan_principal,
        l.flow_fee AS flow_fee,
        l.loan_purpose AS loan_purpose,
        rm.full_name AS rm_name,
        ifNull(tm.full_name, rm.full_name) AS tm_name,
        (l.loan_principal + l.flow_fee) AS initial_due
    FROM loans l
    JOIN (
        SELECT loan_doc_id
        FROM loan_txns
        WHERE txn_type = 'disbursal'
        AND country_code IN :countries
        AND toDate(txn_date) <= (SELECT start_date FROM params)
        GROUP BY loan_doc_id
    ) lt ON lt.loan_doc_id = l.loan_doc_id
    LEFT JOIN persons rm ON rm.id = l.flow_rel_mgr_id
    LEFT JOIN persons tm ON tm.id = rm.report_to
    WHERE l.country_code IN :countries AND l.loan_purpose IN ('float_advance','adj_float_advance') 
    AND l.status NOT IN ('voided','hold','pending_disbursal','pending_mnl_dsbrsl')
    AND l.product_id NOT IN (SELECT id FROM loan_products WHERE product_type = 'float_vending')
),

payments AS (
    SELECT loan_doc_id,
        SUM(IF(txn_type='payment', ifNull(principal,0), 0)) AS principal_paid,
        SUM(IF(txn_type = 'payment', ifNull(fee,0), 0)) AS fee_paid,
        SUM(IF(txn_type IN ('payment','fee_waiver'), ifNull(fee,0), 0)) AS fee_with_fee_waiver,
        maxIf(toDate(txn_date), txn_type IN ('payment')) AS last_payment_date
    FROM loan_txns
    WHERE toDate(txn_date) <= (SELECT start_date FROM params)
    AND country_code IN :countries
    GROUP BY loan_doc_id
),

prepaid AS (
    SELECT lt.loan_doc_id,
        SUM(IF(toDate(lt.txn_date) < toDate(lb.due_date),
        (IF(lt.txn_type='payment', ifNull(lt.principal,0), 0)) + (IF(lt.txn_type IN('payment'), ifNull(lt.fee,0), 0)), 0)) AS prepaid_amount
    FROM loan_txns lt 
    JOIN (SELECT DISTINCT loan_doc_id, due_date FROM loan_base) lb ON lb.loan_doc_id = lt.loan_doc_id 
    WHERE toDate(lt.txn_date) <= (SELECT start_date FROM params)
    AND lt.country_code IN :countries
    GROUP BY lt.loan_doc_id
),

loan_state AS (
    SELECT lb.*, 
        (lb.loan_principal + lb.flow_fee) - (coalesce(p.principal_paid, 0) + coalesce(p.fee_with_fee_waiver, 0)) AS outstanding,
        lb.loan_principal - coalesce(p.principal_paid, 0) AS principal_os,
        lb.flow_fee - coalesce(p.fee_with_fee_waiver, 0) AS fee_os, 
        coalesce(p.principal_paid, 0) + coalesce(p.fee_paid, 0) AS total_cash_paid,
        p.last_payment_date
    FROM loan_base lb LEFT JOIN payments p ON lb.loan_doc_id = p.loan_doc_id
),

dues AS (
    SELECT
        main.due_date AS report_date,
        main.market AS market,
        main.product_type AS product_type,
        main.tm_name AS tm_name,
        main.rm_name AS rm_name, 
        SUM(main.loan_principal + main.flow_fee) AS current_due,
        SUM(coalesce(pp.prepaid_amount, 0)) AS prepaid_dues,
        SUM(IF(main.outstanding > 0 OR toDate(main.last_payment_date) >= toDate(main.due_date), coalesce(pp.prepaid_amount, 0), 0)) AS prepaid_open_amount,
        SUM(IF(main.outstanding <= 0 AND toDate(main.last_payment_date) < toDate(main.due_date), coalesce(pp.prepaid_amount, 0), 0)) AS prepaid_closed_amount,
        SUM(IF(main.outstanding > 0 AND coalesce(pp.prepaid_amount, 0) > 0, 1, 0)) AS prepaid_open_count,
        SUM(IF(main.outstanding <= 0 AND toDate(main.last_payment_date) < toDate(main.due_date), 1, 0)) AS prepaid_closed_count,
        COUNT(*) AS accounts_due,
        SUM(IF(main.outstanding <= 0 AND toDate(main.last_payment_date) = toDate(main.due_date), 1, 0)) AS current_loans_closed,
        SUM(IF(main.outstanding <= 0 AND toDate(main.last_payment_date) < toDate(main.due_date), 1, 0)) AS pre_closed_loans,
        SUM(IF(main.outstanding > 0 AND main.total_cash_paid > 0, 1, 0)) AS loans_partial
    FROM (
        SELECT ls.loan_doc_id, ls.due_date, ls.market, ls.loan_purpose AS product_type, ls.rm_name, ls.tm_name, ls.loan_principal, ls.flow_fee, ls.outstanding, ls.total_cash_paid, ls.principal_os, ls.fee_os, ls.last_payment_date
        FROM loan_state ls
    ) main
    LEFT JOIN prepaid pp ON main.loan_doc_id = pp.loan_doc_id
    WHERE toDate(main.due_date) = (SELECT start_date FROM params)
    GROUP BY report_date, market, product_type, tm_name, rm_name
),

collections AS (
    SELECT
        toDate(txn_date) AS report_date,
        lb.market as market,
        lb.product_type as product_type,
        lb.tm_name as tm_name, 
        lb.rm_name as rm_name, 
        SUM(IF(toDate(lb.due_date) = toDate(txn_date), IF(txn_type='payment', ifNull(principal,0) + ifNull(fee,0), 0), 0)) AS current_collection,
        SUM(IF(toDate(lb.due_date) = toDate(txn_date) AND ls.outstanding > 0, IF(txn_type='payment', ifNull(principal,0) + ifNull(fee,0), 0), 0)) AS current_collection_open,
        SUM(IF(toDate(lb.due_date) = toDate(txn_date) AND ls.outstanding <= 0 AND toDate(ls.last_payment_date) = toDate(txn_date), IF(txn_type='payment', ifNull(principal,0) + ifNull(fee,0), 0), 0)) AS current_collection_closed,
        
        SUM(IF(toDate(lb.due_date) > toDate(txn_date), IF(txn_type='payment', ifNull(principal,0) + ifNull(fee,0), 0), 0)) AS prepayment,
        SUM(IF(toDate(lb.due_date) > toDate(txn_date) AND ls.outstanding > 0, IF(txn_type='payment', ifNull(principal,0) + ifNull(fee,0), 0), 0)) AS prepayment_open,
        SUM(IF(toDate(lb.due_date) > toDate(txn_date) AND ls.outstanding <= 0 AND toDate(ls.last_payment_date) = toDate(txn_date), IF(txn_type='payment', ifNull(principal,0) + ifNull(fee,0), 0), 0)) AS prepayment_closed,
        
        SUM(IF(addDays(toDate(lb.due_date), 1) < toDate(txn_date), IF(txn_type='payment', ifNull(principal,0) + ifNull(fee,0), 0), 0)) AS overdue_collection,
        SUM(IF(addDays(toDate(lb.due_date), 1) < toDate(txn_date) AND ls.outstanding > 0, IF(txn_type='payment', ifNull(principal,0) + ifNull(fee,0), 0), 0)) AS overdue_collection_open,
        SUM(IF(addDays(toDate(lb.due_date), 1) < toDate(txn_date) AND ls.outstanding <= 0 AND toDate(ls.last_payment_date) = toDate(txn_date), IF(txn_type='payment', ifNull(principal,0) + ifNull(fee,0), 0), 0)) AS overdue_collection_closed,
        
        SUM(IF(txn_type='payment', ifNull(principal,0), 0)) AS principal_collected,
        SUM(IF(txn_type='payment', ifNull(fee,0), 0)) AS fee_collected,
        SUM(IF(txn_type='payment', ifNull(principal,0) + ifNull(fee,0), 0)) AS total_amount_collected,
        SUM(IF(toDate(txn_date) <= addDays(toDate(lb.due_date), 1), IF(txn_type='payment', ifNull(principal,0) + ifNull(fee,0), 0), 0)) AS ontime_collection_amount,

        COUNT(DISTINCT IF(toDate(lb.due_date) = toDate(txn_date) AND ls.outstanding > 0, lt.loan_doc_id, NULL)) AS current_open_count,
        COUNT(DISTINCT IF(toDate(lb.due_date) = toDate(txn_date) AND ls.outstanding <= 0 AND toDate(ls.last_payment_date) = toDate(txn_date), lt.loan_doc_id, NULL)) AS current_closed_count,
        COUNT(DISTINCT IF(toDate(lb.due_date) > toDate(txn_date) AND ls.outstanding > 0, lt.loan_doc_id, NULL)) AS future_open_count,
        COUNT(DISTINCT IF(toDate(lb.due_date) > toDate(txn_date) AND ls.outstanding <= 0 AND toDate(ls.last_payment_date) = toDate(txn_date), lt.loan_doc_id, NULL)) AS future_closed_count,
        COUNT(DISTINCT IF(addDays(toDate(lb.due_date), 1) < toDate(txn_date) AND ls.outstanding > 0, lt.loan_doc_id, NULL)) AS overdue_open_count,
        COUNT(DISTINCT IF(addDays(toDate(lb.due_date), 1) < toDate(txn_date) AND ls.outstanding <= 0 AND toDate(ls.last_payment_date) = toDate(txn_date), lt.loan_doc_id, NULL)) AS overdue_closed_count,
        COUNT(DISTINCT IF(toDate(txn_date) = addDays(toDate(lb.due_date), 1) AND ls.outstanding > 0, lt.loan_doc_id, NULL)) AS grace_open_count,
        COUNT(DISTINCT IF(toDate(txn_date) = addDays(toDate(lb.due_date), 1) AND ls.outstanding <= 0 AND toDate(ls.last_payment_date) = toDate(txn_date), lt.loan_doc_id, NULL)) AS grace_closed_count,
        
        SUM(IF(toDate(txn_date) = toDate(lb.due_date), IF(txn_type='payment', ifNull(principal,0) + ifNull(fee,0), 0), 0)) AS same_day_collection,
        SUM(IF(toDate(txn_date) = addDays(toDate(lb.due_date), 1), IF(txn_type='payment', ifNull(principal,0) + ifNull(fee,0), 0), 0)) AS grace_collection,
        SUM(IF(toDate(txn_date) = addDays(toDate(lb.due_date), 1) AND ls.outstanding > 0, IF(txn_type='payment', ifNull(principal,0) + ifNull(fee,0), 0), 0)) AS grace_collection_open,
        SUM(IF(toDate(txn_date) = addDays(toDate(lb.due_date), 1) AND ls.outstanding <= 0 AND toDate(ls.last_payment_date) = toDate(txn_date), IF(txn_type='payment', ifNull(principal,0) + ifNull(fee,0), 0), 0)) AS grace_collection_closed
    FROM loan_txns AS lt
    JOIN (SELECT loan_doc_id, due_date, market, loan_purpose AS product_type, rm_name, tm_name FROM loan_base) lb on lb.loan_doc_id = lt.loan_doc_id
    LEFT JOIN loan_state ls on ls.loan_doc_id = lt.loan_doc_id
    WHERE lt.txn_type IN ('payment','fee_waiver') AND toDate(lt.txn_date) = (SELECT start_date FROM params) AND lt.country_code IN :countries
    GROUP BY report_date, lb.market, lb.product_type, lb.tm_name, lb.rm_name
),

overdue AS (
    SELECT
        (SELECT start_date FROM params) AS report_date,
        ls.market AS market,
        ls.product_type AS product_type,
        ls.tm_name AS tm_name,
        ls.rm_name AS rm_name, 
        SUM(ls.principal_os) AS principal_overdue,
        SUM(ls.fee_os) AS fee_overdue,
        sum(ls.principal_os + ls.fee_os) as total_overdue,
        COUNT(DISTINCT ls.loan_doc_id) AS overdue_loans,
        SUM(IF(dateDiff('day', toDate(ls.due_date), (SELECT start_date FROM params)) BETWEEN 2 AND 10, ls.principal_os + ls.fee_os, 0)) AS par_2_10_amount,
        COUNT(DISTINCT IF(dateDiff('day', toDate(ls.due_date), (SELECT start_date FROM params)) BETWEEN 2 AND 10, ls.loan_doc_id, NULL)) AS par_2_10_count,
        SUM(IF(dateDiff('day', toDate(ls.due_date), (SELECT start_date FROM params)) > 10, ls.principal_os + ls.fee_os, 0)) AS par_10_plus_amount,
        COUNT(DISTINCT IF(dateDiff('day', toDate(ls.due_date), (SELECT start_date FROM params)) > 10, ls.loan_doc_id, NULL)) AS par_10_plus_count
    FROM (
        SELECT loan_doc_id, market, loan_purpose AS product_type, rm_name, tm_name, principal_os, fee_os, outstanding, due_date FROM loan_state
    ) AS ls 
    WHERE ls.outstanding > 0 AND dateDiff('day', toDate(ls.due_date), (SELECT start_date FROM params)) >= 2
    GROUP BY report_date, market, product_type, tm_name, rm_name
)

-- Final step combining all metrics mirroring the behavior of pd.merge(how='outer')
SELECT 
    COALESCE(d.report_date, c.report_date, o.report_date) AS report_date,
    COALESCE(d.market, c.market, o.market) AS market,
    COALESCE(d.product_type, c.product_type, o.product_type) AS product_type,
    COALESCE(d.tm_name, c.tm_name, o.tm_name) AS tm_name,
    COALESCE(d.rm_name, c.rm_name, o.rm_name) AS rm_name,

    IFNULL(d.current_due, 0) AS current_due,
    IFNULL(d.prepaid_dues, 0) AS prepaid_dues,
    IFNULL(d.prepaid_open_amount, 0) AS prepaid_open_amount,
    IFNULL(d.prepaid_closed_amount, 0) AS prepaid_closed_amount,
    IFNULL(d.prepaid_open_count, 0) AS prepaid_open_count,
    IFNULL(d.prepaid_closed_count, 0) AS prepaid_closed_count,
    IFNULL(d.accounts_due, 0) AS accounts_due,
    IFNULL(d.current_loans_closed, 0) AS current_loans_closed,
    IFNULL(d.pre_closed_loans, 0) AS pre_closed_loans,
    IFNULL(d.loans_partial, 0) AS loans_partial,

    IFNULL(c.current_collection, 0) AS current_collection,
    IFNULL(c.current_collection_open, 0) AS current_collection_open,
    IFNULL(c.current_collection_closed, 0) AS current_collection_closed,
    IFNULL(c.current_open_count, 0) AS current_open_count,
    IFNULL(c.current_closed_count, 0) AS current_closed_count,
    IFNULL(c.prepayment, 0) AS prepayment,
    IFNULL(c.prepayment_open, 0) AS prepayment_open,
    IFNULL(c.prepayment_closed, 0) AS prepayment_closed,
    IFNULL(c.future_open_count, 0) AS future_open_count,
    IFNULL(c.future_closed_count, 0) AS future_closed_count,
    IFNULL(c.grace_collection, 0) AS grace_collection,
    IFNULL(c.grace_collection_open, 0) AS grace_collection_open,
    IFNULL(c.grace_collection_closed, 0) AS grace_collection_closed,
    IFNULL(c.grace_open_count, 0) AS grace_open_count,
    IFNULL(c.grace_closed_count, 0) AS grace_closed_count,
    IFNULL(c.overdue_collection, 0) AS overdue_collection,
    IFNULL(c.overdue_collection_open, 0) AS overdue_collection_open,
    IFNULL(c.overdue_collection_closed, 0) AS overdue_collection_closed,
    IFNULL(c.overdue_open_count, 0) AS overdue_open_count,
    IFNULL(c.overdue_closed_count, 0) AS overdue_closed_count,
    IFNULL(c.principal_collected, 0) AS principal_collected,
    IFNULL(c.fee_collected, 0) AS fee_collected,
    IFNULL(c.total_amount_collected, 0) AS total_amount_collected,
    IFNULL(c.ontime_collection_amount, 0) AS ontime_collection_amount,

    IFNULL(o.principal_overdue, 0) AS principal_overdue,
    IFNULL(o.fee_overdue, 0) AS fee_overdue,
    IFNULL(o.overdue_loans, 0) AS overdue_loans,
    IFNULL(o.par_2_10_amount, 0) AS par_2_10_amount,
    IFNULL(o.par_2_10_count, 0) AS par_2_10_count,
    IFNULL(o.par_10_plus_amount, 0) AS par_10_plus_amount,
    IFNULL(o.par_10_plus_count, 0) AS par_10_plus_count

FROM dues d
FULL OUTER JOIN collections c 
    ON  d.report_date = c.report_date 
    AND d.market = c.market 
    AND d.product_type = c.product_type 
    AND d.tm_name = c.tm_name 
    AND d.rm_name = c.rm_name
FULL OUTER JOIN overdue o 
    ON  COALESCE(d.report_date, c.report_date) = o.report_date 
    AND COALESCE(d.market, c.market) = o.market 
    AND COALESCE(d.product_type, c.product_type) = o.product_type 
    AND COALESCE(d.tm_name, c.tm_name) = o.tm_name 
    AND COALESCE(d.rm_name, c.rm_name) = o.rm_name
