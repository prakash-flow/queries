SET @country_code = 'UGA';
SET @last_day = '2025-09-14';

SELECT 
    ova.cust_id `Customer ID`,
    UPPER(CONCAT_WS(' ', p.first_name, p.middle_name, p.last_name)) `Customer Name`,
    b.reg_date,
    TIMESTAMPDIFF(YEAR, b.reg_date, @last_day) `Years@Flow`,
    UPPER(a.field_1) `Region`,
    UPPER(CONCAT_WS(' ', rm.first_name, rm.middle_name, rm.last_name)) `RM Name`,
    CASE WHEN s.cust_id IS NOT NULL THEN 1 ELSE 0 END AS `Is Active Switch User`,
    CASE WHEN acp.cust_id IS NOT NULL THEN 1 ELSE 0 END AS `Is Active FA User`,
    
    -- Overall On-time Repayment Rate
    ova.ontime_repayment_rate_overall `Overall Repayment Rate`,

    -- On-time Repayment Rate for Float Advance
    ova.ontime_repayment_rate_float_advance `Repayment Rate (Float Advance)`,

    -- On-time Repayment Rate for Adj Float Advance
    ova.ontime_repayment_rate_adj_float_advance `Repayment Rate (Adj Float Advance)`,

    -- Total Loan Counts
    total_loans_float_advance `Total Loans (Float Advance)`,
    total_loans_adj_float_advance `Total Loan (Adj Float Advance)`

