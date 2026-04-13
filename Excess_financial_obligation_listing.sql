SET @month = '202601';
SET @country_code = 'UGA';
SET @pre_month = (SELECT DATE_FORMAT(DATE_SUB(STR_TO_DATE(CONCAT(@month, '01'), '%Y%m%d'), INTERVAL 1 MONTH), '%Y%m'));
SET @write_off_date = CONCAT(LAST_DAY(DATE(CONCAT(@pre_month, "01"))),' 23:59:59');
SET @start_date = CONCAT(DATE(CONCAT(@month, "01")),' 00:00:00');
SET @cutoff_date = LAST_DAY(DATE(CONCAT(@month, "01")));
SET @last_day = CONCAT(@cutoff_date,' 23:59:59');

SET @realization_date = (
    SELECT closure_date 
    FROM closure_date_records 
    WHERE country_code = @country_code 
      AND month = @month 
      AND status = 'enabled'
);
SET @pre_realization_date = (
    SELECT closure_date 
    FROM closure_date_records 
    WHERE country_code = @country_code 
      AND month = @pre_month
      AND status = 'enabled'
);


with disbursals as (
  select 
    l.id entity_id,
    @cutoff_date AS `As of`,
    UPPER(l.entity_type) `Source`,
    l.cust_id `Customer ID`,
    l.entity_id `Loan ID`, 
    a.stmt_txn_id `Txn ID`,
    date(a.stmt_txn_date) `Txn Date`,
    datediff(date(@last_day), date(a.stmt_txn_date)) `PAR days`,
    obligation_amount `Excess Received`,
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
    left join financial_obligations_write_off lw on lw.stmt_txn_id = l.stmt_txn_id and lw.country_code = l.country_code and extract(year_month from lw.write_off_date) = '202603'
    left join loan_txns lt on lt.txn_id = a.stmt_txn_id and a.acc_txn_type = lt.txn_type
    left join loans la on la.loan_doc_id = lt.loan_doc_id
    left join sales_txns st on st.txn_id = a.stmt_txn_id and a.acc_txn_type = st.txn_type
  where 
    l.obligation_category in ('payable') 
    and l.country_code = @country_code
    and a.stmt_txn_date <= @last_day
    AND (
        (stmt_txn_date BETWEEN @start_date  AND @last_day AND a.realization_date <= @realization_date)
        OR
        (stmt_txn_date < @start_date  AND a.realization_date > @pre_realization_date AND a.realization_date <= @realization_date)
    )
    and a.realization_date <= @realization_date
    AND l.id not in (
        SELECT financial_obligation_id 
        FROM financial_obligations_write_off 
        WHERE write_off_date <= @write_off_date
    )
),
payments as (
  select 
    l.entity_id, 
    sum(l.allocated_amount) recovered,
    sum(l.principal_amount) reversal,
    sum(l.excess_amount) excess,
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
    and a.stmt_txn_date <= @last_day
    and a.realization_date <= @realization_date
    AND (
        (stmt_txn_date BETWEEN @start_date  AND @last_day AND a.realization_date <= @realization_date)
        OR
        (stmt_txn_date < @start_date  AND a.realization_date > @pre_realization_date AND a.realization_date <= @realization_date)
    )
  group by l.entity_id,lt.loan_doc_id,st.sales_doc_id 
),
parsedLoans as (
  select
    
pri.*,
ifnull(reversal, 0) `Excess reversed`,
(`Excess Received` - ifnull(reversal,0)) `OS amount`

  from 
    disbursals pri 
    left join payments pp on pri.entity_id = pp.entity_id
)
select * from parsedLoans 
# having `OS amount` > 0 
order by `PAR days` desc;
