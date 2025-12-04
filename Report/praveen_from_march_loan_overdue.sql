SET @country_code = 'UGA';

SET @month = '202512';
SET @curdate = '2025-12-02 23:59:59';

SET @realization_date = (
    IFNULL(
        (SELECT closure_date
         FROM closure_date_records
         WHERE month = @month
           AND status = 'enabled'
           AND country_code = @country_code),
        @curdate
    )
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
            ) AS rn
        FROM rm_cust_assignments rm_cust
        WHERE rm_cust.country_code = @country_code
          AND rm_cust.reason_for_reassign NOT IN ('initial_assignment')
          AND DATE(rm_cust.from_date) > '2025-11-07'
    ) x
    WHERE rn = 1
),

loanPayments AS (
    SELECT
        loan_doc_id,
        SUM(CASE WHEN txn_type = 'payment'
                 THEN principal ELSE 0 END) AS total_amount
    FROM loan_txns
    WHERE txn_date <= @curdate
      AND realization_date <= @realization_date
    GROUP BY loan_doc_id
),

/* Borrower details */
borrowerDetails AS (
    SELECT
        cust_id,
        reg_date,
        owner_person_id,
        crnt_fa_limit,
        reg_flow_rel_mgr_id,
        status,
        addl_mob_num
    FROM borrowers
),

/* Loan counts */
loanCounts AS (
    SELECT
        cust_id,
        COUNT(*) AS total_loans_taken
    FROM loans
    WHERE status NOT IN ('voided','hold','pending_disbursal','pending_mnl_dsbrsl')
    AND disbursal_date <= @curdate
    AND product_id NOT IN ('43','75','300')
    AND country_code = @country_code
    GROUP BY cust_id
)

/* FINAL QUERY */
SELECT
    COALESCE(r.from_rm_id, l.flow_rel_mgr_id) AS `RM ID`,
    UPPER(rm.full_name) AS `RM Name`,      

    l.loan_doc_id `Loan ID`,
    l.cust_id `Customer ID`,
    b.reg_date `Registration Date`,
    b.status `Customer Status`,
    UPPER(owner.full_name) AS `Customer Name`,
    b.crnt_fa_limit `Eligibility Amount`,

    DATE(l.disbursal_date) `Disbursal Date`,
    DATE(l.due_date) `Due Date`,
    
    l.acc_number `Loan Disbursed Account`,
    l.loan_principal `Loan Principal`,
    lp.total_amount AS `Principal Paid`,
    (l.loan_principal - IFNULL(lp.total_amount, 0)) AS `OS Amount`,
    l.status AS `Loan Status`,
    DATEDIFF(@curdate, l.due_date) AS `Par Days`,

    lc.total_loans_taken `Total Loans`,

    UPPER(reg.full_name) AS `Registered RM`,
    owner.mobile_num `Mobile Number`,
    owner.alt_biz_mobile_num_1 `Alternate Mobile Number 1`,
    owner.alt_biz_mobile_num_2 `Alternate Mobile Number 2`,

    UPPER(CONCAT(
    JSON_UNQUOTE(JSON_EXTRACT(addl_mob_num, '$[0].name')),
    ' | ',
    JSON_UNQUOTE(JSON_EXTRACT(addl_mob_num, '$[0].relation')),
    ' | ',
    JSON_UNQUOTE(JSON_EXTRACT(addl_mob_num, '$[0].mobile_num'))
    )) AS `Addl Contact 1`,
    UPPER(CONCAT(
    JSON_UNQUOTE(JSON_EXTRACT(addl_mob_num, '$[1].name')),
    ' | ',
    JSON_UNQUOTE(JSON_EXTRACT(addl_mob_num, '$[1].relation')),
    ' | ',
    JSON_UNQUOTE(JSON_EXTRACT(addl_mob_num, '$[1].mobile_num'))
    )) AS `Addl Contact 2`,
    UPPER(CONCAT(
    JSON_UNQUOTE(JSON_EXTRACT(addl_mob_num, '$[2].name')),
    ' | ',
    JSON_UNQUOTE(JSON_EXTRACT(addl_mob_num, '$[2].relation')),
    ' | ',
    JSON_UNQUOTE(JSON_EXTRACT(addl_mob_num, '$[2].mobile_num'))
    )) AS `Addl Contact 3`,

    a.acc_prvdr_code `Account Provider`,
    UPPER(COALESCE(a.acc_ownership, "owned")) `Account Ownership`,
    UPPER(COALESCE(CASE WHEN (la.loan_applied_by IS NULL OR la.loan_applied_by IN (0)) AND la.channel = "sms" THEN la.cust_name ELSE lab.full_name END, 'system')) AS `Loan Applier Name`,
    UPPER(COALESCE(CASE WHEN (la.loan_applied_by IS NULL OR la.loan_applied_by IN (0)) AND la.channel = "sms" THEN "customer" ELSE au.role_codes END, "system")) AS `Loan Applier Role`,
    UPPER(l.loan_purpose) `Loan Purpose`

FROM loanPayments lp
JOIN loans l ON l.loan_doc_id = lp.loan_doc_id

LEFT JOIN recentReassignments r ON l.cust_id = r.cust_id
LEFT JOIN borrowerDetails b ON b.cust_id = l.cust_id
LEFT JOIN loanCounts lc ON lc.cust_id = l.cust_id

LEFT JOIN persons owner ON owner.id = b.owner_person_id 
LEFT JOIN persons reg ON reg.id = b.reg_flow_rel_mgr_id       
LEFT JOIN persons rm ON rm.id = COALESCE(r.from_rm_id, l.flow_rel_mgr_id) 
LEFT JOIN accounts a ON a.id = l.cust_acc_id
LEFT JOIN loan_applications la ON la.id = l.loan_appl_id
LEFT JOIN app_users au ON au.id = la.loan_applied_by
LEFT JOIN persons lab ON lab.id = au.person_id

WHERE l.status NOT IN ('voided','hold','pending_disbursal','pending_mnl_dsbrsl')
  AND l.disbursal_date >= '2025-03-01 00:00:00'
  AND l.disbursal_date <= @curdate
  AND l.product_id NOT IN ('43','75','300')
  AND l.country_code = @country_code
  AND DATEDIFF(@curdate, l.due_date) > 1
  AND (l.loan_principal - IFNULL(lp.total_amount, 0)) > 0

HAVING `RM ID` IN (8282,8286,8287,22864,3462,11369,23932,29998,2440,16393,2509,4926)

ORDER BY `RM ID`, l.loan_doc_id;