FROM
(
    -- Base On-time Repayment + Loan Counts
    SELECT
        o.cust_id,
        o.ontime_repayment_rate_overall,
        o.ontime_repayment_rate_float_advance,
        o.ontime_repayment_rate_adj_float_advance,
        total_loans_float_advance,
        afa.total_loans_adj_float_advance
    FROM
    (
        -- On-time Repayment Calculation
        SELECT
          l.cust_id,

          -- Overall On-time Repayment Rate
          ROUND(
            100 * SUM(CASE 
                        WHEN t.max_txn_date <= DATE_ADD(l.due_date, INTERVAL 1 DAY) 
                        THEN 1 ELSE 0 
                      END) 
                / NULLIF(COUNT(l.loan_doc_id), 0), 
            2
          ) AS ontime_repayment_rate_overall,

          -- Float Advance On-time Repayment Rate
          ROUND(
            100 * SUM(
              CASE
                WHEN l.loan_purpose = 'float_advance'
                     AND t.max_txn_date <= DATE_ADD(l.due_date, INTERVAL 1 DAY)
                THEN 1 ELSE 0 END
            ) / NULLIF(SUM(CASE WHEN l.loan_purpose = 'float_advance' THEN 1 ELSE 0 END), 0),
            2
          ) AS ontime_repayment_rate_float_advance,

          -- Adj Float Advance On-time Repayment Rate
          ROUND(
            100 * SUM(
              CASE
                WHEN l.loan_purpose = 'adj_float_advance'
                     AND t.max_txn_date <= DATE_ADD(l.due_date, INTERVAL 1 DAY)
                THEN 1 ELSE 0 END
            ) / NULLIF(SUM(CASE WHEN l.loan_purpose = 'adj_float_advance' THEN 1 ELSE 0 END), 0),
            2
          ) AS ontime_repayment_rate_adj_float_advance

        FROM
          loans l
          JOIN (
            SELECT
              loan_doc_id,
              MAX(txn_date) AS max_txn_date
            FROM
              loan_txns
            WHERE
              txn_type = 'payment'
            GROUP BY
              loan_doc_id
          ) t ON l.loan_doc_id = t.loan_doc_id
        WHERE
          l.status = 'settled'
          AND l.paid_date <= @last_day
          AND l.product_id NOT IN (43, 75, 300)
          AND l.status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
          AND l.country_code = @country_code
        GROUP BY l.cust_id
    ) AS o

    -- Total Loans for Float Advance
    INNER JOIN (
        SELECT
            l.cust_id,
            COUNT(DISTINCT l.loan_doc_id) AS total_loans_float_advance
        FROM
            loans l
        JOIN
            loan_txns t ON l.loan_doc_id = t.loan_doc_id
        LEFT JOIN (
            SELECT DISTINCT
                r1.record_code
            FROM
                record_audits r1
            JOIN (
                SELECT
                    record_code,
                    MAX(id) AS id
                FROM
                    record_audits
                WHERE
                    DATE(created_at) <= @last_day
                GROUP BY
                    record_code
            ) r2 ON r1.id = r2.id
            WHERE
                JSON_EXTRACT(r1.data_after, '$.status') = 'disabled'
        ) disabled_cust ON l.cust_id = disabled_cust.record_code
        WHERE
            DATEDIFF(@last_day, t.txn_date) <= 30
            AND DATE(t.txn_date) <= @last_day
            AND l.country_code = @country_code
            AND l.loan_purpose = 'float_advance'
            AND t.txn_type = 'disbursal'
            AND l.product_id NOT IN (43, 75, 300)
            AND l.status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
            AND disabled_cust.record_code IS NULL
        GROUP BY l.cust_id
    ) AS fa ON o.cust_id = fa.cust_id

    -- Total Loans for Adj Float Advance
    INNER JOIN (
        SELECT
            l.cust_id,
            COUNT(DISTINCT l.loan_doc_id) AS total_loans_adj_float_advance
        FROM
            loans l
        JOIN
            loan_txns t ON l.loan_doc_id = t.loan_doc_id
        LEFT JOIN (
            SELECT DISTINCT
                r1.record_code
            FROM
                record_audits r1
            JOIN (
                SELECT
                    record_code,
                    MAX(id) AS id
                FROM
                    record_audits
                WHERE
                    DATE(created_at) <= @last_day
                GROUP BY
                    record_code
            ) r2 ON r1.id = r2.id
            WHERE
                JSON_EXTRACT(r1.data_after, '$.status') = 'disabled'
        ) disabled_cust ON l.cust_id = disabled_cust.record_code
        WHERE
            DATEDIFF(@last_day, t.txn_date) <= 30
            AND DATE(t.txn_date) <= @last_day
            AND l.country_code = @country_code
            AND l.loan_purpose = 'adj_float_advance'
            AND t.txn_type = 'disbursal'
            AND l.product_id NOT IN (43, 75, 300)
            AND l.status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
            AND disabled_cust.record_code IS NULL
        GROUP BY l.cust_id
    ) AS afa ON o.cust_id = afa.cust_id
) AS ova
LEFT JOIN (
    SELECT DISTINCT cust_id
    FROM sales
    WHERE status = 'delivered'
      AND DATE(delivery_date) BETWEEN DATE_SUB(@last_day, INTERVAL 30 DAY) AND @last_day
) s ON ova.cust_id = s.cust_id
LEFT JOIN (
	SELECT DISTINCT cust_id
    FROM loans l
    WHERE l.product_id NOT IN (43, 75, 300)
            AND l.status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl') 
  		AND channel = 'cust_app'
      AND DATE(disbursal_date) BETWEEN DATE_SUB(@last_day, INTERVAL 30 DAY) AND @last_day
) acp on acp.cust_id = ova.cust_id
LEFT JOIN borrowers b ON b.cust_id = ova.cust_id
LEFT JOIN address_info a ON a.id = b.owner_address_id
LEFT JOIN persons p on p.id = b.owner_person_id
LEFT JOIN persons rm on rm.id = b.flow_rel_mgr_id
-- Final Filter (Optional)
HAVING 
     `Overall Repayment Rate` = 100
     AND `Region` IN ('eastern', 'central')
     AND `Is Active FA User` = 1
     AND `Is Active Switch User` = 1
     AND `Years@Flow` > 2;