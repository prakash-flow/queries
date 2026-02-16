WITH ontime_customers AS (
    SELECT
        l.cust_id,
        ROUND(
            100 * SUM(
                CASE
                    WHEN t.max_txn_date <= DATE_ADD(l.due_date, INTERVAL 1 DAY)
                    THEN 1 ELSE 0
                END
            ) / COUNT(l.loan_doc_id),
            2
        ) AS ontime_repayment_rate
    FROM loans l
    JOIN (
        SELECT
            loan_doc_id,
            MAX(txn_date) AS max_txn_date
        FROM loan_txns
        WHERE txn_type = 'payment'
        GROUP BY loan_doc_id
    ) t ON l.loan_doc_id = t.loan_doc_id
    WHERE
        l.status = 'settled'
        AND l.paid_date <= '2026-02-08 23:59:59'
        AND l.product_id NOT IN (43, 75, 300)
        AND l.status NOT IN (
            'voided',
            'hold',
            'pending_disbursal',
            'pending_mnl_dsbrsl'
        )
        AND l.country_code = 'UGA'
    GROUP BY l.cust_id
    HAVING ontime_repayment_rate > 90
)

SELECT
    oc.cust_id `Customer ID`,
    b.reg_date `Registration Date`,
    UPPER(b.biz_name) `Business Name`,
    p.full_name `Customer Name`,
    UPPER(p.gender) `Gender`,
    TIMESTAMPDIFF(YEAR, p.dob, curdate()) `Age`,
    p.national_id `NIN`,
    p.mobile_num `Customer Mobile Number`,
    p.email_id `Customer Email ID`,
    p.alt_biz_mobile_num_1 `Alternate Number 1`,
    p.alt_biz_mobile_num_2 `Alternate Number 2`,
    p.whatsapp `Whatsapp Number`,
    b.district `District`,
    b.territory `Territory`,
    a.field_1 `Region`,
    b.impairment_type `Impairment Type`,
    b.person_w_disability `PWD`,
    ontime_repayment_rate `Ontime Repayment Rate`,
    rm.full_name `RM Name`,
    rm.mobile_num `RM Number`
FROM ontime_customers oc
JOIN borrowers b
    ON b.cust_id = oc.cust_id
JOIN persons p
    ON p.id = b.owner_person_id
JOIN persons rm 
    ON rm.id = b.flow_rel_mgr_id
JOIN address_info a
    ON a.id = b.owner_address_id
WHERE 
  p.gender IN ('male', 'female');


-- https://docs.google.com/spreadsheets/d/1I67ML_DX8KRev9QMRk8npzZB8euh8d7WFDss9u5LHAc/edit?usp=sharing