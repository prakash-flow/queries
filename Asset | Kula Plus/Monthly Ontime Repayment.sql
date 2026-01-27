SET @month = 202512;
SET @country_code = 'RWA';

SET @closure_date = (
    SELECT closure_date
    FROM flow_api.closure_date_records
    WHERE status = 'enabled'
      AND month = @month
      AND country_code = @country_code
);

WITH loan AS (
    SELECT
        l.loan_doc_id,
        l.loan_purpose
    FROM loans l
    JOIN loan_txns lt
        ON lt.loan_doc_id = l.loan_doc_id
    WHERE lt.txn_type IN ('af_disbursal')
      AND l.loan_purpose IN ('growth_financing', 'asset_financing')
      AND l.country_code = @country_code
      AND DATE(disbursal_date) <= @last_day
      AND realization_date <= @closure_date
      AND product_id NOT IN (
          SELECT id
          FROM loan_products
          WHERE product_type = 'float_vending'
      )
      AND status NOT IN (
          'voided', 'hold',
          'pending_disbursal',
          'pending_mnl_dsbrsl'
      )
      AND l.loan_doc_id NOT IN (
          SELECT loan_doc_id
          FROM loan_write_off
          WHERE country_code = @country_code
            AND write_off_date <= @last_day
            AND write_off_status IN (
                'approved',
                'partially_recovered',
                'recovered'
            )
      )
    GROUP BY l.loan_doc_id
),
  
loan_installment AS (
    SELECT
        li.loan_doc_id,
        li.installment_number,
        li.principal_due + li.fee_due AS due,
        li.due_date
    FROM loan_installments li
    WHERE li.country_code = @country_code
      AND li.loan_doc_id IN (SELECT loan_doc_id FROM loan)
      AND EXTRACT(YEAR_MONTH FROM li.due_date) <= @month
),

payment AS (
    SELECT
        p.loan_doc_id,
        p.installment_number,
        SUM(p.allocated_amount) AS paid_amount
    FROM payment_allocation_items p
    JOIN account_stmts a
        ON a.id = p.account_stmt_id
    WHERE EXTRACT(YEAR_MONTH FROM stmt_txn_date) <= @month
      AND realization_date <= @closure_date
      AND p.country_code = @country_code
      AND a.country_code = @country_code
    GROUP BY p.loan_doc_id, p.installment_number
)

SELECT
    lo.loan_purpose,
    COUNT(*) AS total_due_installments,
    SUM(
        CASE 
            WHEN IFNULL(p.paid_amount,0) >= l.due THEN 1 
            ELSE 0 
        END
    ) AS ontime_installments,
    ROUND(
        SUM(CASE WHEN IFNULL(p.paid_amount,0) >= l.due THEN 1 ELSE 0 END)
        * 100.0 / COUNT(*),
        2
    ) AS overall_ontime_percentage
FROM loan_installment l
JOIN loan lo
    ON lo.loan_doc_id = l.loan_doc_id
LEFT JOIN payment p
    ON p.loan_doc_id = l.loan_doc_id
   AND p.installment_number = l.installment_number
GROUP BY lo.loan_purpose
ORDER BY lo.loan_purpose;