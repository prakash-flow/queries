SELECT
    IF(loan_purpose = 'growth_financing', 'Kula Plus', 'Kula Asset') AS product_name,
    loan_principal,
    flow_fee,
    30 * duration
FROM loans
WHERE country_code = 'UGA'
  AND loan_purpose IN ('growth_financing', 'asset_financing')
GROUP BY
    loan_purpose,
    loan_principal,
    flow_fee,
    duration
ORDER by
    loan_purpose,
    loan_principal,
    flow_fee,
    duration;


select loan_purpose, max_loan_amount, flow_fee, duration from loan_products where country_code = 'UGA' and status = 'enabled' and product_type not in ('probation', 'referral') group by loan_purpose, max_loan_amount, flow_fee, duration order by loan_purpose, max_loan_amount, flow_fee, duration;
