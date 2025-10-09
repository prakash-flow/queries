SET @cur_date = '2025-10-07 23:59:59';
SET @last_day = '2025-10-07';

WITH last_loan AS (
    SELECT 
        l.cust_id, 
        l.loan_principal, 
        l.status,
        l.disbursal_date,
        l.due_date,
        l.paid_date,
        CASE
            WHEN l.paid_date IS NOT NULL AND DATE(l.paid_date) <= @last_day THEN 'settled'
            WHEN @last_day < DATE(l.due_date) THEN 'ongoing'
            WHEN @last_day > DATE(l.due_date) THEN 'overdue'
            WHEN @last_day = DATE(l.due_date) THEN 'due'
        END AS last_loan_status
    FROM loans l
    JOIN (
        SELECT cust_id, MAX(disbursal_date) AS last_loan_date
        FROM loans
        WHERE disbursal_date <= @cur_date
          AND product_id NOT IN (43, 75, 300)
          AND status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
          AND country_code = 'UGA'
          AND YEAR(disbursal_date) = 2025 AND disbursal_date <= @cur_date
        GROUP BY cust_id
    ) AS sub ON l.cust_id = sub.cust_id 
             AND l.disbursal_date = sub.last_loan_date
    WHERE l.country_code = 'UGA'
)

SELECT 
    ll.cust_id `Customer ID`,
    CONCAT_WS(' ', p.first_name, p.middle_name, p.last_name) `Customer Name`,
    b.reg_date `Registration Date`,
    b.status `Customer Status`,
    DATE(b.last_visit_date) `Last Visit Date`,
    CONCAT_WS(' ', rm.first_name, rm.middle_name, rm.last_name) `RM Name`,
    ll.loan_principal `Last Loan Amount`,  
    ll.last_loan_status `Last Loan Status`,  
    DATE(disbursal_date) `Last Loan Disbursal Date`,
    DATE(due_date) `Last Loan Due Date`
FROM last_loan ll
JOIN borrowers b ON ll.cust_id = b.cust_id
LEFT JOIN persons p ON p.id = b.owner_person_id
LEFT JOIN persons rm ON rm.id = b.flow_rel_mgr_id
WHERE DATEDIFF(@cur_date, b.last_visit_date) > 90;