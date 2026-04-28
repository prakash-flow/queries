SET @country_code='UGA';
SET @report_date='2026-02-28';
SET @month='202602';
SET @last_day=@report_date;
SET @cutoff_date=CONCAT(@last_day,' 23:59:59');
SET @one_daybefore='2026-02-27 23:59:59';



WITH loan AS (
    SELECT
        l.cust_id ,
        l.loan_doc_id,
        l.loan_purpose
    FROM loans l
    JOIN loan_txns lt
        ON lt.loan_doc_id = l.loan_doc_id
    WHERE lt.txn_type IN ('af_disbursal')
      AND l.loan_purpose IN ('growth_financing', 'asset_financing')
      AND l.country_code COLLATE utf8mb4_unicode_ci = @country_code
      AND DATE(disbursal_date) <= @last_day
      -- AND realization_date <= IFNULL(@closure_date, NOW())
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
          WHERE country_code COLLATE utf8mb4_unicode_ci = @country_code
            AND write_off_date <= @last_day
            AND write_off_status IN (
                'approved',
                'partially_recovered',
                'recovered'
            )
      )
    GROUP BY l.loan_doc_id,l.cust_id,l.loan_purpose
),
  loan_installment AS (
    SELECT
        loan_doc_id,
        id,
        principal_due AS installment_principal,
        if(due_date <= @cutoff_date, principal_due, 0) AS over_principal_due,
        if(due_date <= @cutoff_date, fee_due, 0) AS installment_fee,
        due_date,
        (principal_due + fee_due) AS installment_amount
    FROM loan_installments
    WHERE loan_doc_id IN (SELECT loan_doc_id FROM loan) )
,

payment AS (
    SELECT
        p.loan_doc_id,
        p.installment_id,
        sum(ifnull(p.allocated_amount,0)) as allocated_amount,
        SUM(p.principal_amount) AS paid_principal,
        SUM(p.fee_amount) AS paid_fee,
        MAX(a.stmt_txn_date) as last_paid_date
    FROM payment_allocation_items p
    JOIN account_stmts a
        ON a.id = p.account_stmt_id
    JOIN loan_installments li
        ON li.id = p.installment_id 
    WHERE EXTRACT(YEAR_MONTH FROM stmt_txn_date) <= @month
      -- AND realization_date <= IFNULL(@closure_date, NOW())
       AND is_reversed = 0
      AND stmt_txn_date <= @one_daybefore
      AND p.country_code COLLATE utf8mb4_unicode_ci = @country_code
      AND a.country_code COLLATE utf8mb4_unicode_ci = @country_code
    GROUP BY p.loan_doc_id, p.installment_id
),

installment_os AS (
    SELECT
        l.cust_id,
        l.loan_doc_id,
        l.loan_purpose,
        li.due_date,
        p.last_paid_date,
        ( IFNULL(p.allocated_amount,0) ) as Paid_amount,
        GREATEST(
            li.installment_principal - IFNULL(p.paid_principal, 0),
            0
        ) AS os_amount,
        GREATEST(
            li.installment_fee - IFNULL(p.paid_fee, 0),
            0
        ) AS fee_os_amount,
        GREATEST(
            li.over_principal_due - IFNULL(p.paid_principal, 0),
            0
        ) AS over_principal_due_amount,
        installment_amount
    FROM loan l
    JOIN loan_installment li
        ON li.loan_doc_id = l.loan_doc_id 
    LEFT JOIN payment p
        ON p.loan_doc_id = li.loan_doc_id
       AND p.installment_id = li.id
),

loan_level_os AS (
    SELECT
        cust_id,
        loan_doc_id,
        loan_purpose,
        min(due_date) as due_date,
        max(installment_amount) as installment_amount,
        sum(Paid_amount) as Paid_amount,
        sum(fee_os_amount) as fee_os,
        MAX(last_paid_date) as last_paid_date,
        SUM(os_amount) AS loan_os,
        sum(over_principal_due_amount) as over_principal_due_amount,

        MIN(CASE
            WHEN (os_amount + fee_os_amount) > 0  AND DATE(due_date) <= @last_day
            THEN due_date
        END) AS min_overdue_due_date
    FROM installment_os
    GROUP BY loan_doc_id, loan_purpose,cust_id
),

loan_level_par AS (
    SELECT
        cust_id,
        loan_doc_id,
        loan_purpose,
        fee_os,
        Paid_amount,
        loan_os,
        due_date,
        last_paid_date,
        installment_amount,
        over_principal_due_amount,
        CASE
            WHEN (loan_os + fee_os) = 0
              OR min_overdue_due_date IS NULL
            THEN 0
            ELSE DATEDIFF(@last_day, date(min_overdue_due_date))
        END AS par_days
    FROM loan_level_os
),
os as (
SELECT
    cust_id,
    loan_doc_id,
    max(installment_amount) as installment_amount,
    loan_purpose AS loan_purpose,
    sum(Paid_amount) as Paid_amount,
    MAX(last_paid_date) as last_paid_date,
    Min(due_date) AS first_due_date,
    sum(fee_os)  AS total_outstanding_fee,
    SUM(loan_os) AS total_outstanding,
    Max(par_days) As par_days,
    sum(if (par_days > 1,over_principal_due_amount + fee_os,0  )) as over_due_amt
FROM loan_level_par
GROUP BY loan_purpose,loan_doc_id,cust_id
ORDER BY loan_purpose ) ,

