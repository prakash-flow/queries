set @month = "202503";
set @country_code = 'RWA';

set @last_day = (LAST_DAY(DATE(CONCAT(@month, "01"))));
  
with borrower as (
  select
    sum(if(a.field_2 in ('kampala'), 0, 1)) as rural_count,
    sum(if(p.gender in ('female', 'Female'), 1, 0)) as female_count,
    count(b.id) as total_customer
  from
    borrowers b
    left join persons p on p.id = b.owner_person_id
    left join address_info a on a.id = b.owner_address_id
  where
    reg_date <= @last_day
    and b.country_code = @country_code
),
metric as (
  select 
    total_customer,
    rural_count,
    female_count,
    (female_count / total_customer) * 100 as female_percent,
    (rural_count / total_customer) * 100 as rural_percent
  from borrower
)
select 'Total Borrowers' as `Borrower Demographics`, ROUND(total_customer) as `Value` from metric
union all
select 'Rural Borrower %', rural_percent from metric
union all
select 'Female Borrower %', female_percent from metric;