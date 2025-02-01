set @country_code = 'RWA';
set @start_month = '202401';
set @end_month = '202412';

select @country_code, @start_month, @end_month;

select 
  count(id) loan_applied, 
  count(if(status = 'rejected', 1, null)) loan_rejected, 
  sum(loan_principal) loan_value, 
	sum(if(status = 'rejected', loan_principal, 0)) rejected_value 
from 
	loan_applications 
where 
	country_code = @country_code
	and extract(year_month from loan_appl_date) between @start_month and @end_month;