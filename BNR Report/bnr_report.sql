set @report_date = '2024-12-31';
set @month = '202412';
set @country_code = 'RWA';

set @last_day = (LAST_DAY(DATE(CONCAT(@month, "01"))));
set @realization_date = (select closure_date from closure_date_records where country_code = @country_code and month = @month and status = 'enabled');

# Watch
set @having_condition = "between 1 and 89";

# Substandard
set @having_condition = "between 90 and 179";

# Doubtful
set @having_condition = "between 180 and 359";

# Loss
set @having_condition = "between 360 and 719";

select @last_day, @realization_date, @country_code, @month, @report_date, @having_condition;

set @query = CONCAT("select cust_name, cust_id, cust_mobile_num, gender, age, 'Customer' relationship, '' martial_status, is_ontime_repaid, 'Growing Mobile Money Business' purpose_of_loan, '' branch_name, '' collateral_type, '' collateral_amt, field_2 district, field_3 sector, field_4 cell, field_5 village, '' annual_interest, 'Flat' interest_rate, flow_rel_mgr_name, principal, disbursal_date, due_date, '' empty1, '' empty2, '' empty3, '' empty4, DATE_ADD(due_date, interval 1 day) arrear_start, @last_day report_date, '' empty5, '' empty6, '' empty7, partial_pay, par_loan_principal, '' empty8, par_loan_principal net_principal, od_days from ( select sum( IF( principal - IFNULL(partial_pay, 0) < 0, 0, principal - IFNULL(partial_pay, 0) ) ) par_loan_principal, TIMESTAMPDIFF( YEAR, max(dob), @last_day ) age, pri.loan_doc_id, pri.cust_id, pri.cust_name, pri.cust_mobile_num, pri.acc_prvdr_code, pri.acc_number, pri.flow_rel_mgr_name, pri.principal, pri.fee, pri.disbursal_date, pri.due_date, if( datediff(@last_day, due_date)< 0, 0, datediff(@last_day, due_date) ) as od_days, pri.status, pri.paid_date, max(pri.gender) as gender, sum(partial_pay) partial_pay, max(field_2) field_2, max(field_3) field_3, max(field_4) field_4, max(field_5) field_5, is_ontime_repaid from ( select l.loan_doc_id, loan_principal principal, l.cust_id, l.flow_fee as fee, l.acc_prvdr_code, l.cust_name, l.cust_mobile_num, l.flow_rel_mgr_name, l.product_name, l.disbursal_date, l.due_date, l.overdue_days, l.acc_number, l.status, l.paid_date, p.gender, p.dob, field_2, field_3, field_4, field_5 from loans l, loan_txns lt, borrowers b, persons p, address_info a where lt.loan_doc_id = l.loan_doc_id and b.cust_id = l.cust_id and p.id = b.owner_person_id and b.owner_address_id = a.id and lt.txn_type in ('disbursal') and realization_date <= @realization_date and l.country_code = @country_code and date(disbursal_date) <= @last_day and product_id not in (43, 75, 300) and l.status not in ( 'voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl' ) and l.loan_doc_id not in ( select loan_doc_id from loan_write_off where l.country_code = @country_code and date(write_off_date) <= @last_day and write_off_status in ( 'approved', 'partially_recovered', 'recovered' ) ) ) pri left join ( select l.loan_doc_id, sum(principal) partial_pay from loans l join loan_txns t ON l.loan_doc_id = t.loan_doc_id where l.country_code = @country_code and date(disbursal_Date) <= @last_day and product_id not in (43, 75, 300) and realization_date <= @realization_date and date(txn_date) <= @last_day and txn_type = 'payment' and l.status not in ( 'voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl' ) and l.loan_doc_id not in ( select loan_doc_id from loan_write_off where l.country_code = @country_code and date(write_off_date) <= @last_day and write_off_status in ( 'approved', 'partially_recovered', 'recovered' ) ) group by l.loan_doc_id ) pp on pri.loan_doc_id = pp.loan_doc_id join ( select current_due_date, loan_doc_id, loan, case when due_date is null and paid_date is null then 'yes' when datediff(paid_date, due_date) = 0 then 'yes' else 'no' end is_ontime_repaid from ( select due_date current_due_date, l.loan_doc_id, cust_id, LAG(l.loan_doc_id) OVER ( PARTITION BY cust_id ORDER BY disbursal_date ) loan, LAG(due_date) OVER ( PARTITION BY cust_id ORDER BY disbursal_date ) due_date, LAG(paid_date) OVER ( PARTITION BY cust_id ORDER BY disbursal_date ) paid_date from loans l, loan_txns lt where lt.loan_doc_id = l.loan_doc_id and lt.txn_type in ('disbursal') and realization_date <= @realization_date and l.country_code = @country_code and date(disbursal_date) <= @last_day and product_id not in (43, 75, 300) and l.status not in ( 'voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl' ) ) t having datediff(@last_day, current_due_date) ", 
                    @having_condition
                    , " ) pl on pl.loan_doc_id = pri.loan_doc_id group by pri.loan_doc_id having od_days ", 
                    @having_condition, " and par_loan_principal > 0 ) t");

select @query;
  
PREPARE stmt FROM @query;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;