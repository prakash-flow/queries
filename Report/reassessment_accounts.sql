DROP TABLE IF EXISTS reassessment_accounts;
CREATE TABLE IF NOT EXISTS reassessment_accounts (
  	month VARCHAR(6),
    account_id BIGINT,
    cust_id VARCHAR(50),
    acc_number VARCHAR(50),
  	alt_acc_num VARCHAR(50),
    acc_prvdr_code VARCHAR(4),
    is_primary_acc TINYINT,
    cust_score_factors JSON,
  	monthly_comms BIGINT,
    acc_ownership VARCHAR(50),
    conditions JSON,
  	`limit` BIGINT,
    -- Unique constraint
    UNIQUE KEY uniq_account_cust (month, account_id, cust_id),
    -- Indexes
    INDEX idx_cust_id (cust_id),
    INDEX idx_acc_number (acc_number),
    INDEX idx_alt_acc_number (alt_acc_num)
);


set @month = '202501';
set @last_day = (LAST_DAY(DATE(CONCAT(@month, "01"))));
set @country_code = 'UGA';

INSERT INTO reassessment_accounts (
  	month,
    account_id,
    cust_id,
    acc_number,
  	alt_acc_num,
    acc_prvdr_code,
    is_primary_acc,
    cust_score_factors,
  	monthly_comms,
    acc_ownership,
    conditions,
  	`limit`
)
WITH active_cust AS (
    SELECT DISTINCT
        l.cust_id AS cust_id
    FROM loans l
    JOIN loan_txns t ON l.loan_doc_id = t.loan_doc_id
    LEFT JOIN (
        SELECT DISTINCT
            r1.record_code
        FROM record_audits r1
        JOIN (
            SELECT
                record_code,
                MAX(id) AS id
            FROM record_audits
            WHERE DATE(created_at) <= @last_day
            GROUP BY record_code
        ) r2 ON r1.id = r2.id
        WHERE JSON_EXTRACT(r1.data_after, '$.status') = 'disabled'
    ) disabled_cust ON l.cust_id = disabled_cust.record_code
    WHERE
        DATEDIFF(@last_day, t.txn_date) <= 30
        AND DATE(t.txn_date) <= @last_day
        AND l.country_code = @country_code
        AND l.loan_purpose = 'float_advance'
        AND t.txn_type = 'disbursal'
        AND l.product_id NOT IN (43, 75, 300)
        AND l.status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
        AND disabled_cust.record_code IS NULL
  HAVING 
    cust_id IN (SELECT cust_id FROM accounts WHERE status = 'enabled' AND acc_prvdr_code = 'UMTN' AND DATE(created_at) <= @last_day)
)
SELECT 
    @month,
    a.id AS account_id,
    a.cust_id,
    a.acc_number,
    a.alt_acc_num,
    a.acc_prvdr_code,
    a.is_primary_acc,
    COALESCE(a.cust_score_factors, JSON_ARRAY()),
    IFNULL(jt.g_val, 0),
    a.acc_ownership,
    COALESCE(a.conditions, JSON_ARRAY()),
    IFNULL(MAX(limits.`limit`), 0)
FROM accounts a
JOIN active_cust e ON a.cust_id = e.cust_id
LEFT JOIN JSON_TABLE(
    a.cust_score_factors,
    "$[*]" COLUMNS (
        csf_type VARCHAR(50) PATH "$.csf_type",
        g_val BIGINT PATH "$.g_val"
    )
) AS jt ON jt.csf_type = 'monthly_comms'
LEFT JOIN JSON_TABLE(
    a.conditions,
    "$[*]" COLUMNS (
        type VARCHAR(50) PATH "$.type",
        `limit` BIGINT PATH "$.limit"
    )
) AS limits ON 1
WHERE a.is_removed = 0 AND a.status = 'enabled'
GROUP BY 
    a.id, a.cust_id, a.acc_number, a.alt_acc_num, a.acc_prvdr_code, 
    a.is_primary_acc, a.cust_score_factors, a.acc_ownership, a.conditions, jt.g_val;