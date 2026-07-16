set @country_code = 'UGA';
set @month = '202606';
SET @pre_month = (SELECT DATE_FORMAT(DATE_SUB(STR_TO_DATE(CONCAT(@month, '01'), '%Y%m%d'), INTERVAL 1 MONTH), '%Y%m'));
SET @start_month = @month;
SET @start_date = CONCAT((DATE(CONCAT(@start_month, '01'))),' 00:00:00');
set @last_day = CONCAT((LAST_DAY(DATE(CONCAT(@month, "01")))),' 23:59:59');
set @realization_date = (IFNULL((select closure_date from closure_date_records where month = @month and status = 'enabled' and country_code = @country_code), CONCAT(@last_day, ' 23:59:59')));
set @pre_realization_date = ((select closure_date from closure_date_records where month = @pre_month and status = 'enabled' and country_code = @country_code));

select @start_date,@last_day,@realization_date,@pre_realization_date,@pre_month,@start_month;


with disbursals as (
          select
            l.id entity_id,
            date(@last_day) `As of`,
            CASE
                WHEN ((a.stmt_txn_date BETWEEN @start_date AND @last_day AND a.realization_date <= @realization_date) OR (a.stmt_txn_date < @start_date AND a.realization_date > @pre_realization_date AND a.realization_date <= @realization_date))
                THEN 'Current Month'
                ELSE 'Previous Month'
            END AS `Disbursal Transaction Period`,
            l.cust_id `Customer ID`,
            l.entity_id `Loan ID`,
            a.stmt_txn_id `Disbursal Transaction ID`,
            date(a.stmt_txn_date) `Disbursal Transaction Date`,
            a.acc_number `Disbursal Account Number`,
            datediff(date(@last_day), date(a.stmt_txn_date)) `PAR days`,
            obligation_amount `Duplicate`,
            if(lw.write_off_date is not null, 1, 0) `Is Written Off`,
            lw.write_off_date `Write Off Date`,
            CASE
                WHEN lt.loan_doc_id IS NOT NULL and la.loan_purpose in ('float_advance','terminal_financing') THEN 'Float Advance'
                WHEN lt.loan_doc_id IS NOT NULL and la.loan_purpose in ('adj_float_advance') THEN 'Regular Kula'
                WHEN st.sales_doc_id IS NOT NULL THEN 'Switch'
                ELSE 'Unknown'
             END AS `Purpose`
          from
            financial_obligations l
            left join account_stmts a on a.id = l.account_stmt_id
            left join financial_obligations_write_off lw on lw.stmt_txn_id = l.stmt_txn_id and lw.country_code = l.country_code and lw.write_off_date >= date(@last_day) and lw.write_off_date <= @last_day
            left join loan_txns lt on lt.txn_id = a.stmt_txn_id and a.acc_txn_type = lt.txn_type
            left join loans la on la.loan_doc_id = lt.loan_doc_id
            left join sales_txns st on st.txn_id = a.stmt_txn_id and a.acc_txn_type = st.txn_type
          where
            l.obligation_category in ('receivable')
            and l.country_code = @country_code
            and a.stmt_txn_date <= @last_day
            and a.realization_date <= @realization_date
            AND l.id not in (
                SELECT financial_obligation_id
                FROM financial_obligations_write_off
                WHERE write_off_date <= date(@last_day)
            )
        ),
        payments as (
          select
            l.entity_id,
            sum(l.allocated_amount) recovered,
            sum(l.principal_amount) reversal,
            sum(l.excess_amount) excess,
            sum(CASE WHEN ((a.stmt_txn_date BETWEEN @start_date AND @last_day AND a.realization_date <= @realization_date) OR (a.stmt_txn_date < @start_date AND a.realization_date > @pre_realization_date AND a.realization_date <= @realization_date)) THEN l.allocated_amount ELSE 0 END) recovered_new,
            sum(CASE WHEN ((a.stmt_txn_date BETWEEN @start_date AND @last_day AND a.realization_date <= @realization_date) OR (a.stmt_txn_date < @start_date AND a.realization_date > @pre_realization_date AND a.realization_date <= @realization_date)) THEN l.principal_amount ELSE 0 END) reversal_new,
            sum(CASE WHEN ((a.stmt_txn_date BETWEEN @start_date AND @last_day AND a.realization_date <= @realization_date) OR (a.stmt_txn_date < @start_date AND a.realization_date > @pre_realization_date AND a.realization_date <= @realization_date)) THEN l.excess_amount ELSE 0 END) excess_new,
            sum(CASE WHEN NOT ((a.stmt_txn_date BETWEEN @start_date AND @last_day AND a.realization_date <= @realization_date) OR (a.stmt_txn_date < @start_date AND a.realization_date > @pre_realization_date AND a.realization_date <= @realization_date)) THEN l.allocated_amount ELSE 0 END) recovered_old,
            sum(CASE WHEN NOT ((a.stmt_txn_date BETWEEN @start_date AND @last_day AND a.realization_date <= @realization_date) OR (a.stmt_txn_date < @start_date AND a.realization_date > @pre_realization_date AND a.realization_date <= @realization_date)) THEN l.principal_amount ELSE 0 END) reversal_old,
            sum(CASE WHEN NOT ((a.stmt_txn_date BETWEEN @start_date AND @last_day AND a.realization_date <= @realization_date) OR (a.stmt_txn_date < @start_date AND a.realization_date > @pre_realization_date AND a.realization_date <= @realization_date)) THEN l.excess_amount ELSE 0 END) excess_old,
            max(a.stmt_txn_date) payment_txn_date,
            substring_index(group_concat(a.stmt_txn_id order by a.stmt_txn_date desc), ',', 1) payment_txn_id,
            substring_index(group_concat(a.acc_number order by a.stmt_txn_date desc), ',', 1) payment_account_number,
            CASE
                WHEN lt.loan_doc_id IS NOT NULL and la.loan_purpose in ('float_advance','terminal_financing') THEN 'Float Advance'
                WHEN lt.loan_doc_id IS NOT NULL and la.loan_purpose in ('adj_float_advance') THEN 'Regular Kula'
                WHEN st.sales_doc_id IS NOT NULL THEN 'Switch'
                ELSE 'Unknown'
             END AS `Purpose`
          from
            payment_allocation_items l
            left join account_stmts a on a.id = l.account_stmt_id
            left join loan_txns lt on lt.txn_id = a.stmt_txn_id and a.acc_txn_type = lt.txn_type
            left join loans la on la.loan_doc_id = lt.loan_doc_id
            left join sales_txns st on st.txn_id = a.stmt_txn_id and a.acc_txn_type = st.txn_type
          where
            l.entity_type = 'financial_obligation'
            and a.country_code = @country_code
          group by l.entity_id,lt.loan_doc_id,st.sales_doc_id
        ),