full_payments as (
  SELECT
        p.loan_doc_id,
        sum(ifnull(p.allocated_amount,0)) as allocated_amount,
        (SUM(p.principal_amount) + SUM(p.fee_amount)) AS Paid_amount,
        MAX(a.stmt_txn_date) as last_paid_date
    FROM payment_allocation_items p
    JOIN account_stmts a
        ON a.id = p.account_stmt_id
    JOIN loan_installments li
        ON li.id = p.installment_id 
    -- AND DATE(li.due_date) <= @last_day
    WHERE p.country_code COLLATE utf8mb4_unicode_ci = @country_code
      AND a.country_code COLLATE utf8mb4_unicode_ci = @country_code
       AND is_reversed = 0
      AND a.stmt_txn_date <= @cutoff_date
    GROUP BY p.loan_doc_id
),
EMI as (
  select loan_doc_id,id , 
          sum(principal_due) as principal_due ,
          sum(fee_due) as fee_due,
          (sum(principal_due) + sum(fee_due)) as due_amount ,max(due_date) as curr_due_date
  from loan_installments where extract(year_month from due_date) = @month group by loan_doc_id,id
),
current_due as (
  select 
      e.loan_doc_id,
      ( (sum(principal_due) + sum(fee_due)) - ( sum(ifnull(paid_principal,0)) + sum(ifnull(paid_fee,0) )) ) as current_due
      #(ifnull(paid_principal,0) + ifnull(paid_fee,0) ) as paid_amount
  from loan_installments e left join  
  payment pa on 
  pa.installment_id = e.id and 
  pa.loan_doc_id = e.loan_doc_id
  where extract(year_month from due_date) <= @month 
  and due_date <= @cutoff_date
  group by e.loan_doc_id
),
loan_sqn as (
    SELECT 
        loan_doc_id,
        disbursal_date,
        ROW_NUMBER() OVER (
            PARTITION BY cust_id
            ORDER BY disbursal_date ASC
        ) AS rn
    FROM loans
    WHERE loan_purpose IN ('growth_financing', 'asset_financing')
      AND country_code COLLATE utf8mb4_unicode_ci = @country_code
      AND product_id NOT IN (
          SELECT id
          FROM loan_products
          WHERE product_type = 'float_vending'
      )
      AND status NOT IN (
          'voided',
          'hold',
          'pending_disbursal',
          'pending_mnl_dsbrsl'
      )
),

  final_os as (select
      @report_date as report_date,
      o.loan_doc_id,
      sum(o.total_outstanding) as os_principal  ,
      sum(o.total_outstanding_fee) as os_fee ,
      sum( if((o.total_outstanding+o.total_outstanding_fee) >0 ,1, 0) ) as Os_count,
      sum( if((o.par_days) >1 and (o.total_outstanding+o.total_outstanding_fee) >0 ,1, 0) ) as Overdue_count,
      sum(ifnull(current_due,0)) as current_due,
      SUM(IF(par_days <= 1, total_outstanding + total_outstanding_fee , 0)) AS `due`,
      SUM(IF(par_days > 1, total_outstanding + total_outstanding_fee , 0)) AS `Total overdue`,
      SUM(IF(par_days > 1, total_outstanding , 0)) AS `Total overdue_prin`,
      SUM(IF(par_days > 1, total_outstanding_fee , 0)) AS `Total overdue_fee`
  from
    os o 
    join loans l on l.loan_doc_id = o.loan_doc_id
    left join borrowers b on o.cust_id = b.cust_id
    left join persons p on p.id = b.owner_person_id
    left Join full_payments fp on fp.loan_doc_id = o.loan_doc_id
    Left Join EMI fd on fd.loan_doc_id = o.loan_doc_id 
    left Join current_due cd on cd.loan_doc_id = o.loan_doc_id 
    left join loan_sqn s on s.loan_doc_id = o.loan_doc_id
  group by o.loan_doc_id
  order by o.par_days desc),
-- select * from final_os ;
collection as (
  select date(stmt_txn_date) as report_date ,count(distinct a.loan_doc_id) as count_loans,sum(p.allocated_amount) as total_amount,
  sum(principal_amount) as principal,sum(fee_amount) as Fee
  from payment_allocation_items p
  join account_stmts  a  on a.stmt_txn_id = p.stmt_txn_id and a.id = p.account_stmt_id
  where 
  date(stmt_txn_date) = @report_date
   AND is_reversed = 0
  and a.country_code ='UGA' and acc_txn_type = 'af_payment' 
  group by date(stmt_txn_date) 
  )

select 
  o.report_date,
  loan_doc_id,
  o.os_principal,
  o.os_fee,
  o.Os_count,
  o.Overdue_count,
  o.current_due,
  ifnull(c.count_loans,0),
  ifnull(c.total_amount,0),
  ifnull(c.principal,0),
  ifnull(c.Fee,0)
from final_os o 
left join collection c on o.report_date = c.report_date









