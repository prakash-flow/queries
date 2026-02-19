SET @country_code = 'RWA';
SET @month = '202512';

SET @last_day = (
    SELECT LAST_DAY(DATE(CONCAT(@month, '01')))
);

SET @cutoff_date = CONCAT(@last_day, ' 23:59:59');

SET @closure_date = (
    SELECT closure_date
    FROM flow_api.closure_date_records
    WHERE status = 'enabled'
      AND month = @month
      AND country_code = @country_code
);
select @country_code, @month, @last_day, @closure_date;


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
    GROUP BY l.loan_doc_id,l.cust_id,l.loan_purpose
),
  loan_installment AS (
    SELECT
        loan_doc_id,
        id,
        principal_due AS installment_principal,
        if(due_date <= @cutoff_date, fee_due, 0) AS installment_fee,
        due_date,
        (principal_due + fee_due) AS installment_amount
    FROM loan_installments
    WHERE loan_doc_id IN (SELECT loan_doc_id FROM loan)
)
,
-- select * from loan_installment where loan_doc_id = 'UFLW-36267-1565346'

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
        ON li.id = p.installment_id AND DATE(li.due_date) <= @last_day
    WHERE EXTRACT(YEAR_MONTH FROM stmt_txn_date) <= @month
      AND realization_date <= @closure_date
      AND p.country_code = @country_code
      AND a.country_code = @country_code
    GROUP BY p.loan_doc_id, p.installment_id
),

/* ===============================
   Installment-level OS
================================ */
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
        
        installment_amount
    FROM loan l
    JOIN loan_installment li
        ON li.loan_doc_id = l.loan_doc_id 
  -- AND DATE(li.due_date) <= @last_day
    LEFT JOIN payment p
        ON p.loan_doc_id = li.loan_doc_id
       AND p.installment_id = li.id
),
-- select * from installment_os where loan_doc_id = 'UFLW-36267-1565346'

/* ===============================
   Loan-level OS + MIN overdue due_date
================================ */
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
        /* Total outstanding per loan */
        SUM(os_amount) AS loan_os,

        MIN(CASE
            WHEN os_amount > 0 AND DATE(due_date) <= @last_day
            THEN due_date
        END) AS min_overdue_due_date
    FROM installment_os
    GROUP BY loan_doc_id, loan_purpose,cust_id
),

/* ===============================
   Loan-level PAR days
================================ */
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
        CASE
            WHEN loan_os = 0
              OR min_overdue_due_date IS NULL
            THEN 0
            ELSE DATEDIFF(@last_day, min_overdue_due_date)
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
    Max(par_days) As par_days
FROM loan_level_par
GROUP BY loan_purpose,loan_doc_id,cust_id
ORDER BY loan_purpose ) ,
next_due_date AS (
    SELECT
        loan_doc_id,
        min(due_date) as next_due_date
    FROM loan_installments
    WHERE loan_doc_id IN (SELECT loan_doc_id FROM loans) and due_date > @cutoff_date group by loan_doc_id
),
last_max_due_date AS (
    SELECT
        loan_doc_id,
        max(due_date) as max_due_date
    FROM loan_installments
    WHERE loan_doc_id IN (SELECT loan_doc_id FROM loans) and due_date <= @cutoff_date group by loan_doc_id
),
last_payment as (
    select 
        p.loan_doc_id ,
        sum(ifnull(allocated_amount,0)) as last_payment
      from 
      payment p
     join (select loan_doc_id ,max(id) as id from loan_installments where due_date <= @cutoff_date group by loan_doc_id) as i on p.installment_id = i.id group by p.loan_doc_id
)
  select
      p.full_name as `Client Name`,
      p.national_id as `Client National ID`,
      p.mobile_num as `Client Primary Mobile No`,
      "" as `Loan agreement`,
      o.loan_doc_id as `Loan ID`,
      o.cust_id as `Customer ID`,
      o.loan_purpose as `Kula Category`,
      l.disbursal_date as `Date of Disbursement`,
      first_due_date as `1st EMI date`,
      lm.max_due_date as `Last Installment Due Date`,
      n.next_due_date as `Next Due Date`,
      l.due_date as `Loans Last Due Date`,
      l.loan_principal as `Disbursement Amount`,
      l.flow_fee as `Total Interest`,
      installment_amount as `Monthly Installment`,
      -- "" as IRR,
      lp.last_payment as `Last Paid Amount`,
      o.Paid_amount as `Total Paid Amount`,
      o.total_outstanding  as `Principal OS (as on 31 Dec 2025 )`,
      o.total_outstanding_fee as `Interest OS (as on 31 Dec 2025 )`,
      CASE
            WHEN par_days > 0 THEN 'Overdue'
            WHEN par_days = 0 and o.total_outstanding > 0 THEN 'Ongoing'
            WHEN par_days = 0 and o.total_outstanding = 0 THEN 'Closed'
        ELSE 'not defined'
        END
      as `Status`,
      par_days as `Arrear days`,
      if(par_days = 0,last_paid_date,null) as `Last paid date`,
      l.duration AS `Term (in Months)`,
      l.schedule_grace_period as `schedule_grace_period (in months)`,
      l.schedule_part_period as `schedule_part_period (in months)`,
      "" as `Last visit date by RM`,
      "" as `Last visit date by collection officer`,
      interest_rate as `Interest Rate (monthly)`
  from
    os o 
    join loans l on l.loan_doc_id = o.loan_doc_id
    left join borrowers b on o.cust_id = b.cust_id
    left join persons p on p.id = b.owner_person_id
    left join next_due_date n on n.loan_doc_id = o.loan_doc_id
    left join last_max_due_date lm on lm.loan_doc_id = o.loan_doc_id
    left join last_payment lp on lp.loan_doc_id = o.loan_doc_id
   -- where l.loan_doc_id = 'UFLW-40751B-1569127'
  order by disbursal_date
;









