-- Per-customer on-time repayment metrics.
-- Same logic as BorrowerService::get_cust_ontime_metrics(), but for every
-- customer at once instead of filtering to a single cust_id.

SET @end_date     = '2026-09-15';
SET @country_code = 'UGA';

WITH base_query AS (
    SELECT
        l.cust_id,
        l.loan_doc_id,
        l.due_date,
        (IFNULL(l.loan_principal, 0) + IFNULL(l.flow_fee, 0) + IFNULL(l.charges, 0)) AS expected_amount,
        SUM(IFNULL(lt.principal, 0) + IFNULL(lt.fee, 0) + IFNULL(lt.charges, 0)) AS paid_amount,
        SUM(
            IF(
                DATE(lt.txn_date) <= DATE_ADD(DATE(l.due_date), INTERVAL 1 DAY),
                IFNULL(lt.principal, 0) + IFNULL(lt.fee, 0) + IFNULL(lt.charges, 0),
                0
            )
        ) AS ontime_paid_amount,
        SUM(
            IF(
                DATE(lt.txn_date) <= DATE_ADD(DATE(l.due_date), INTERVAL 5 DAY),
                IFNULL(lt.principal, 0) + IFNULL(lt.fee, 0) + IFNULL(lt.charges, 0),
                0
            )
        ) AS paid_within_5_days_amount,
        IF(
            SUM(IFNULL(lt.principal, 0) + IFNULL(lt.fee, 0) + IFNULL(lt.charges, 0)) > 0,
            MAX(DATE(lt.txn_date)),
            NULL
        ) AS paid_date
    FROM loans l
    LEFT JOIN loan_txns lt
        ON l.loan_doc_id = lt.loan_doc_id
       AND lt.txn_type = 'payment'
    WHERE l.due_date <= CONCAT(@end_date, ' 23:59:59')
      AND l.country_code = @country_code
      AND l.product_id NOT IN (
            SELECT id FROM loan_products
            WHERE product_type = 'float_vending' OR repayment_type = 'installment'
          )
      AND l.status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
      AND l.loan_purpose IN ('float_advance')
    GROUP BY l.cust_id, l.loan_doc_id, l.due_date, expected_amount
),
raw AS (
    SELECT
        cust_id,
        loan_doc_id,
        MAX(due_date) AS due_date,
        COUNT(loan_doc_id) AS loan_count,
        SUM(ontime_paid_amount) AS ontime_repaid_amount,
        SUM(expected_amount) AS total_due_amount,
        SUM(paid_within_5_days_amount) AS paid_within_5_days_amount,
        (SUM(ontime_paid_amount) / NULLIF(SUM(expected_amount), 0)) * 100 AS loan_wise_ontime_repayment,
        SUM(IF(ontime_paid_amount >= expected_amount, 1, 0)) AS ontime_settle_count,
        MAX(paid_date) AS paid_date
    FROM base_query
    GROUP BY cust_id, loan_doc_id
)

-- === Per-customer breakdown ===
SELECT
    b.cust_id,
    b.reg_date,
    b.acc_purpose,
    cp.full_name AS customer_name,
    rm.full_name AS rm_name,

    COUNT(raw.loan_doc_id) AS total_loans,

    SUM(
        CASE WHEN raw.due_date >= DATE_SUB(@end_date, INTERVAL 3 MONTH) THEN 1 ELSE 0 END
    ) AS total_loans_3_months,

    IFNULL(
        ROUND(
            SUM(
                CASE WHEN raw.due_date >= DATE_SUB(@end_date, INTERVAL 3 MONTH) THEN raw.ontime_repaid_amount ELSE 0 END
            ) /
            NULLIF(
                SUM(
                    CASE WHEN raw.due_date >= DATE_SUB(@end_date, INTERVAL 3 MONTH) THEN raw.total_due_amount ELSE 0 END
                ),
                0
            ) * 100,
            2
        ),
        0
    ) AS ontime_rate_3_months,

    IFNULL(
        SUM(
            CASE WHEN raw.due_date >= DATE_SUB(@end_date, INTERVAL 3 MONTH) THEN raw.ontime_settle_count ELSE 0 END
        ),
        0
    ) AS ontime_loans_3_months,

    IFNULL(
        ROUND(
            SUM(raw.ontime_repaid_amount) / NULLIF(SUM(raw.total_due_amount), 0) * 100,
            2
        ),
        0
    ) AS ontime_rate_overall,

    IFNULL(SUM(raw.ontime_settle_count), 0) AS ontime_loans_overall

FROM borrowers b
LEFT JOIN raw ON raw.cust_id = b.cust_id
LEFT JOIN persons cp ON cp.id = b.owner_person_id
LEFT JOIN persons rm ON rm.id = b.flow_rel_mgr_id
WHERE b.country_code = @country_code
  AND b.acc_purpose IS NOT NULL
  AND b.acc_purpose NOT IN ('asset')
GROUP BY b.cust_id, b.reg_date, b.acc_purpose, cp.full_name, rm.full_name;
