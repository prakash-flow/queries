SELECT
    COUNT(CASE WHEN status = 'approved' THEN 1 END) AS approved_count,
    COUNT(*) AS total_count,
    COUNT(CASE WHEN status = 'approved' THEN 1 END) / COUNT(*) AS approval_ratio
FROM loan_applications
WHERE country_code = 'UGA'
  AND status <> 'voided'
  AND EXTRACT(YEAR_MONTH FROM loan_appl_date) BETWEEN 202507 AND 202512;


-- https://docs.google.com/spreadsheets/d/1-S5ZvRrwj_2821NJW19wee_cSwuyqoyk/edit?usp=sharing&ouid=105568563141825877596&rtpof=true&sd=true