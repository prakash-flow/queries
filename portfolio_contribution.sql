set @month = '202412';
set @country_code = 'RWA'

with
    custInMonth as (
      select distinct
        cust_id
      from
        loans l
      where
        l.country_code = @country_code
        and extract(
          year_month
          from
            disbursal_date
        ) = @month
        and product_id not in(
          select
            id
          from
            loan_products
          where
            product_type = 'float_vending'
        )
        and status not in(
          'voided',
          'hold',
          'pending_disbursal',
          'pending_mnl_dsbrsl'
        )
    ),
    loansWithPrevious as (
      select
        l.cust_id,
        l.loan_doc_id,
        extract(
          year_month
          from
            l.disbursal_date
        ) disbursal_month,
        l.loan_principal `current_loan_principal`,
        lag(l.loan_principal) over (
          partition by
            l.cust_id
          order by
            l.disbursal_date
        ) AS previous_loan_principal,
        l.disbursal_date,
        IF(TIMESTAMPDIFF(YEAR, p.dob, curdate()) < 35, 'youth', 'elder') `age`,
        p.gender,
        l.lender_code,
        l.sub_lender_code
      from
        loans l 
      join custInMonth b on l.cust_id = b.cust_id
      left join borrowers bo on bo.cust_id = b.cust_id
      left join persons p on p.id = bo.owner_person_id
      where
        l.country_code = @country_code
        and extract(
          year_month
          from
            disbursal_date
        ) <= @month
        and product_id not in(
          select
            id
          from
            loan_products
          where
            product_type = 'float_vending'
        )
        and l.status not in(
          'voided',
          'hold',
          'pending_disbursal',
          'pending_mnl_dsbrsl'
        )
    ),
    loansLabelled as (
      select
        l.cust_id,
        l.loan_doc_id,
        l.disbursal_date,
        l.disbursal_month,
        l.current_loan_principal,
        l.previous_loan_principal,
        gender,
        age,
        lender_code,
        sub_lender_code,
        (
          l.current_loan_principal - ifnull(l.previous_loan_principal, 0)
        ) `change_in_loan_principal`,
        case
          when previous_loan_principal is null then 'new'
          when current_loan_principal = previous_loan_principal then 'repeat'
          when current_loan_principal > previous_loan_principal then 'upgrade'
          when current_loan_principal < previous_loan_principal then 'downgrade'
          else 'unknown'
        end `loan_label`
      from
        loansWithPrevious l
      where
        disbursal_month = @month
      order by
        l.disbursal_date
    ),
    newCustomersRaw AS (
      select
        disbursal_month,
        cust_id,
        avg(current_loan_principal) average
      from
        loansLabelled
      where
        cust_id in (
          select distinct
            cust_id
          from
            loansLabelled
          where
            loan_label = 'new'
        )
      group by
        cust_id, disbursal_month, age, gender, lender_code, sub_lender_code
    ),
    newCustomers AS (
      select
        disbursal_month,
        sum(average) new_customers
      from
        newCustomersRaw
      group by
        disbursal_month
    ),
    loanOrder AS (
      select
        *,
        ROW_NUMBER() OVER (
          PARTITION BY
            cust_id,
            loan_label
          ORDER BY
            disbursal_date
        ) rn
      from
        loansLabelled
    ),
    upgradeCustomers AS (
      select
        disbursal_month,
        sum(
          if(
            loan_label = 'upgrade'
            and rn = 1,
            change_in_loan_principal,
            0
          )
        ) upgrade_customers,
        count(
          if(
            loan_label = 'upgrade'
            and rn = 1,
            change_in_loan_principal,
            null
          )
        ) upgrades_count
      from
        loanOrder
      where
      cust_id not in (
          select distinct
            cust_id
          from
            loansLabelled
          where
            loan_label = 'new'
        )
      group by
        disbursal_month
    ),
    existUpgradeCount as (
      select
        disbursal_month,
        count(if(
            loan_label = 'upgrade'
            and rn = 1,
            change_in_loan_principal,
            null
          )) existing_upgrade_count
      from
        loanOrder
      where
        cust_id not in (
          select distinct
            cust_id
          from
            loansLabelled
          where
            loan_label = 'new'
        )
      group by disbursal_month
    )
  select
    u.disbursal_month,
    ROUND(new_customers, 2) new_customers,
    upgrades_count,
    upgrade_customers existing_customer_upgrade,	
    ROUND(upgrade_customers / new_customers * 100, 2) growth
  from
    upgradeCustomers u
    join newCustomers n on u.disbursal_month = n.disbursal_month
    join existUpgradeCount e on e.disbursal_month = u.disbursal_month;