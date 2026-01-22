SET @country_code = 'UGA';
SET @month = '202510';

SET @prev_month = DATE_FORMAT(DATE_SUB(DATE(CONCAT(@month,'01')), INTERVAL 1 MONTH),'%Y%m');
SET @last_day = LAST_DAY(DATE(CONCAT(@month, '01')));

SET @closure_date = (
    SELECT closure_date
    FROM flow_api.closure_date_records
    WHERE status='enabled'
      AND month=@month
      AND country_code=@country_code
);

WITH loan AS (
    SELECT l.loan_doc_id, l.loan_purpose
    FROM loans l
    JOIN loan_txns lt ON lt.loan_doc_id = l.loan_doc_id
    WHERE lt.txn_type='af_disbursal'
      AND l.loan_purpose IN ('growth_financing','asset_financing')
      AND l.country_code=@country_code
      AND DATE(disbursal_date)<=@last_day
      AND realization_date<=@closure_date
      AND product_id NOT IN (
          SELECT id FROM loan_products WHERE product_type='float_vending'
      )
      AND status NOT IN ('voided','hold','pending_disbursal','pending_mnl_dsbrsl')
      AND l.loan_doc_id NOT IN (
          SELECT loan_doc_id
          FROM loan_write_off
          WHERE country_code=@country_code
            AND write_off_date<=@last_day
            AND write_off_status IN ('approved','partially_recovered','recovered')
      )
    GROUP BY l.loan_doc_id
),

loan_installment AS (
    SELECT
        loan_doc_id,
        installment_number,
        principal_due + fee_due AS installment_due,
        due_date
    FROM loan_installments
    WHERE loan_doc_id IN (SELECT loan_doc_id FROM loan)
),

payment AS (
    SELECT
        p.loan_doc_id,
        p.installment_number,
        SUM(p.allocated_amount) AS paid_amount,
        MAX(a.stmt_txn_date) AS max_stmt_txn_date
    FROM payment_allocation_items p
    JOIN account_stmts a ON a.id=p.account_stmt_id
    JOIN loan_installments li ON li.id=p.installment_id
    WHERE EXTRACT(YEAR_MONTH FROM a.stmt_txn_date)<=@month
      AND a.realization_date<=@closure_date
      AND p.country_code=@country_code
      AND a.country_code=@country_code
    GROUP BY p.loan_doc_id, p.installment_number
),

installment_os AS (
    SELECT
        l.loan_doc_id,
        l.loan_purpose,
        li.installment_number,
        li.installment_due,
        li.due_date,
        EXTRACT(YEAR_MONTH FROM li.due_date) AS due_month,
        IFNULL(p.paid_amount,0) AS paid_amount,
        GREATEST(li.installment_due-IFNULL(p.paid_amount,0),0) AS os_amount,
        p.max_stmt_txn_date,
        EXTRACT(YEAR_MONTH FROM p.max_stmt_txn_date) AS paid_month
    FROM loan l
    JOIN loan_installment li ON li.loan_doc_id=l.loan_doc_id
    LEFT JOIN payment p 
        ON p.loan_doc_id=li.loan_doc_id
       AND p.installment_number=li.installment_number
)

SELECT
    loan_purpose,

    /* Current Month Due */
    COUNT(CASE WHEN due_month=@month THEN 1 END) AS current_month_due_count,
    SUM(CASE WHEN due_month=@month THEN installment_due ELSE 0 END) AS current_month_due_amount,

    /* Fully Paid */
    COUNT(CASE WHEN due_month=@month AND os_amount=0 THEN 1 END) AS current_month_paid_count,
    SUM(CASE WHEN due_month=@month AND os_amount=0 THEN installment_due ELSE 0 END) AS current_month_paid_amount,

    /* Ontime Paid */
    COUNT(
        CASE 
            WHEN due_month=@month
             AND os_amount=0
             AND DATE(max_stmt_txn_date)<=DATE(due_date)
            THEN 1 
        END
    ) AS current_month_ontime_paid_count,
    SUM(
        CASE 
            WHEN due_month=@month
             AND os_amount=0
             AND DATE(max_stmt_txn_date)<=DATE(due_date)
            THEN installment_due ELSE 0
        END
    ) AS current_month_ontime_paid_amount,

    /* Partial Paid */
    COUNT(
        CASE 
            WHEN due_month=@month
             AND paid_amount>0
             AND os_amount>0
            THEN 1
        END
    ) AS current_month_partial_paid_count,
    SUM(
        CASE 
            WHEN due_month=@month
             AND paid_amount>0
             AND os_amount>0
            THEN paid_amount ELSE 0
        END
    ) AS current_month_partial_paid_amount,

    /* Not Paid */
    COUNT(CASE WHEN due_month=@month AND paid_amount=0 THEN 1 END) AS current_month_not_paid_count,
    SUM(CASE WHEN due_month=@month AND paid_amount=0 THEN installment_due ELSE 0 END) AS current_month_not_paid_amount,

    /* Previous Due Paid in Current Month */
    COUNT(
        CASE
            WHEN due_month<@month
             AND paid_month=@month
             AND os_amount=0
            THEN 1
        END
    ) AS previous_due_paid_in_current_month_count,
    SUM(
        CASE
            WHEN due_month<@month
             AND paid_month=@month
             AND os_amount=0
            THEN installment_due ELSE 0
        END
    ) AS previous_due_paid_in_current_month_amount,

    /* Future Paid in Advance */
    COUNT(
        CASE
            WHEN due_month>@month
             AND paid_month=@month
             AND os_amount=0
            THEN 1
        END
    ) AS future_due_paid_in_advance_count,
    SUM(
        CASE
            WHEN due_month>@month
             AND paid_month=@month
             AND os_amount=0
            THEN installment_due ELSE 0
        END
    ) AS future_due_paid_in_advance_amount,

    /* Overdue */
    COUNT(
        CASE
            WHEN due_month<=@month
             AND os_amount>0
            THEN 1
        END
    ) AS overdue_installment_count,
    SUM(
        CASE
            WHEN due_month<=@month
             AND os_amount>0
            THEN os_amount ELSE 0
        END
    ) AS overdue_installment_amount

FROM installment_os
GROUP BY loan_purpose
ORDER BY loan_purpose