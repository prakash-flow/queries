SET @end_month = '202608';
SET @country_code = 'UGA';
SET @satrt_month = (SELECT DATE_FORMAT(DATE_SUB(STR_TO_DATE(CONCAT(@end_month, '01'), '%Y%m%d'), INTERVAL 2 MONTH), '%Y%m'));
SET @start_month_date = DATE(CONCAT(@satrt_month, '01'));
SET @end_month_date = DATE(CONCAT(@end_month, '01'));
SET @start_date = CONCAT(@start_month_date, ' 00:00:00');
SET @end_date   = CONCAT(LAST_DAY(@end_month_date), ' 23:59:59');

SET @sub_lender_code = 'FSD2';

SET @closure_date = (
    SELECT closure_date
    FROM closure_date_records
    WHERE country_code = @country_code
      AND status = 'enabled'
      AND month = @end_month
);

select @end_month,@country_code,@satrt_month,@start_month_date,@end_month_date,@start_date,@end_date,@sub_lender_code,@closure_date;

WITH loan_os AS (
    SELECT
        l.loan_doc_id,
        SUM(l.loan_principal) AS loan_principal,
        SUM(l.flow_fee) AS flow_fee,
        SUM(IFNULL(t.paid_principal, 0)) AS paid_principal,
        SUM(IFNULL(t.paid_fee, 0)) AS paid_fee,
        SUM(IFNULL(t.paid_charges, 0)) AS paid_charges,
        SUM(IFNULL(t.paid_penalty, 0)) AS paid_penalty,
        SUM(l.loan_principal)
            - SUM(IFNULL(t.paid_principal, 0)) AS principal_os,
        SUM(l.flow_fee)
            - (SUM(IFNULL(t.paid_fee, 0)) + SUM(IFNULL(t.fee_waiver, 0))) AS fee_os,
        DATEDIFF(@end_date, l.due_date) AS par_day,
        max(t.paid_date) as paid_date,
        sum(recovery_amount) as recovery_amount,
        sum(principal_recived) as principal_recived,
        sum(fee_recived) as fee_recived,
        sum(amount_recived) as amount_recived,
        sum(amount_recoverd) as amount_recoverd,
        ((SUM(l.loan_principal) + SUM(l.flow_fee))
            - (sum(amount_recived)+ SUM(IFNULL(t.fee_waiver, 0)) )) AS before_overdue_due_amount
    FROM loans l
    LEFT JOIN (
        SELECT
            l.loan_doc_id,
            SUM(if(txn_type = 'payment', t.principal,0)) AS paid_principal,
            SUM(if(txn_type = 'payment',t.fee,0)) AS paid_fee,
            SUM(if(txn_type = 'fee_waiver',t.fee,0)) AS fee_waiver,
            SUM(if(txn_type = 'payment',t.charges,0)) AS paid_charges,
            SUM(if(txn_type = 'payment',t.penalty,0)) AS paid_penalty,
            max(if(txn_type = 'payment' and (t.principal > 0 or t.fee > 0),t.txn_date,null)) as paid_date,
            sum(if(t.realization_date >= lw.write_off_date, amount , 0)) as recovery_amount,
            SUM(if(txn_type = 'payment' and (t.realization_date < lw.write_off_date), t.principal,0)) AS principal_recived,
            SUM(if(txn_type = 'payment'and (t.realization_date < lw.write_off_date),t.fee,0)) AS fee_recived,
            SUM(if(txn_type = 'payment' and (t.txn_date <= DATE_ADD(due_date, INTERVAL 1 DAY)), t.principal+t.fee,0)) AS amount_recived,
            SUM(if(txn_type = 'payment' and (t.txn_date > DATE_ADD(due_date, INTERVAL 1 DAY)), t.principal+t.fee,0)) AS amount_recoverd
        FROM loans l
        left JOIN loan_txns t
            ON l.loan_doc_id = t.loan_doc_id
        left join loan_write_off lw
            on lw.loan_doc_id = l.loan_doc_id
        WHERE l.country_code = @country_code
          -- AND l.disbursal_date BETWEEN @start_date AND @end_date
          and txn_type in ('payment','fee_waiver')
          AND l.status NOT IN (
              'pending_disbursal',
              'pending_mnl_dsbrsl',
              'voided',
              'hold'
          )
          AND l.sub_lender_code = @sub_lender_code
          AND t.txn_date <= @end_date
          AND t.realization_date <= @closure_date
        GROUP BY l.loan_doc_id
    ) t
        ON t.loan_doc_id = l.loan_doc_id

    WHERE l.country_code = @country_code
      -- AND l.disbursal_date BETWEEN @start_date AND @end_date
      AND l.status NOT IN (
          'pending_disbursal',
          'pending_mnl_dsbrsl',
          'voided',
          'hold'
      )
      AND l.sub_lender_code = @sub_lender_code

    GROUP BY l.loan_doc_id, l.due_date
),

