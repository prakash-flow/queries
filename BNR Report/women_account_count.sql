set @month = '202412';
set @country_code = 'RWA';

set @last_day = (LAST_DAY(DATE(CONCAT(@month, "01"))));;

select @last_day, @country_code;

select 
  count(cust_id), 
  gender 
from 
  borrowers b, 
  persons p 
where 
  b.owner_person_id = p.id 
  and reg_date <= @last_day 
  and b.country_code = @country_code 
group by 
  gender;