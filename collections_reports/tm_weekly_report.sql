-- the query gives the collection performance of tms in uga and their weekly collection performace on fa & kula for the inputed week.

WITH params AS (
    SELECT 
        toDate('2026-03-22') AS start_date,
        toDate('2026-03-28') AS end_date,
        'UGA' AS country_code
),
closure AS (
    SELECT coalesce(
        max(closure_date), 
        parseDateTimeBestEffort(concat(toString((SELECT end_date FROM params)), ' 23:59:59'))
    ) AS closure_date
    FROM flow_api.closure_date_records
    WHERE status='enabled'
      AND month = toYear((SELECT end_date FROM params)) * 100 + toMonth((SELECT end_date FROM params))
      AND country_code = (SELECT country_code FROM params)
),
loan_principal AS (
    SELECT
        l.loan_doc_id,
        l.cust_id,
        l.flow_rel_mgr_id AS rm_id,
        l.loan_principal,
        l.flow_fee,
        toDate(l.due_date) AS due_date,
        toDate(l.disbursal_date) AS disbursal_date
    FROM flow_api.loans l
    WHERE l.loan_doc_id IN (
        SELECT loan_doc_id 
        FROM flow_api.loan_txns 
        WHERE txn_type='disbursal' 
          AND realization_date <= (SELECT closure_date FROM closure)
    )
    AND l.country_code = (SELECT country_code FROM params)
    AND l.loan_purpose IN ('float_advance','adj_float_advance')
    AND l.status NOT IN ('voided','hold','pending_disbursal','pending_mnl_dsbrsl')
    AND l.product_id NOT IN (
        SELECT id FROM flow_api.loan_products WHERE product_type = 'float_vending'
    )
),
loan_payments AS (
    SELECT
        loan_doc_id,
        SUM(IF(txn_type='payment', principal, 0)) AS principal_paid,
        SUM(IF(txn_type IN ('payment'), fee, 0)) AS fee_paid,
        SUM(IF(txn_type IN ('payment', 'fee_waiver'), fee, 0)) AS fee_with_fee_waiver,
        maxIf(toDate(txn_date), txn_type in ('payment') AND (principal>0 OR fee>0)) AS last_payment_date
    FROM flow_api.loan_txns
    WHERE realization_date <= (SELECT closure_date FROM closure)
      AND country_code = (SELECT country_code FROM params)
    GROUP BY loan_doc_id
),
collections_week AS (
SELECT
    lt.loan_doc_id,
    /* total collections during week */
    SUM(IF(lt.txn_type='payment', ifNull(lt.principal,0), 0)) AS collected_principal_week,
    SUM(IF(lt.txn_type IN ('payment'),ifNull(lt.fee,0),0)) AS collected_fee_week,
    /* same-day collections (CURRENT COLLECTION) */
    SUM(IF(toDate(lt.txn_date)=toDate(l.due_date),IF(lt.txn_type='payment', ifNull(lt.principal,0),0)  + IF(lt.txn_type IN ('payment'), ifNull(lt.fee,0),0), 0)) AS same_day_collection_week,
    /* grace collection (1 day late) */
    SUM(IF(toDate(lt.txn_date)=addDays(toDate(l.due_date),1),IF(lt.txn_type='payment', ifNull(lt.principal,0),0)+IF(lt.txn_type IN ('payment'), ifNull(lt.fee,0),0),0)) AS grace_collection_week,
    /* overdue collections (2+ days late) */
    SUM(IF(toDate(lt.txn_date)>addDays(toDate(l.due_date),1),IF(lt.txn_type='payment', ifNull(lt.principal,0),0),0)) AS overdue_collection_principal_week,
    SUM(IF(toDate(lt.txn_date)>addDays(toDate(l.due_date),1),IF(lt.txn_type IN ('payment'), ifNull(lt.fee,0),0),0)) AS overdue_collection_fee_week,
    /* prepayments */
    SUM(IF(toDate(lt.txn_date)<toDate(l.due_date),IF(lt.txn_type='payment', ifNull(lt.principal,0),0)+IF(lt.txn_type IN ('payment'), ifNull(lt.fee,0),0),0)) AS prepayment_collection_week
FROM flow_api.loan_txns lt

JOIN loan_principal l
ON lt.loan_doc_id=l.loan_doc_id

WHERE toDate(lt.txn_date) BETWEEN (SELECT start_date FROM params) AND (SELECT end_date FROM params)
  AND lt.realization_date <= (SELECT closure_date FROM closure)
  AND lt.country_code = (SELECT country_code FROM params)
GROUP BY lt.loan_doc_id
),
loan_state AS (
    SELECT
        l.*,
        p.last_payment_date,
        coalesce(p.principal_paid, 0) AS principal_paid,
        coalesce(p.fee_paid, 0) AS fee_paid,
        (l.loan_principal - coalesce(p.principal_paid, 0)) AS principal_os,
        (l.flow_fee - coalesce(p.fee_with_fee_waiver, 0)) AS fee_os,
        (l.loan_principal - coalesce(p.principal_paid, 0) + l.flow_fee - coalesce(p.fee_with_fee_waiver, 0)) AS outstanding,
        IF((l.loan_principal - coalesce(p.principal_paid, 0)) > 0, greatest(dateDiff('day', toDate(l.due_date), (SELECT end_date FROM params)), 0),0) AS dpd
    FROM loan_principal l
    LEFT JOIN loan_payments p ON l.loan_doc_id = p.loan_doc_id
),
tm_mapping AS (
    SELECT
        s.*,
        rm.full_name AS rm_name_orig,
        tm.id AS tm_id_orig,
        coalesce(tm.id, s.rm_id) AS tm_group_id,
        ifNull(tm.full_name, rm.full_name) AS tm_name
    FROM loan_state s
    LEFT JOIN flow_api.persons rm ON rm.id = s.rm_id
    LEFT JOIN flow_api.persons tm ON tm.id = rm.report_to
),
new_customers AS (
    SELECT
        ifNull(tm.full_name, p.full_name) AS tm_name,
        COUNT(DISTINCT l.cust_id) AS new_customer_count
    FROM flow_api.loans l
    JOIN flow_api.borrowers b ON l.cust_id = b.cust_id
    JOIN flow_api.persons p ON l.flow_rel_mgr_id = p.id
    LEFT JOIN flow_api.persons tm ON tm.id = p.report_to
    WHERE toDate(b.reg_date) BETWEEN (SELECT start_date FROM params) AND (SELECT end_date FROM params)
      AND l.country_code = (SELECT country_code FROM params)
      AND l.loan_purpose IN ('float_advance','adj_float_advance')
      AND l.status NOT IN ('voided','hold','pending_disbursal','pending_mnl_dsbrsl')
      AND l.product_id NOT IN (SELECT id FROM flow_api.loan_products WHERE product_type = 'float_vending')
    GROUP BY tm_name
)


