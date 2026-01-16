WITH loan_rates AS (
    SELECT 
        loan_principal,
        CASE 
            WHEN IFNULL(duration_unit,'day') = 'day' 
                THEN (flow_fee / loan_principal) * (365 / duration) * 100
            WHEN IFNULL(duration_unit,'day') = 'month' 
                THEN (flow_fee / loan_principal) * (12 / duration) * 100
            WHEN IFNULL(duration_unit,'day') = 'year' 
                THEN (flow_fee / loan_principal) * (1 / duration) * 100
        END AS interest_rate_pa
    FROM loans
    WHERE EXTRACT(YEAR_MONTH FROM disbursal_date) BETWEEN '202507' AND '202512'
      AND country_code = 'UGA' AND loan_doc_id NOT IN (
      select 
      	loan_doc_id
      from 
      	loan_write_off 
      where country_code = @country_code and write_off_date <= @last_day and loan_doc_id NOT IN ('UFLW-83346-1282256')
      and write_off_status in ('approved','partially_recovered','recovered')
    )
)

SELECT 
    ROUND(
        SUM(loan_principal * interest_rate_pa) / SUM(loan_principal),
        2
    ) AS weighted_avg_interest_rate_percent
FROM loan_rates;


-- Schedule 3_UPS_FLOW_KPI and Impact Reporting_25H2
-- https://docs.google.com/spreadsheets/d/1-S5ZvRrwj_2821NJW19wee_cSwuyqoyk/edit?usp=sharing&ouid=105568563141825877596&rtpof=true&sd=true