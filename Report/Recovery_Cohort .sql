select l.country_code , YEARWEEK(disbursal_date, 4) as disbursal_week , sum(if((yearweek(txn_date, 4) between 202544 and 202622) and txn_type= 'disbursal', amount,0)) amount_disbursed, 
  
  					sum(if(datediff(t.txn_date, due_date) <=0 ,if((t.txn_type = 'payment' and t.principal > 0), principal, 0),0)) paid_on_time ,
  
                    sum(if(datediff(t.txn_date, due_date) between 1 and 5 ,if((t.txn_type = 'payment' and t.principal > 0), principal, 0),0)) paid_between_1_and_5,
                    sum(if(datediff(t.txn_date, due_date) between 6 and 30 ,if((t.txn_type = 'payment' and t.principal > 0), principal, 0),0)) paid_between_6_and_30,
                    sum(if(datediff(t.txn_date, due_date) > 30 ,if((t.txn_type = 'payment' and t.principal > 0), principal, 0),0)) paid_30_after_late,
                    sum(if(datediff(t.txn_date, due_date) = 30 ,if((t.txn_type = 'payment' and t.principal > 0), principal, 0),0)) paid_after_due_date 
                    
  
  					  
  					 from loans l ,loan_txns t where l.loan_doc_id = t.loan_doc_id and (yearweek(disbursal_date, 4) between 202544 and 202622) and l.loan_doc_id not in (select loan_doc_id from loan_write_off where type = 'fraud') 
    and l.country_code = 'RWA'  and l.product_id not in ('43','75','300')   and l.status not in ('voided','hold','pending_disbursal','pending_mnl_dsbrsl')  
    and l.loan_purpose in ('adj_float_advance') 
    group by l.country_code, YEARWEEK(disbursal_date, 4)  order by YEARWEEK(disbursal_date, 4)









