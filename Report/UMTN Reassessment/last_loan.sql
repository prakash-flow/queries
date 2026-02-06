SELECT
    l.cust_id,
    l.disbursal_date AS last_disbursal_date,
    l.loan_principal AS last_loan_principal
FROM loans l
JOIN (
    SELECT
        cust_id,
        MAX(disbursal_date) AS last_disbursal_date
    FROM loans
    WHERE cust_id IN (
        SELECT DISTINCT cust_id
        FROM accounts
        WHERE acc_prvdr_code='UMTN'
          AND status='enabled'
          AND is_removed=0
    )
    GROUP BY cust_id
) x
  ON x.cust_id = l.cust_id
 AND x.last_disbursal_date = l.disbursal_date
WHERE l.status NOT IN ('voided', 'hold', 'pending_disbursal','pending_mnl_dsbrsl')
    AND loan_purpose not in ('asset_financing', 'growth_financing');