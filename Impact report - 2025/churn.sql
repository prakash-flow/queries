with customers as (
  select 
    country_code,
    cust_id,
    reg_date,
    tot_loans
    -- timestampdiff(month, reg_date, @report_date) `months_w_flow`
  from 
    borrowers 
  where 
    (
      -- category is null #this is kula, we can ignore
      -- or 
      category != 'float_switch'
    )
    -- and extract(year_month from reg_date) between @reg_month_start and @reg_month_end
    and extract(year_month from reg_date) = @reg_month
    and country_code = @country_code
    -- limit 10
),
-- select * from customers;
filteredLoans as (
  select
    b.cust_id,
    l.loan_doc_id,
    date(l.disbursal_date) disbursal_date,
    l.status,
    l.loan_purpose
  from
    customers b
    left join loans l on l.cust_id = b.cust_id
  where
    disbursal_date <= @report_date
    and l.loan_purpose in (@loan_purpose)
    and product_id not in (select id from loan_products where product_type = 'float_vending')
    and status not in ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
),
loanRevenue as (
  select 
    t.loan_doc_id,
    sum(
      case 
        when lw.write_off_date is null then ifnull(t.fee,0)+ifnull(t.penalty,0)
        when date(t.txn_date) <= lw.write_off_date then ifnull(t.fee,0)+ifnull(t.penalty,0)
        else ifnull(t.principal,0) + ifnull(t.fee,0) + ifnull(t.charges,0) + ifnull(t.penalty,0)
      end
    ) revenue
  from 
    filteredLoans l 
    left join loan_txns t on l.loan_doc_id = t.loan_doc_id 
    left join loan_write_off lw on lw.loan_doc_id = l.loan_doc_id
  where  
    t.txn_date <= @report_date
    and l.loan_purpose in (@loan_purpose)
    and t.txn_type = 'payment'
    and t.country_code = @country_code
  group by t.loan_doc_id
),
loans_w_revenue as (
  select
    l.*,
    ifnull(lt.revenue, 0) revenue
  from
    filteredLoans l
    left join loanRevenue lt on l.loan_doc_id = lt.loan_doc_id
),
loanMetrics as (
  select
    b.cust_id `cust_id`,
    count(l.loan_doc_id) `fa_count`,
    ifnull(sum(l.revenue),0) `cust_revenue`,
    sum(if(l.status = 'ongoing', 1, 0)) `cust_is_ongoing`,
    sum(if(l.status = 'overdue', 1, 0)) `cust_is_overdue`,
    if(count(l.loan_doc_id) < 5, 1, 0) `lt_5_fas`,
    if(count(l.loan_doc_id) between 5 and 9, 1, 0) `5_10_fas`,
    if(count(l.loan_doc_id) between 10 and 19, 1, 0) `10_20_fas`,
    if(count(l.loan_doc_id) between 20 and 39, 1, 0) `20_40_fas`,
    if(count(l.loan_doc_id) >= 40, 1, 0) `gt_40_fas`,
    max(date(disbursal_date)) `last_disbursed_date`,
    timestampdiff(month, max(b.reg_date), max(date(disbursal_date))) `months_with_flow`,
    ifnull(sum(l.revenue)/@exchange_rate,0) `cust_revenue_in_usd`,
    if(ifnull(sum(l.revenue),0)/@exchange_rate < 25, 1, 0) `rev_lt_25_usd`,
    if(ifnull(sum(l.revenue),0)/@exchange_rate between 25 and 50, 1, 0) `rev_25_50_usd`,
    if(ifnull(sum(l.revenue),0)/@exchange_rate > 50, 1, 0) `rev_gt_50_usd`
  from
    customers b
    left join loans_w_revenue l on l.cust_id = b.cust_id
  group by b.cust_id
)
  ,
summary1 as (
  select
    DATE_FORMAT(STR_TO_DATE(CONCAT(@reg_month, '01'), '%Y%m%d'),'%m/%Y') AS `Month`,
    if(@country_code = 'UGA', 'Uganda', 'Rwanda') `Country`,
    count(distinct b.cust_id) `Customers acquired`,
    timestampdiff(month, @reg_month_date, @report_date) `Months with Flow`,
    avg(`months_with_flow`) `Average months with Flow`,
    max(`months_with_flow`) `Max months with Flow`,
    min(`months_with_flow`) `Min months with Flow`,
    sum(`fa_count`) `Count of FAs till date`,
    sum(`cust_revenue`) `Total FA revenue till date`,
    sum(`cust_is_overdue`) `Customers with ongoing overdue`,
    sum(`cust_is_ongoing`) `Customers with ongoing FAs`,
    sum(`lt_5_fas`) `Customers with less than 5 FAs`,
    sum(`5_10_fas`) `Customers with 5-10 FAs`,
    sum(`10_20_fas`) `10-20 FAs`,
    sum(`20_40_fas`) `20-40 FAs`,
    sum(`gt_40_fas`) `>=40 FAs`,
    sum(`rev_lt_25_usd`) `Revenue generated - <=25 USD`,
    sum(`rev_25_50_usd`) `Revenue generated - 25 to 50 USD`,
    sum(`rev_gt_50_usd`) `Revenue generated - >50 USD`
  from
    loanMetrics l
    join customers b on b.cust_id = l.cust_id
),
final as (
  select
    `Month`,
    `Country`,
    `Customers acquired`,
    round(`Average months with Flow`, 2) `Average months with Flow`,
    `Max months with Flow`,
    `Min months with Flow`,
    `Months with Flow`,
    `Count of FAs till date`,
    `Total FA revenue till date`,
    round(`Total FA revenue till date`/`Customers acquired`, 2) `Average FA revenue/customer till date`,
    round(`Total FA revenue till date`/`Months with Flow`, 2) `Average FA revenue/month`,
    round(`Count of FAs till date`/`Months with Flow`/`Customers acquired`, 2) `Average FAs/month till date (per customer)`,
    `Customers with ongoing overdue`,
    round(`Customers with ongoing overdue`/`Customers acquired`, 4) `Overdue%`,
    `Customers with ongoing FAs`,
    round(`Customers with ongoing FAs`/`Customers acquired`, 4) `Ongoing%`,
    `Customers with less than 5 FAs`,
    round(`Customers with less than 5 FAs`/`Customers acquired`, 4) `Less than 5 FAs%`,
    `Customers with 5-10 FAs`,
    round(`Customers with 5-10 FAs`/`Customers acquired`, 4) `5-10 FAs%`,
    `10-20 FAs`,
    round(`10-20 FAs`/`Customers acquired`, 4) `10-20 FAs%`,
    `20-40 FAs`,
    round(`20-40 FAs`/`Customers acquired`, 4) `20-40 FAs%`,
    `>=40 FAs`,
    round(`>=40 FAs`/`Customers acquired`, 4) `>=40 FAs%`,
    `Revenue generated - <=25 USD`,
    round(`Revenue generated - <=25 USD`/`Customers acquired`, 4) `Less than 25 USD%`,
    `Revenue generated - 25 to 50 USD`,
    round(`Revenue generated - 25 to 50 USD`/`Customers acquired`, 4) `25 to 50 USD%`, 
    `Revenue generated - >50 USD`,
    round(`Revenue generated - >50 USD`/`Customers acquired`, 4) `Greater than 50 USD%`
  from
    summary1
)
select * from final;