SELECT
    t.tm_name AS `TM Name`,

    /* ---------------- PORTFOLIO SNAPSHOT ---------------- */
    SUM(IF(t.outstanding > 0, 1, 0)) AS `Total Outstanding Loans`,
    SUM(t.outstanding) AS `Total Portfolio Outstanding`,
    SUM(t.principal_os) AS `Principal Outstanding`,
    SUM(t.fee_os) AS `Fee Outstanding`,
    max(ifNull(nc.new_customer_count, 0)) AS `New Customers`,

  /* ---------------- DISBURSALS ---------------- */
    SUM(IF(toDate(t.disbursal_date) BETWEEN (SELECT start_date FROM params) AND (SELECT end_date FROM params), 1, 0)) AS `Loans Disbursed`,
    /* ---------------- WEEKLY DUE COHORT ---------------- */

  SUM(IF(toDate(t.due_date) BETWEEN (SELECT start_date FROM params) AND (SELECT end_date FROM params), 1, 0)) AS `Loans Due This Week Count`,
  SUM(IF(toDate(t.due_date) BETWEEN (SELECT start_date FROM params) AND (SELECT end_date FROM params), (t.loan_principal + t.flow_fee), 0)) AS `Amount Due This Week`,

    /* ---------------- TOTAL COLLECTIONS DURING WEEK ---------------- */
    SUM(ifNull(w.collected_principal_week,0) + ifNull(w.collected_fee_week,0)) AS `Total Collections Week`,

    /* ---------------- COLLECTIONS FOR WEEKLY DUE LOANS ---------------- */
    SUM(IF(toDate(t.due_date) BETWEEN (SELECT start_date FROM params) AND (SELECT end_date FROM params), 
    ifNull(w.collected_principal_week,0) + ifNull(w.collected_fee_week,0), 0)) AS `Total Amount Collected For Weeks Due`,

    /* ---------------- CURRENT COLLECTION (SAME-DAY ONLY) ---------------- */
    SUM(ifNull(w.same_day_collection_week,0)) AS `Current Collection Week`,
    SUM(IF(ifNull(w.same_day_collection_week,0) > 0, 1, 0)) AS `Current Collection Week Count`,

    /* ---------------- GRACE COLLECTION (1 DAY LATE) ---------------- */
    SUM(ifNull(w.grace_collection_week,0)) AS `Grace Collection Week`,
    SUM(IF(ifNull(w.grace_collection_week,0) > 0, 1, 0)) AS `Grace Collection Week Count`,

    /* ---------------- PREPAYMENT ---------------- */
    SUM(ifNull(w.prepayment_collection_week,0)) AS `Prepayment Week`,
    SUM(IF(ifNull(w.prepayment_collection_week,0) > 0, 1, 0)) AS `Prepayment Week Count`,

    /* ---------------- PREPAID BEFORE WEEK ---------------- */
    SUM(IF(toDate(t.due_date) BETWEEN (SELECT start_date FROM params) AND (SELECT end_date FROM params),
           (t.principal_paid + t.fee_paid) - (ifNull(w.collected_principal_week, 0) + ifNull(w.collected_fee_week, 0)),
           0)) AS `Prepaid Before Week Collection`,

    SUM(IF(toDate(t.due_date) BETWEEN (SELECT start_date FROM params) AND (SELECT end_date FROM params)
           AND ((t.principal_paid + t.fee_paid) - (ifNull(w.collected_principal_week, 0) + ifNull(w.collected_fee_week, 0))) > 0,
           1, 0)) AS `Prepaid Before Week Collection Count`,

    /* ---------------- FULLY CLOSED THIS WEEK ---------------- */
    SUM(IF(toDate(t.due_date) BETWEEN (SELECT start_date FROM params) AND (SELECT end_date FROM params)
           AND toDate(t.last_payment_date) BETWEEN (SELECT start_date FROM params) AND (SELECT end_date FROM params)
           AND t.outstanding = 0, (t.loan_principal + t.flow_fee), 0)) AS `Fully Closed This Week Amount`,

    SUM(IF(toDate(t.due_date) BETWEEN (SELECT start_date FROM params) AND (SELECT end_date FROM params)
           AND toDate(t.last_payment_date) BETWEEN (SELECT start_date FROM params) AND (SELECT end_date FROM params)
           AND t.outstanding = 0, 1, 0)) AS `Fully Closed This Week Count`,

    /* ---------------- PARTIAL PAYMENTS ---------------- */
    SUM(IF(toDate(t.due_date) BETWEEN (SELECT start_date FROM params) AND (SELECT end_date FROM params)
           AND toDate(t.last_payment_date) BETWEEN (SELECT start_date FROM params) AND (SELECT end_date FROM params)
           AND t.outstanding > 0, 1, 0)) AS `Partial Paid Loans`,

    SUM(IF(toDate(t.due_date) BETWEEN (SELECT start_date FROM params) AND (SELECT end_date FROM params)
           AND toDate(t.last_payment_date) BETWEEN (SELECT start_date FROM params) AND (SELECT end_date FROM params)
           AND t.outstanding > 0, ifNull(w.same_day_collection_week,0), 0)) AS `Partial Paid Amount`,

    /* ---------------- STILL DUE AT WEEK END ---------------- */
    SUM(IF(toDate(t.due_date) = (SELECT end_date FROM params) AND t.outstanding > 0, 1, 0)) AS `Still Due End Of Week Count`,
    SUM(IF(toDate(t.due_date) = (SELECT end_date FROM params) AND t.outstanding > 0, t.outstanding, 0)) AS `Still Due End Of Week Amount`,

    /* ---------------- NEW PAR GENERATED ---------------- */
    SUM(IF(toDate(t.due_date) BETWEEN (SELECT start_date FROM params) AND subtractDays((SELECT end_date FROM params),1)
           AND t.principal_os > 0 AND t.dpd BETWEEN 2 AND 7, 1, 0)) AS `New Par Generated Count`,

    SUM(IF(toDate(t.due_date) BETWEEN (SELECT start_date FROM params) AND subtractDays((SELECT end_date FROM params),1)
           AND t.principal_os > 0 AND t.dpd BETWEEN 2 AND 7, t.principal_os, 0)) AS `New Par Generated Amount`,

    /* ---------------- OVERDUE COLLECTION (PORTFOLIO LEVEL) ---------------- */
    SUM(ifNull(w.overdue_collection_principal_week,0)) AS `Overdue Collection Principal Week`,
    SUM(ifNull(w.overdue_collection_fee_week,0)) AS `Overdue Collection Fee Week`,
    SUM(IF(ifNull(w.overdue_collection_principal_week, 0) + ifNull(w.overdue_collection_fee_week, 0) > 0, 1, 0)) AS `Overdue Collection Week Count`,

    /* ---------------- PAR BUCKETS ---------------- */
    SUM(IF(t.dpd BETWEEN 2 AND 5, t.principal_os, 0)) AS `Par 2 5 Amount`,
    SUM(IF(t.dpd BETWEEN 2 AND 5 AND t.principal_os > 0, 1, 0)) AS `Par 2 5 Count`,

    SUM(IF(t.dpd BETWEEN 6 AND 15, t.principal_os, 0)) AS `Par 6 15 Amount`,
    SUM(IF(t.dpd BETWEEN 6 AND 15 AND t.principal_os > 0, 1, 0)) AS `Par 6 15 Count`,

    SUM(IF(t.dpd BETWEEN 16 AND 30, t.principal_os, 0)) AS `Par 16 30 Amount`,
    SUM(IF(t.dpd BETWEEN 16 AND 30 AND t.principal_os > 0, 1, 0)) AS `Par 16 30 Count`,

    SUM(IF(t.dpd > 30, t.principal_os, 0)) AS `Par 30 Plus Amount`,
    SUM(IF(t.dpd > 30 AND t.principal_os > 0, 1, 0)) AS `Par 30 Plus Count`,

    /* ---------------- ACTIVE RM COUNT ---------------- */
    COUNT(DISTINCT IF(t.outstanding > 0, t.rm_id, NULL)) AS `RM Count`


FROM tm_mapping t
LEFT JOIN collections_week w
    ON t.loan_doc_id = w.loan_doc_id
LEFT JOIN new_customers nc
    ON t.tm_name = nc.tm_name

GROUP BY
    t.tm_name
HAVING `Total Portfolio Outstanding` > 0
ORDER BY `Total Portfolio Outstanding` DESC;    