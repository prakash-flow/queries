set @sub_lender_code = 'FSD2';
set @start_date = '2026-02-01';
set @end_date = '2026-02-28';

SELECT 
    p.national_id AS NIN, 
    CONCAT_WS(' ', p.first_name, p.middle_name, p.last_name) AS `Name of Borrower`, 
    p.email_id AS `Email address`, 
    'Self-employed' AS `Employment Status`,
    b.highest_education_lvl AS `Highest Education`, 
    p.mobile_num AS `Phone Number`, 
    l.loan_doc_id AS `Loan ID`, 
    l.cust_id AS `Borrower ID`,
    'Mobile Money' AS `Line of Business`,
    p.gender AS `Gender`, 
    l.loan_principal AS `Loan amount`,
    l.disbursal_date AS `Date of loan issue / disbursement`,
    l.due_date AS `Date of repayments commencement`, 
    l.duration AS `Tenure of loan`, 
    (SELECT product_code FROM loan_products WHERE id = l.product_id) AS `Loan product name`, 
    'Mobile Money Business Loan' AS `Loan product description`,
    'Individual' AS `Loan type`, 
    l.duration AS `Loan term value`,
    1 AS `Expected number of installments`,
    'Growing Mobile Money Business' AS `Loan Purpose`,

    (SELECT COUNT(id) 
     FROM loans  
     WHERE cust_id = b.cust_id 
       AND id <= (SELECT id FROM loans WHERE loan_doc_id = l.loan_doc_id) 
       AND status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
    ) AS `Loan cycle (For the PFI)`, 

    (SELECT COUNT(id) 
     FROM loans 
     WHERE cust_id = b.cust_id 
       AND sub_lender_code = @sub_lender_code 
       AND status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl') 
       AND id <= (SELECT id FROM loans WHERE loan_doc_id = l.loan_doc_id)
    ) AS `Loan Cycle fund specific`,

    l.flow_fee AS `Interest rate`, 
    (SELECT field_2 FROM address_info WHERE id = b.owner_address_id) AS `Location of borrower (District)`,
    
    IF(b.no_of_employees LIKE '0%', CAST(b.no_of_employees AS UNSIGNED), b.no_of_employees) AS `Number of employees`, 
    b.annual_revenue AS `Annual revenue of borrower (UGX)`, 

    -- Borrower's Date of Birth & Age
    p.dob AS `Date of birth`, 
    TIMESTAMPDIFF(YEAR, p.dob, CURDATE()) AS `Age`, 

    -- Length of time running the business
    CASE
        WHEN CONCAT(
            TIMESTAMPDIFF(YEAR, mob_money_agent_since, CURDATE()), ' years ',
            TIMESTAMPDIFF(MONTH, mob_money_agent_since, CURDATE()) % 12, ' months '
        ) = '0 years 0 months' 
        THEN CONCAT(
            TIMESTAMPDIFF(YEAR, mob_money_agent_since, CURDATE()), ' years ',
            TIMESTAMPDIFF(MONTH, mob_money_agent_since, CURDATE()) % 12, ' months ',
            DATEDIFF(CURDATE(), mob_money_agent_since), ' days'
        )
        ELSE CONCAT(
            TIMESTAMPDIFF(YEAR, mob_money_agent_since, CURDATE()), ' years ',
            TIMESTAMPDIFF(MONTH, mob_money_agent_since, CURDATE()) % 12, ' months '
        )
    END AS `Length of time running business`,

    b.person_w_disability AS `Is owner a person with Disability?`,
    1 AS `Monthly Installments`
    
FROM loans l
JOIN borrowers b ON l.cust_id = b.cust_id
JOIN persons p ON p.id = b.owner_person_id 

WHERE l.country_code = 'UGA' 
    AND DATE(l.disbursal_date) BETWEEN @start_date AND @end_date
    AND l.status NOT IN ('pending_disbursal', 'pending_mnl_dsbrsl', 'voided', 'hold') 
    AND l.sub_lender_code = @sub_lender_code

ORDER BY l.disbursal_date ASC;









