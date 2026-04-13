SET @country_code = 'UGA';
SET @month = '202602';

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
)

SELECT
    @month as Month,
   la.loan_purpose as `Loan Purpose`,
    -- l.loan_doc_id,
    SUM(loan_os) AS principal_os,
    SUM(IF(par_days between 2 and 15,  loan_os, 0)) AS par_2and_15,
    SUM(IF(par_days between 16 and 30,  loan_os, 0)) AS par_16_and_30,
    SUM(IF(par_days between 31 and 60,  loan_os, 0)) AS par_31_and_60,
    SUM(IF(par_days > 60,  loan_os, 0)) AS par_60,
    SUM(IF(par_days > 90,  loan_os, 0)) AS par_90,
    -- COUNT(DISTINCT IF((loan_os > 0 or fee_os>0) , cust_id, NULL)) AS cust_count,
    -- COUNT(DISTINCT IF(par_days > 1 AND (loan_os > 0 or fee_os>0) , cust_id, NULL)) AS overdue_count,
    -- COUNT(DISTINCT IF(par_days > 1 AND (loan_os > 0 or fee_os>0) AND date(l.due_date) < @last_day, cust_id, NULL)) AS overdue_tenor_expiry_count,
    COUNT(DISTINCT IF((loan_os > 0 or fee_os>0) , la.loan_doc_id, NULL)) AS cust_count_loan,
    COUNT(DISTINCT IF(par_days > 1 AND (loan_os > 0 or fee_os>0) , la.loan_doc_id, NULL)) AS overdue_count_loan,
    COUNT(DISTINCT IF(par_days > 1 AND (loan_os > 0 or fee_os>0) AND date(l.due_date) < @last_day, la.loan_doc_id, NULL)) AS overdue_tenor_expiry_count_loan,
    SUM(IF(par_days > 1 , current_due , 0)) AS `Total overdue`

FROM loan_level_par la
join loans l on la.loan_doc_id = l.loan_doc_id
left join current_due cd on l.loan_doc_id = cd.loan_doc_id
GROUP BY la.loan_purpose
  -- ,l.loan_doc_id
ORDER BY la.loan_purpose desc
  -- ,l.loan_doc_id
  ;





