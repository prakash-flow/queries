-- Update distributor_code in accounts using cust_commissions
DB::update("
    UPDATE accounts a
    JOIN cust_commissions cc
        ON cc.identifier = a.acc_number
        AND cc.acc_prvdr_code = a.acc_prvdr_code
        AND cc.country_code = a.country_code
    SET a.distributor_code = cc.distributor_code
    WHERE cc.month = '202512' AND cc.country_code = 'RWA' AND a.country_code = 'RWA'
");

-- Update parent_acc_id in accounts
DB::update("
    UPDATE accounts child
    JOIN accounts parent 
        ON parent.distributor_code = child.distributor_code
        AND parent.cust_id IS NULL
        AND parent.distributor_code IS NOT NULL
        AND parent.to_recon = 1
        AND parent.status = 'enabled'
        AND parent.country_code = child.country_code 
    SET child.parent_acc_id = parent.id
    WHERE child.cust_id IS NOT NULL AND parent.country_code = 'RWA' AND child.country_code = 'RWA'
");

-- Update parent_acc_id to null in accounts
DB::update("
    UPDATE accounts SET parent_acc_id = NULL 
    WHERE distributor_code NOT IN (
        SELECT distributor_code 
        FROM accounts 
        WHERE country_code = 'RWA' 
        AND status = 'enabled' 
        AND distributor_code IS NOT NULL 
        AND to_recon = 1 
        AND cust_id IS NULL
    ) AND cust_id IS NOT NULL AND country_code = 'RWA' AND parent_acc_id IS NOT NULL
")

-- Update distributor_code in borrowers using accounts
DB::update("
    UPDATE borrowers b
    JOIN accounts a 
        ON b.cust_id = a.cust_id
        AND b.acc_number = a.acc_number
        AND b.country_code = a.country_code
    SET b.distributor_code = a.distributor_code
    WHERE b.country_code = 'RWA' AND a.country_code = 'RWA'
");

-- Update last_assessment_date in borrowers using accounts
DB::update("
    UPDATE borrowers b
    JOIN (
        SELECT 
            cust_id,
            MAX(last_assessment_date) AS max_assessment_date
        FROM accounts
        WHERE is_removed = 0
          AND last_assessment_date IS NOT NULL
        GROUP BY cust_id
    ) a ON a.cust_id = b.cust_id
    SET b.last_assessment_date = a.max_assessment_date
    WHERE b.last_assessment_date IS NULL
");