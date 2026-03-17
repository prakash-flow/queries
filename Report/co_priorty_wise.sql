WITH
toDateTime(@from_date) AS from_date,
toDateTime(@to_date) AS to_date,
@country_code AS v_country_code,

loan_base AS (
    SELECT
        l.cust_id,
        l.loan_doc_id as loan_doc_id,
        toDate(l.disbursal_date) as disbursal_date,
        l.loan_principal,
        l.flow_rel_mgr_id,
        CASE 
            WHEN l.loan_purpose = 'adj_float_advance' THEN 'Kula'
            WHEN l.loan_purpose = 'float_advance' THEN 'Float Advance'
            ELSE l.loan_purpose 
        END loan_purpose,
        l.due_date,
        dateDiff('day', l.due_date, to_date) as overdue_days
        ,
        l.flow_fee
    FROM loans l
    INNER JOIN loan_txns lt ON lt.loan_doc_id = l.loan_doc_id
    WHERE lt.txn_type = 'disbursal'
        AND lt.realization_date <= to_date
        AND l.country_code = v_country_code
        AND l.disbursal_date <= to_date
        AND l.product_id NOT IN (43, 75, 300)
        AND l.status NOT IN ('voided','hold','pending_disbursal','pending_mnl_dsbrsl')
),

payments AS (
    SELECT
        loan_doc_id,
        sumIf(ifNull(principal, 0), txn_type = 'payment') AS total_paid_principal,
        sumIf(ifNull(fee, 0), txn_type IN ('payment','fee_waiver')) AS total_paid_fee,
        ifNull(sumIf(ifNull(fee, 0) + ifNull(principal, 0), txn_type IN ('payment')), 0) AS total_paid_now,
        max(txn_date) as last_payment_date,
        ifNull(argMax(principal + fee, txn_date), 0) AS last_payment_amount
    FROM loan_txns
    WHERE realization_date <= to_date
        AND txn_date <= to_date
        AND txn_type IN ('payment','fee_waiver')
        AND country_code = v_country_code
    GROUP BY loan_doc_id
),

customer_info AS (
    SELECT  
        b.cust_id,
        UPPER(a_info.field_1) AS region,
        UPPER(a_info.field_2) AS district,
        UPPER(a_info.field_3) AS county,
        UPPER(COALESCE(b.location, a_info.field_8)) AS location,
        p.mobile_num AS cust_mobile_num,
        p.full_name AS cust_name,
        b.owner_person_id
    FROM borrowers b
    LEFT JOIN address_info a_info ON b.owner_address_id = a_info.id 
    LEFT JOIN persons p ON p.id = b.owner_person_id
    WHERE b.country_code = v_country_code 
),

latest_visits AS (
    SELECT loan_doc_id, visitor_name, visit_end_time, 
            dateDiff('day', visit_end_time, to_date) since_last_visit, remarks
    FROM (
        SELECT loan_doc_id, visitor_name, visit_end_time, remarks,
                row_number() OVER (PARTITION BY loan_doc_id ORDER BY visit_end_time DESC) as rn
        FROM field_visits 
        WHERE visitor_id IN (SELECT person_id FROM app_users WHERE country_code = v_country_code and role_codes = 'recovery_specialist')
            AND loan_doc_id IS NOT NULL 
            AND country_code = v_country_code
            AND sch_status = 'checked_out'
            AND toDate(visit_end_time) <= to_date
    ) WHERE rn = 1
),

collections_after_visit AS (
    SELECT
        v.loan_doc_id,
        sum(lt.principal + lt.fee) AS amount_collected_after_visit
    FROM latest_visits v
    INNER JOIN loan_txns lt ON v.loan_doc_id = lt.loan_doc_id
    WHERE lt.txn_type = 'payment'
        AND lt.realization_date > v.visit_end_time 
        AND lt.realization_date <= to_date
        AND lt.txn_date <= to_date
    GROUP BY v.loan_doc_id
)

SELECT
ci.region as `Region`,
ci.district as `District`,
ci.county as `County`,
ci.location as `Location`,
rm.full_name AS `RM Name`, 
lb.flow_rel_mgr_id as `RM ID`,
ci.cust_name as `Customer Name`,
lb.cust_id as `Customer ID`,
lb.loan_doc_id as `Loan ID`,
lb.loan_purpose as `Loan Purpose`,
ci.cust_mobile_num as `Client Primary Mobile No`,
lb.disbursal_date as `Disbursal Date`,
lb.loan_principal as `Disbursal Amount`,
p.total_paid_now as `Total Paid Till`,
toDate(p.last_payment_date) as `Last Paid Date`,
p.last_payment_amount as `Last Paid Amount`,
greatest(lb.loan_principal - coalesce(p.total_paid_principal, 0), 0) AS `Principal OS`,
greatest(lb.flow_fee - coalesce(p.total_paid_fee, 0), 0) AS `Fee OS`,
(`Principal OS` + `Fee OS`) as `Overdue Amount`,
lb.overdue_days as `Overdue Days`,
CASE WHEN tm.id in (2707, 1742, 3461, 2709, 5456, 2562, 12537, 11365, 3150) THEN tm.full_name END as `TM Name`,
since_last_visit as `Days since last visited by CO`,
ifNull(cav.amount_collected_after_visit, 0) as `Amount Collected by CO till date`,
toDate(lv.visit_end_time) as `Last CO Visit Date`,
lv.visitor_name as `CO Name`,
lv.remarks as `Visit Comments`,
lv.remarks as `Visit Comments`
FROM loan_base lb
LEFT JOIN payments p ON lb.loan_doc_id = p.loan_doc_id
LEFT JOIN customer_info ci ON lb.cust_id = ci.cust_id
LEFT JOIN persons rm ON rm.id = lb.flow_rel_mgr_id 
LEFT JOIN persons tm on tm.id = rm.report_to
LEFT JOIN latest_visits lv ON lb.loan_doc_id = lv.loan_doc_id
LEFT JOIN collections_after_visit cav ON lb.loan_doc_id = cav.loan_doc_id
WHERE (`Principal OS` > 0 or `Fee OS` > 0) AND lb.overdue_days BETWEEN 6 AND (30 + dateDiff('day', toDate(from_date), toDate(to_date)))
ORDER BY lb.overdue_days DESC