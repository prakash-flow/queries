    WITH CalculatedCommissions AS (
        SELECT 
            *,
            CASE 
                WHEN cr_amt + dr_amt <= 4 THEN 0
                -- 1. CASH-IN (Airtel Net Commission: 0.50% for all tiers) [cite: 2, 3]
                WHEN LOWER(txn_type) = 'cash_in' THEN 
                    (cr_amt + dr_amt) * 0.0050

                -- 2. CASH-OUT (Airtel Net Commission: Tiered) [cite: 4, 5]
                WHEN LOWER(txn_type) = 'cash_out' THEN
                    CASE 
                        -- Tiers A, B, C: 5.00k - 600.00k (1.00%) 
                        WHEN (cr_amt + dr_amt) <= 600.00 THEN (cr_amt + dr_amt) * 0.0100
                        
                        -- Tiers D, E: 600.01k - 3000.00k (Fixed 15) 
                        WHEN (cr_amt + dr_amt) <= 3000.00 THEN 15.00
                        
                        -- Tiers F, G, H: 3000.01k and above (Fixed 20) 
                        ELSE 20.00
                    END

                -- 3. OTHER TYPES (Fall back to existing commission column)
                ELSE comms 
            END AS calculated_comm
        FROM izwe_cust_acc_stmts
        WHERE acc_prvdr_code = 'ZATL'
        AND LOWER(txn_type) IN (
            'cash_in','cash_out'
        )
    )

    SELECT
        t.run_id AS `Run ID`,
        t.acc_number AS `Account Number`,
        t.txn_type AS `Txn Type`,
        COUNT(*) AS `Txn Count`,
        ROUND(SUM(t.calculated_comm), 2) AS `Commission`,
        ROUND(SUM(t.calculated_comm) / NULLIF(COUNT(*), 0), 2) AS `Comms Per Txn`,
        d.statement_duration AS `Statment Duration`,
        ROUND(SUM(t.cr_amt + t.dr_amt) / NULLIF(COUNT(*), 0), 2) AS `Amount Per Txn`,
        ROUND(COUNT(*) / NULLIF(d.statement_duration, 0), 2) AS `Txn Per Day`,
        ROUND(
            (COUNT(*) / NULLIF(d.statement_duration, 0)) * (SUM(t.cr_amt + t.dr_amt) / NULLIF(COUNT(*), 0)), 
            2
        ) AS `Float Used Per Day`,
        ROUND(
            SUM(
                CASE 
                    WHEN (t.cr_amt + t.dr_amt) != 0 
                    THEN (t.calculated_comm / (t.cr_amt + t.dr_amt)) * 100 
                END
            ), 2
        ) AS `ROI`,
        ROUND(
            AVG(
                CASE 
                    WHEN (t.cr_amt + t.dr_amt) != 0 
                    THEN (t.calculated_comm / (t.cr_amt + t.dr_amt)) * 100 
                END
            ), 2
        ) AS `Average ROI`
    FROM CalculatedCommissions t
    JOIN (
        SELECT 
            run_id,
            acc_number,
            DATEDIFF(MAX(txn_date), MIN(txn_date)) AS statement_duration
        FROM izwe_cust_acc_stmts
        WHERE acc_prvdr_code = 'ZATL'
        GROUP BY run_id, acc_number
    ) d 
    ON t.run_id = d.run_id 
    AND t.acc_number = d.acc_number
    GROUP BY t.run_id, t.acc_number, t.txn_type
    ORDER BY t.run_id, t.acc_number;



    WITH agg AS (
        SELECT 
            run_id,
            acc_number,
            SUM(comms) AS total_comms
        FROM izwe_cust_acc_stmts
        WHERE acc_prvdr_code = 'ZATL'
        GROUP BY run_id, acc_number
    ),

    ranked AS (
        SELECT *,
            ROW_NUMBER() OVER (
                PARTITION BY acc_number
                ORDER BY run_id DESC
            ) AS rn
        FROM agg
    )

    SELECT *
    FROM ranked
    WHERE rn = 1;