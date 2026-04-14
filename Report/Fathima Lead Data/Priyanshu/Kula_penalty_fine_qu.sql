SET @country_code = 'UGA';
SET @month = '202604';

SET @last_day = (
    SELECT LAST_DAY(DATE(CONCAT(@month, '01')))
);
-- SET @last_day = '2026-04-12';

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
        loan_doc_id,
        installment_number,
        principal_due AS installment_principal,
        if(date(due_date) <= @last_day,fee_due,0 ) as fee_due,
        date(due_date) as due_date
    FROM loan_installments
    WHERE loan_doc_id IN (SELECT loan_doc_id FROM loan)
),

payment AS (
    SELECT
        p.loan_doc_id,
        p.installment_number,
        p.installment_id,
        SUM(p.principal_amount) AS paid_principal,
        sum(p.fee_amount) as paid_fee
    FROM payment_allocation_items p
    JOIN account_stmts a
        ON a.id = p.account_stmt_id
    JOIN loan_installments li
        ON li.id = p.installment_id 
    WHERE EXTRACT(YEAR_MONTH FROM stmt_txn_date) <= @month
      AND is_reversed = 0
      AND p.country_code = @country_code
      AND a.country_code = @country_code
    GROUP BY p.loan_doc_id, p.installment_number,p.installment_id
),

installment_os AS (
    SELECT
        l.loan_doc_id,
        l.loan_purpose,
        li.due_date,
        GREATEST(
            li.installment_principal - IFNULL(p.paid_principal, 0),
            0
        ) AS os_amount,
        GREATEST(fee_due - ifnull(paid_fee,0),0) as fee_os
    FROM loan l
    JOIN loan_installment li
        ON li.loan_doc_id = l.loan_doc_id 
    LEFT JOIN payment p
        ON p.loan_doc_id = li.loan_doc_id
       AND p.installment_number = li.installment_number
),


loan_level_os AS (
    SELECT
        loan_doc_id,
        loan_purpose,

        SUM(os_amount) AS loan_os,
        sum(fee_os) AS fee_os,
        MIN(CASE
            WHEN (os_amount > 0 or fee_os > 0 ) AND DATE(due_date) <= @last_day
            THEN due_date
        END) AS min_overdue_due_date
    FROM installment_os
    GROUP BY loan_doc_id, loan_purpose
),

current_due as (
  select 
      e.loan_doc_id,
      ( (sum(principal_due) + sum(fee_due)) - ( sum(ifnull(paid_principal,0)) + sum(ifnull(paid_fee,0) )) ) as current_due
  from loan_installments e left join  
  payment pa on 
  pa.installment_id = e.id and 
  pa.loan_doc_id = e.loan_doc_id
  where extract(year_month from due_date) <= @month 
  and date(due_date) <= @last_day
  group by e.loan_doc_id
),
loan_level_par AS (
    SELECT
        loan_doc_id,
        loan_purpose,
        loan_os,
        if(fee_os<0,0,fee_os) as fee_os,
        CASE
            WHEN loan_os = 0
              OR min_overdue_due_date IS NULL
            THEN 0
            ELSE DATEDIFF(@last_day, min_overdue_due_date)
        END AS par_days
    FROM loan_level_os
),
instalments as (select loan_doc_id,max(fee_due) as fee_due from loan_installments 
where country_code = @country_code group by loan_doc_id
),
final_df AS (
SELECT
    @month AS Month,
    la.loan_purpose,
    l.loan_doc_id,
    DATE(l.due_date) AS due_date,

    SUM(loan_os) AS principal_os,
    SUM(fee_os) AS fee_os,

    SUM(IF(par_days > 1, current_due, 0)) AS total_overdue,

    CASE 
        WHEN DATE(l.due_date) < @last_day 
        THEN TIMESTAMPDIFF(MONTH, DATE(l.due_date), @last_day)
        ELSE 0
    END AS not_paid_month,

    MAX(fee_due) AS instalment_amount

FROM loan_level_par la
JOIN loans l ON la.loan_doc_id = l.loan_doc_id
JOIN instalments i ON i.loan_doc_id = la.loan_doc_id 
LEFT JOIN current_due cd ON l.loan_doc_id = cd.loan_doc_id

GROUP BY 
    la.loan_purpose,
    l.loan_doc_id,
    DATE(l.due_date)
)

SELECT 
    loan_purpose,
    loan_doc_id,
    @last_day,
    due_date,
    if(datediff(@last_day,due_date) >0 , datediff(@last_day,due_date) ,0)  as date_dif,
    principal_os,
    fee_os,
    total_overdue,
    not_paid_month,
    instalment_amount,
    (not_paid_month * instalment_amount) AS fine_amount

FROM final_df
WHERE total_overdue > 0 ;