disbursal_report as (
SELECT 
    "" AS `Institution ID`,
    l.cust_id AS `Borrower ID`,
    p.national_id as `Borrower NIN`,
      a.acc_number as `Agent identification number (if any)`,
    p.mobile_num as `Borrower_phone_number`,
    p.full_name AS `Borrower_name`, 
    p.gender as `Borrower_gender`,
    p.dob AS `Borrower_date_of_birth`,
    b.reg_date AS `Date of Registration`,
    "" AS Borrower_rating,
    ai.field_2 as `field_2`,
    IF(b.person_w_disability IS NULL, 'no', b.person_w_disability) AS `Borrower_PWD_Status`,
    "" AS `Borrower_Refugee_Status`,
    l.loan_doc_id as `loan_ID`,
    l.loan_principal as `loan_amount`,
    "1" as `loan_cycle`,
    CASE 
        WHEN (os.principal_os + os.fee_os) <= 0 THEN 'settled'
        WHEN os.par_day <= 0 THEN 'normal'
        WHEN os.par_day BETWEEN 1 AND 89 THEN 'Watch'
        WHEN os.par_day BETWEEN 90 AND 179 THEN 'Substandard'
        WHEN os.par_day BETWEEN 180 AND 359 THEN 'Doubtful'
        WHEN os.par_day >= 360 THEN 'Loss'
    END AS `loan_status`,
    if(os.par_day >0 and (os.principal_os + os.fee_os) > 0,os.par_day,0) as `Par Bucket`,
    l.interest_rate as `loan_interest_rate`,
    l.disbursal_date AS `loan_issue_date`,
    l.due_date AS `maturity_date`,
    os.principal_os as `principal_outstanding`,
    (os.principal_os + os.fee_os) as `exposure_at_default`,
    l.duration as `loan_tenure_in_days`
    
FROM loans l
JOIN borrowers b ON l.cust_id = b.cust_id
join accounts a on a.cust_id = b.cust_id and is_primary_acc = 1
join address_info ai on ai.id = b.owner_address_id 
JOIN persons p ON p.id = b.owner_person_id 
left join loan_os os on os.loan_doc_id = l.loan_doc_id
WHERE l.country_code = @country_code 
    AND l.disbursal_date BETWEEN @start_date AND @end_date 
    AND l.status NOT IN ('pending_disbursal', 'pending_mnl_dsbrsl', 'voided', 'hold') 
    AND l.sub_lender_code = @sub_lender_code
ORDER BY l.disbursal_date ASC ) ,

