WITH ranked_loans AS (
    SELECT
        l.cust_id,
        CASE
            WHEN DATEDIFF(l.paid_date, l.due_date) <= 1 THEN 1
            ELSE 0
        END AS ontime,
        ROW_NUMBER() OVER (
            PARTITION BY l.cust_id
            ORDER BY l.disbursal_date DESC
        ) AS rn
    FROM loans l
    INNER JOIN customer_repayment_limits c
        ON c.cust_id = l.cust_id
       AND c.status = 'enabled'
    WHERE l.status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
      AND l.paid_date IS NOT NULL
      AND l.loan_purpose = 'float_advance'
      AND l.disbursal_date > c.loan_repaid_date
      AND l.cust_id IN (
      )
)

SELECT
    b.cust_id,
    b.last_upgraded_amount,
    b.crnt_fa_limit,
    p.first_name,
    p.mobile_num,
    COUNT(rl.cust_id) AS last_5_loans,

    CASE
        WHEN MIN(CASE WHEN rl.ontime = 0 THEN rl.rn END) IS NULL
            THEN COUNT(rl.cust_id)
        ELSE MIN(CASE WHEN rl.ontime = 0 THEN rl.rn END) - 1
    END AS consecutive_ontime,

    GREATEST(
        5 - (
            CASE
                WHEN MIN(CASE WHEN rl.ontime = 0 THEN rl.rn END) IS NULL
                    THEN COUNT(rl.cust_id)
                ELSE MIN(CASE WHEN rl.ontime = 0 THEN rl.rn END) - 1
            END
        ),
        0
    ) AS loans_needed_for_upgrade

FROM borrowers b
LEFT JOIN persons p on p.id = b.owner_person_id
LEFT JOIN ranked_loans rl
    ON rl.cust_id = b.cust_id
   AND rl.rn <= 5
WHERE b.cust_id IN (
)
GROUP BY
    b.cust_id,
    b.last_upgraded_amount,
    b.crnt_fa_limit,
    p.first_name,
    p.mobile_num;