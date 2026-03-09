WITH loan_payments AS (
    SELECT
        loan_doc_id,
        MAX(txn_date) AS max_txn_date
    FROM loan_txns
    WHERE txn_type = 'payment'
    GROUP BY loan_doc_id
)

SELECT
    l.cust_id,

    /* ---------------- CURRENT MONTH ---------------- */
    ROUND(
        100 * SUM(
            CASE
                WHEN l.paid_date >= DATE_FORMAT(CURDATE(), '%Y-%m-01')
                 AND t.max_txn_date <= DATE_ADD(l.due_date, INTERVAL 1 DAY)
                THEN 1 ELSE 0
            END
        ) /
        NULLIF(
            SUM(
                CASE
                    WHEN l.paid_date >= DATE_FORMAT(CURDATE(), '%Y-%m-01')
                    THEN 1 ELSE 0
                END
            ),
            0
        ),
        2
    ) AS ontime_rate_current_month,

    /* ---------------- LAST 1 MONTH ---------------- */
    ROUND(
        100 * SUM(
            CASE
                WHEN l.paid_date >= DATE_SUB(CURDATE(), INTERVAL 1 MONTH)
                 AND t.max_txn_date <= DATE_ADD(l.due_date, INTERVAL 1 DAY)
                THEN 1 ELSE 0
            END
        ) /
        NULLIF(
            SUM(
                CASE
                    WHEN l.paid_date >= DATE_SUB(CURDATE(), INTERVAL 1 MONTH)
                    THEN 1 ELSE 0
                END
            ),
            0
        ),
        2
    ) AS ontime_rate_last_1_month,

    /* ---------------- LAST 3 MONTHS ---------------- */
    ROUND(
        100 * SUM(
            CASE
                WHEN l.paid_date >= DATE_SUB(CURDATE(), INTERVAL 3 MONTH)
                 AND t.max_txn_date <= DATE_ADD(l.due_date, INTERVAL 1 DAY)
                THEN 1 ELSE 0
            END
        ) /
        NULLIF(
            SUM(
                CASE
                    WHEN l.paid_date >= DATE_SUB(CURDATE(), INTERVAL 3 MONTH)
                    THEN 1 ELSE 0
                END
            ),
            0
        ),
        2
    ) AS ontime_rate_last_3_months,

    /* ---------------- LAST 6 MONTHS ---------------- */
    ROUND(
        100 * SUM(
            CASE
                WHEN l.paid_date >= DATE_SUB(CURDATE(), INTERVAL 6 MONTH)
                 AND t.max_txn_date <= DATE_ADD(l.due_date, INTERVAL 1 DAY)
                THEN 1 ELSE 0
            END
        ) /
        NULLIF(
            SUM(
                CASE
                    WHEN l.paid_date >= DATE_SUB(CURDATE(), INTERVAL 6 MONTH)
                    THEN 1 ELSE 0
                END
            ),
            0
        ),
        2
    ) AS ontime_rate_last_6_months,

  /* ---------------- LAST 12 MONTHS ---------------- */
    ROUND(
        100 * SUM(
            CASE
                WHEN l.paid_date >= DATE_SUB(CURDATE(), INTERVAL 12 MONTH)
                 AND t.max_txn_date <= DATE_ADD(l.due_date, INTERVAL 1 DAY)
                THEN 1 ELSE 0
            END
        ) /
        NULLIF(
            SUM(
                CASE
                    WHEN l.paid_date >= DATE_SUB(CURDATE(), INTERVAL 12 MONTH)
                    THEN 1 ELSE 0
                END
            ),
            0
        ),
        2
    ) AS ontime_rate_last_12_months

FROM loans l
JOIN loan_payments t
    ON t.loan_doc_id = l.loan_doc_id

WHERE l.status = 'settled'
  AND l.product_id NOT IN (43, 75, 300)
  AND l.status NOT IN (
      'voided',
      'hold',
      'pending_disbursal',
      'pending_mnl_dsbrsl'
  )
  AND l.country_code = 'UGA'

GROUP BY l.cust_id
ORDER BY l.cust_id;