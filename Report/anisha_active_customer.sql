SET @as_of_date = '2026-02-10';
SET @country_code = 'UGA';

WITH active_cust AS (
    SELECT DISTINCT l.cust_id
    FROM loans l
    JOIN loan_txns t 
        ON l.loan_doc_id = t.loan_doc_id
    WHERE
        DATEDIFF(@as_of_date, t.txn_date) <= 30
        AND DATE(t.txn_date) <= @as_of_date
        AND l.country_code = @country_code
        AND t.txn_type = 'disbursal'
        AND l.product_id NOT IN (43, 75, 300)
        AND l.status NOT IN (
            'voided',
            'hold',
            'pending_disbursal',
            'pending_mnl_dsbrsl'
        )
),

ontime AS (
    SELECT
        l.cust_id,
        COUNT(DISTINCT l.loan_doc_id) AS total_loans,
        SUM(
            CASE
                WHEN t.max_txn_date <= DATE_ADD(l.due_date, INTERVAL 1 DAY)
                THEN 1 ELSE 0
            END
        ) AS ontime_settle_count,
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
    JOIN active_cust ac 
        ON l.cust_id = ac.cust_id
    JOIN (
        SELECT
            loan_doc_id,
            MAX(txn_date) AS max_txn_date
        FROM loan_txns
        WHERE txn_type = 'payment'
        GROUP BY loan_doc_id
    ) t 
        ON l.loan_doc_id = t.loan_doc_id
    WHERE
        l.status = 'settled'
        AND l.paid_date <= @as_of_date
        AND l.product_id NOT IN (43, 75, 300)
        AND l.country_code = @country_code
    GROUP BY l.cust_id
),

last_loan AS (
    SELECT *
    FROM (
        SELECT
            l.cust_id,
            l.loan_principal,
            l.disbursal_date,
            l.status,
            ROW_NUMBER() OVER (
                PARTITION BY l.cust_id
                ORDER BY l.disbursal_date DESC
            ) AS rn
        FROM loans l
        WHERE
            l.country_code = @country_code
            AND l.product_id NOT IN (43, 75, 300)
            AND l.status NOT IN (
                'voided',
                'hold',
                'pending_disbursal',
                'pending_mnl_dsbrsl'
            )
            AND l.disbursal_date <= @as_of_date
    ) x
    WHERE rn = 1
)

SELECT
    b.cust_id,
    b.reg_date AS `Registration Date`,
    p.full_name AS `Customer Name`,
    p.mobile_num AS `Customer Mobile Num`,
    o.total_loans AS `Total Loans`,
    rm.full_name AS `RM Name`,
    o.ontime_repayment_rate AS `Ontime %`,

    ll.loan_principal AS `Last Loan Principal`,
    ll.disbursal_date AS `Last Disbursal Date`,
    ll.status AS `Last Loan Status`

FROM ontime o

JOIN borrowers b 
    ON b.cust_id = o.cust_id

LEFT JOIN persons p 
    ON p.id = b.owner_person_id

LEFT JOIN persons rm 
    ON rm.id = b.flow_rel_mgr_id

LEFT JOIN last_loan ll
    ON ll.cust_id = o.cust_id

ORDER BY o.ontime_repayment_rate DESC;


-- https://docs.google.com/spreadsheets/d/1n1HHt5azgv-Ro9QxKpyQ3X8UZe4T8g1XHel2w-koS44/edit?usp=sharing