parsedLoans as (
  select
    
            pri.`As of`,
            pri.`Customer ID` as `Customer ID`,
            pri.`Purpose`,
            pri.`Disbursal Transaction ID`,
            pri.`Disbursal Transaction Date`,
            pri.`Duplicate`,
            ifnull(recovered, 0) `Total Reversal`,
            (Duplicate - ifnull(reversal,0)) `Pending Amount`,
            `Disbursal Transaction Period`
        
  from
    disbursals pri
    left join payments pp on pri.entity_id = pp.entity_id
),

loan_rank AS (
    SELECT
        cust_id,
        disbursal_date,
        due_date,
        current_os_amount,
        status,
        RANK() OVER (
            PARTITION BY cust_id
            ORDER BY disbursal_date desc
        ) AS rnk
    FROM loans
    where country_code = 'UGA' and cust_id in (select `Customer ID` from parsedLoans where `Disbursal Transaction Period` = 'Current Month')
      AND status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
              and product_id not in (43, 75, 300)
  ),
loan_status as (
SELECT *
FROM loan_rank
WHERE rnk = 1)

  
select p.*,l.status  as loan_status 
from parsedLoans p
left join loan_status l on p.`Customer ID` = l.cust_id
where 
  `Disbursal Transaction Period` = 'Current Month' 
;









