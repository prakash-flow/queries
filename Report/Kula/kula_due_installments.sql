SET @country_code = 'UGA';
SET @month = '202602';

SET @report_date       = LAST_DAY(DATE(CONCAT(@month,'01')));
SET @report_end        = CONCAT(@report_date, ' 23:59:59');
SET @next_month_start  = DATE_ADD(@report_end, INTERVAL 1 SECOND);
SET @next_month_end    = CONCAT(LAST_DAY(@next_month_start), ' 23:59:59');

SET @closure_date = (
    SELECT closure_date
    FROM flow_api.closure_date_records
    WHERE status = 'enabled'
      AND month = @month
      AND country_code = @country_code
);

SELECT @country_code, @month, @report_end, @next_month_start, @next_month_end;


WITH loan AS (
    SELECT
        l.loan_doc_id,
        l.cust_id,
        l.cust_name,
        l.biz_name,
        l.flow_fee,
        l.loan_purpose,
        l.loan_principal,
        l.number_of_installments,
        l.schedule_grace_period,
        l.disbursal_date,

        ROW_NUMBER() OVER (
            PARTITION BY l.cust_id
            ORDER BY l.disbursal_date
        ) AS loan_sequence

    FROM loans l
    JOIN loan_txns lt
        ON lt.loan_doc_id = l.loan_doc_id
       AND lt.txn_type = 'af_disbursal'

    WHERE l.loan_purpose IN ('growth_financing','asset_financing')
      AND l.country_code = @country_code
      AND l.disbursal_date <= @report_end
      AND lt.realization_date <= @closure_date

      AND NOT EXISTS (
            SELECT 1
            FROM loan_products lp
            WHERE lp.id = l.product_id
            AND lp.product_type = 'float_vending'
      )

      AND l.status NOT IN (
            'voided','hold',
            'pending_disbursal',
            'pending_mnl_dsbrsl'
      )

      AND NOT EXISTS (
            SELECT 1
            FROM loan_write_off w
            WHERE w.loan_doc_id = l.loan_doc_id
              AND w.country_code = @country_code
              AND w.write_off_date <= @report_end
              AND w.write_off_status IN (
                    'approved',
                    'partially_recovered',
                    'recovered'
              )
      )
),

payment AS (
    SELECT
        p.loan_doc_id,
        p.installment_number,

        SUM(p.principal_amount) AS principal_paid,
        SUM(p.fee_amount)       AS fee_paid

    FROM payment_allocation_items p
    JOIN account_stmts a
        ON a.id = p.account_stmt_id

    WHERE a.realization_date <= @closure_date
      AND a.stmt_txn_date <= @report_end
      AND p.country_code = @country_code
      AND is_reversed = 0
      AND a.country_code = @country_code

    GROUP BY p.loan_doc_id, p.installment_number
),

installment_os AS (
    SELECT
        li.loan_doc_id,
        li.installment_number,
        li.due_date,

        li.principal_due,
        li.fee_due,

        COALESCE(p.principal_paid,0) AS principal_paid,
        COALESCE(p.fee_paid,0) AS fee_paid,

        (li.principal_due - COALESCE(p.principal_paid,0)) AS principal_os,
        (li.fee_due - COALESCE(p.fee_paid,0)) AS fee_os,

        (li.principal_due - COALESCE(p.principal_paid,0)) +
        (li.fee_due - COALESCE(p.fee_paid,0)) AS installment_os

    FROM loan_installments li
    LEFT JOIN payment p
        ON p.loan_doc_id = li.loan_doc_id
       AND p.installment_number = li.installment_number

    WHERE li.country_code = @country_code
),

loan_level AS (
    SELECT
        loan_doc_id,

        SUM(principal_os) AS principal_os_as_on_prev_month,

        SUM(IF(due_date > @report_end , principal_paid,0))
            AS future_allocated_pricipal_os,

        SUM(IF(due_date <= @report_end, fee_os, 0)) AS interest_os_as_on_prev_month,

        SUM(IF(due_date <= @report_end, installment_os, 0))
            AS total_overdue_os_as_on_prev_month,

        SUM(IF(due_date <= @report_end AND installment_os > 0,1,0))
            AS installment_not_paid_as_on_prev_month,

        SUM(
            IF(
                due_date BETWEEN @next_month_start AND @next_month_end,
                principal_paid + fee_paid,
                0
            )
        ) AS next_month_collected,
  
        MIN(
          IF(due_date BETWEEN @next_month_start AND @next_month_end, due_date, NULL)
        ) AS next_month_first_due_date,

        SUM(
            IF(
                due_date BETWEEN @next_month_start AND @next_month_end,
                principal_due + fee_due,
                0
            )
        ) AS next_month_due,

        SUM(installment_os) AS total_due

    FROM installment_os
    GROUP BY loan_doc_id
),

paid_till_report AS (
    SELECT
        p.loan_doc_id,
        SUM(p.principal_amount + p.fee_amount) AS total_paid

    FROM payment_allocation_items p
    JOIN account_stmts a
        ON a.id = p.account_stmt_id

    WHERE a.realization_date <= @closure_date
      AND a.stmt_txn_date <= @report_end
      AND a.country_code = @country_code
      AND p.country_code = @country_code
      AND is_reversed = 0

    GROUP BY p.loan_doc_id
)

SELECT

    l.cust_name AS client_name,
    l.biz_name  AS business_name,

    '' AS loan_agreement,

    l.cust_id     AS customer_id,
    l.loan_doc_id AS loan_id,

    case 
      when l.loan_purpose = 'growth_financing' then 'Kula Plus'
      when l.loan_purpose = 'asset_financing' then 'Kula Asset'
    end as loan_purpose,
  
    l.loan_sequence,

    DATE(l.disbursal_date) AS disbursal_date,

    l.loan_principal AS amount_disbursed,
    l.flow_fee,
    (l.number_of_installments + l.schedule_grace_period) AS tenor_months,

    COALESCE(ptr.total_paid,0) AS total_paid_till_report,

    (ll.principal_os_as_on_prev_month) as principal_os,
    ll.interest_os_as_on_prev_month,

    CASE
      WHEN ll.total_overdue_os_as_on_prev_month > 0 THEN 'Overdue'
      WHEN ll.total_due = 0 THEN 'Closed'
      ELSE 'Ongoing'
  END AS status,
    date(ll.next_month_first_due_date),
    ll.next_month_due,
    ll.next_month_collected,
    ll.total_overdue_os_as_on_prev_month,
    ll.installment_not_paid_as_on_prev_month

FROM loan l

LEFT JOIN loan_level ll
       ON ll.loan_doc_id = l.loan_doc_id

LEFT JOIN paid_till_report ptr
       ON ptr.loan_doc_id = l.loan_doc_id

ORDER BY customer_id, loan_sequence;