arrears_report as (
    select 
        l.cust_id as `borrower_ID`,
        l.loan_doc_id as `loan_ID`,
        CASE 
          WHEN (os.principal_os + os.fee_os) <= 0 THEN 'settled'
          WHEN os.par_day <= 0 THEN 'normal'
          WHEN os.par_day BETWEEN 1 AND 89 THEN 'Watch'
          WHEN os.par_day BETWEEN 90 AND 179 THEN 'Substandard'
          WHEN os.par_day BETWEEN 180 AND 359 THEN 'Doubtful'
          WHEN os.par_day >= 360 THEN 'Loss'
        END AS `loan_status`,
        if(os.par_day > 1,os.principal_os + os.fee_os, 0  ) AS `amount_in_arrears`,
        (os.principal_os + os.fee_os) as `outstanding_balance`,
        os.principal_os as `principal_outstanding`,
        if(os.par_day >0 and (os.principal_os + os.fee_os) > 0,os.par_day,0)  as `days_arrears`
      from  loans l
      left join loan_os os on os.loan_doc_id = l.loan_doc_id
      where l.country_code = @country_code 
      AND l.status NOT IN ('pending_disbursal', 'pending_mnl_dsbrsl', 'voided', 'hold') 
      AND l.sub_lender_code = @sub_lender_code  and (os.principal_os + os.fee_os) > 0 
),
repayments_report as (
    select 
        l.cust_id as `borrower_ID`,
        l.loan_doc_id as `loan_ID`,
        (os.paid_principal + os.paid_fee) as `repaid_amount`,
        (os.principal_os + os.fee_os) as `outstanding_balance`,
        if((os.principal_os + os.fee_os) <=0 , os.paid_date, null) as `repaid_date`,
        CASE 
          WHEN (os.principal_os + os.fee_os) <= 0 THEN 'settled'
          WHEN os.par_day <= 0 THEN 'normal'
          WHEN os.par_day BETWEEN 1 AND 89 THEN 'Watch'
          WHEN os.par_day BETWEEN 90 AND 179 THEN 'Substandard'
          WHEN os.par_day BETWEEN 180 AND 359 THEN 'Doubtful'
          WHEN os.par_day >= 360 THEN 'Loss'
        END AS `loan_status`
      from  loans l
      left join loan_os os on os.loan_doc_id = l.loan_doc_id
      where l.country_code = @country_code 
      AND l.status NOT IN ('pending_disbursal', 'pending_mnl_dsbrsl', 'voided', 'hold') 
      AND l.sub_lender_code = @sub_lender_code  and (os.paid_principal + os.paid_fee) > 0 
      and os.paid_date BETWEEN @start_date AND @end_date 
),
recoveries_report as (
  select 
        l.cust_id as `borrower_ID`,
        l.loan_doc_id as `loan_ID`,
        (amount_recoverd) as `recovered_amount`,
        (os.principal_os + os.fee_os) as `outstanding_amount`,
        if((os.principal_os + os.fee_os) <=0 , os.paid_date, null) as `recovery_date`,
        DATE_ADD(due_date, INTERVAL 1 DAY) as `default_date`,
        before_overdue_due_amount as `outstanding_balance_at_default_date`,
        "" as discounted_value_of_recovered_amount
      from  loans l
      left join loan_os os on os.loan_doc_id = l.loan_doc_id
      where l.country_code = @country_code 
      AND l.status NOT IN ('pending_disbursal', 'pending_mnl_dsbrsl', 'voided', 'hold') 
      AND l.sub_lender_code = @sub_lender_code  and amount_recoverd > 0 
),
rejected_loans AS (
    SELECT
        YEAR(l.loan_appl_date) AS `Year`,
        CONCAT('Q', QUARTER(l.loan_appl_date)) AS `Quarter`,
        '' AS `Institution ID`,
        l.loan_appl_doc_id AS `Loan ID`,
        TIMESTAMPDIFF(YEAR, p.dob, CURDATE()) AS `Age`,
        p.gender AS `Gender`,
        l.loan_principal AS `Loan Request Amount`,
        l.loan_purpose AS `Loan Purpose`

    FROM loan_applications l
    JOIN borrowers b
        ON l.cust_id = b.cust_id
    JOIN address_info ai
        ON ai.id = b.owner_address_id
    JOIN persons p
        ON p.id = b.owner_person_id

    WHERE l.status = 'rejected' and l.country_code = @country_code
      AND l.sub_lender_code = @sub_lender_code
)





-- select * from disbursal_report;
-- select * from arrears_report;
-- select * from repayments_report;
-- select * from recoveries_report;
SELECT * FROM rejected_loans;

