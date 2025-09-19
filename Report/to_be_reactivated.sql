  SET @month = '202509';
  SET @country_code = 'UGA';

  SET @last_day = LAST_DAY(DATE(CONCAT(@month, '01')));
  SET @last_day = LEAST(@last_day, CURDATE());

  WITH recentReassignments AS (
      SELECT *
      FROM (
          SELECT
              cust_id,
              from_rm_id,
              rm_id,
              reason_for_reassign,
              DATE(from_date) AS from_date,
              ROW_NUMBER() OVER (
                  PARTITION BY cust_id
                  ORDER BY from_date DESC
              ) rn
          FROM rm_cust_assignments rm_cust
          WHERE rm_cust.country_code = @country_code
            AND rm_cust.reason_for_reassign NOT IN ('initial_assignment')
            AND DATE(rm_cust.from_date) <= @last_day
      ) t
      WHERE rn = 1
  ),

  latest_txn AS (
      SELECT 
          l.cust_id,
          MAX(t.txn_date) AS last_txn_date
      FROM loans l
      JOIN loan_txns t ON l.loan_doc_id = t.loan_doc_id
      WHERE DATE(t.txn_date) <= @last_day
        AND l.country_code = @country_code
        AND t.txn_type = 'disbursal'
        AND l.product_id NOT IN (43, 75, 300)
        AND l.status NOT IN ('voided','hold','pending_disbursal','pending_mnl_dsbrsl')
      GROUP BY l.cust_id
  ),

  customers_with_rm AS (
      SELECT
          COALESCE(r.from_rm_id, l.flow_rel_mgr_id) AS rm_id,
          lt.cust_id,
          lt.last_txn_date,
          DATEDIFF(@last_day, lt.last_txn_date) AS day_since_last_loan,
          l.loan_principal,
          l.flow_fee,
          l.cust_name,
          l.flow_rel_mgr_name,
          l.cust_mobile_num
      FROM latest_txn lt
      JOIN loans l ON lt.cust_id = l.cust_id
      JOIN loan_txns t ON l.loan_doc_id = t.loan_doc_id
                       AND t.txn_date = lt.last_txn_date  
      LEFT JOIN recentReassignments r ON r.cust_id = l.cust_id
      WHERE DATEDIFF(@last_day, lt.last_txn_date) > 30
  ),

  address AS (
      SELECT 
          c.*, 
          a.field_1 AS region, 
          a.field_2 AS district,
          b.reg_date
      FROM customers_with_rm c
      JOIN borrowers b ON b.cust_id = c.cust_id
      LEFT JOIN address_info a ON a.id = b.owner_address_id
  ),

  assessment_dates AS (
      SELECT
          cust_id,
          DATE(MIN(last_assessment_date)) AS min_assessment_date,
          DATE(MAX(last_assessment_date)) AS max_assessment_date
      FROM accounts
      WHERE status = 'enabled' 
        AND is_removed = 0
        AND cust_id IN (SELECT cust_id FROM address)
      GROUP BY cust_id
  ),

  primary_account_cte AS (
      SELECT
        a.cust_id,
        SUBSTRING_INDEX(
          GROUP_CONCAT(
            a.acc_prvdr_code
            ORDER BY
              a.is_primary_acc DESC,
              a.id ASC
          ),
          ',',
          1
        ) AS primary_acc_prvdr_code,
        SUBSTRING_INDEX(
          GROUP_CONCAT(
            a.acc_number
            ORDER BY
              a.is_primary_acc DESC,
              a.id ASC
          ),
          ',',
          1
        ) AS primary_acc_number,
        SUBSTRING_INDEX(
          GROUP_CONCAT(
            a.alt_acc_num
            ORDER BY
              a.is_primary_acc DESC,
              a.id ASC
          ),
          ',',
          1
        ) AS primary_alt_acc_num,
        SUBSTRING_INDEX(
          GROUP_CONCAT(
            a.acc_ownership
            ORDER BY
              a.is_primary_acc DESC,
              a.id ASC
          ),
          ',',
          1
        ) AS primary_acc_ownership,
        SUBSTRING_INDEX(
          GROUP_CONCAT(
            a.is_primary_acc
            ORDER BY
              a.is_primary_acc DESC,
              a.id ASC
          ),
          ',',
          1
        ) AS is_primary_acc,
        SUBSTRING_INDEX(
          GROUP_CONCAT(
            a.id
            ORDER BY
              a.is_primary_acc DESC,
              a.id ASC
          ),
          ',',
          1
        ) AS primary_account_id
      FROM
        accounts a WHERE cust_id IN (SELECT cust_id FROM address)  AND is_removed = 0 AND status = 'enabled'
      GROUP BY
        a.cust_id
    ),

  account_limits AS (
      SELECT
          fa.cust_id,
          MAX(CAST(JSON_UNQUOTE(JSON_EXTRACT(j.value, '$.limit')) AS UNSIGNED)) AS eligibility,
          FLOOR(MAX(CAST(JSON_UNQUOTE(JSON_EXTRACT(j.value, '$.limit')) AS UNSIGNED)) * 0.5) AS eligibility_50_raw,
          CASE
              WHEN FLOOR(MAX(CAST(JSON_UNQUOTE(JSON_EXTRACT(j.value, '$.limit')) AS UNSIGNED)) * 0.5) >= 5000000 THEN 5000000
              WHEN FLOOR(MAX(CAST(JSON_UNQUOTE(JSON_EXTRACT(j.value, '$.limit')) AS UNSIGNED)) * 0.5) >= 4000000 THEN 4000000
              WHEN FLOOR(MAX(CAST(JSON_UNQUOTE(JSON_EXTRACT(j.value, '$.limit')) AS UNSIGNED)) * 0.5) >= 3000000 THEN 3000000
              WHEN FLOOR(MAX(CAST(JSON_UNQUOTE(JSON_EXTRACT(j.value, '$.limit')) AS UNSIGNED)) * 0.5) >= 2500000 THEN 2500000
              WHEN FLOOR(MAX(CAST(JSON_UNQUOTE(JSON_EXTRACT(j.value, '$.limit')) AS UNSIGNED)) * 0.5) >= 2000000 THEN 2000000
              WHEN FLOOR(MAX(CAST(JSON_UNQUOTE(JSON_EXTRACT(j.value, '$.limit')) AS UNSIGNED)) * 0.5) >= 1500000 THEN 1500000
              WHEN FLOOR(MAX(CAST(JSON_UNQUOTE(JSON_EXTRACT(j.value, '$.limit')) AS UNSIGNED)) * 0.5) >= 1000000 THEN 1000000
              WHEN FLOOR(MAX(CAST(JSON_UNQUOTE(JSON_EXTRACT(j.value, '$.limit')) AS UNSIGNED)) * 0.5) >= 750000 THEN 750000
              WHEN FLOOR(MAX(CAST(JSON_UNQUOTE(JSON_EXTRACT(j.value, '$.limit')) AS UNSIGNED)) * 0.5) >= 500000 THEN 500000
              WHEN FLOOR(MAX(CAST(JSON_UNQUOTE(JSON_EXTRACT(j.value, '$.limit')) AS UNSIGNED)) * 0.5) >= 250000 THEN 250000
              ELSE 0
          END AS eligibility_50_tier
      FROM accounts fa
      CROSS JOIN JSON_TABLE(fa.conditions, '$[*]' COLUMNS (value JSON PATH '$')) j
      WHERE JSON_UNQUOTE(JSON_EXTRACT(j.value, '$.type')) IN ('commission_based_limits', 'statement_based_limits')
      GROUP BY fa.cust_id
  ),

  ontime_repayment AS (
      SELECT
        l.cust_id,
        ROUND(
          100 * SUM(CASE WHEN t.max_txn_date <= DATE_ADD(l.due_date, INTERVAL 1 DAY) THEN 1 ELSE 0 END) 
          / COUNT(l.loan_doc_id), 2
        ) AS ontime_repayment_rate,
        SUM(CASE WHEN t.max_txn_date <= DATE_ADD(l.due_date, INTERVAL 1 DAY) THEN 1 ELSE 0 END) AS ontime_settle_count,
        COUNT(l.loan_doc_id) total_loan_taken
      FROM loans l
      JOIN (
          SELECT loan_doc_id, MAX(txn_date) AS max_txn_date
          FROM loan_txns
          WHERE txn_type = 'payment'
          GROUP BY loan_doc_id
      ) t ON l.loan_doc_id = t.loan_doc_id
      WHERE l.status = 'settled'
        AND DATE(l.paid_date) <= @last_day
        AND l.product_id NOT IN (43, 75, 300)
        AND l.status NOT IN ('voided','hold','pending_disbursal','pending_mnl_dsbrsl')
        AND l.country_code = @country_code
      GROUP BY l.cust_id
  ),

  final_table AS (
      SELECT DISTINCT
          adr.*,
          primary_acc_number,
          primary_alt_acc_num,
          primary_acc_ownership,
          primary_acc_prvdr_code,
          primary_account_id,
          ad.min_assessment_date,
          ad.max_assessment_date,
          al.eligibility,
          al.eligibility_50_raw,
          al.eligibility_50_tier,
          DATEDIFF(@last_day, ad.max_assessment_date) AS day_since_last_assessment,
          CASE
              WHEN primary_acc_ownership = 'rented' OR primary_acc_prvdr_code = 'UEZM' THEN FALSE
              WHEN ad.max_assessment_date IS NOT NULL AND DATEDIFF(@last_day, ad.max_assessment_date) <= 90 THEN TRUE
              ELSE FALSE
          END AS can_reactivate,
          IFNULL(ot.ontime_repayment_rate, 0) ontime_repayment_rate,
          ot.ontime_settle_count,
          ot.total_loan_taken
      FROM address adr
      LEFT JOIN primary_account_cte pa ON adr.cust_id = pa.cust_id
      LEFT JOIN assessment_dates ad ON adr.cust_id = ad.cust_id
      LEFT JOIN account_limits al ON adr.cust_id = al.cust_id
      LEFT JOIN ontime_repayment ot ON adr.cust_id = ot.cust_id
  )

  SELECT 
      cust_id AS `Customer ID`,
      reg_date AS `Registration Date`,
      DATE(last_txn_date) AS `Inactive Since`,
      day_since_last_loan AS `Days Since Last Loan`,
      total_loan_taken AS `Total Loans Taken`,
      ontime_settle_count AS `Ontime Paid Loans`,
      ontime_repayment_rate AS `On-Time Repayment Rate`,
      loan_principal AS `Last Loan Amount`,
      flow_fee AS `Last Loan Fee`,
      eligibility AS `Eligibility`,
      min_assessment_date AS `Min Assessment Date`,
      max_assessment_date AS `Max Assessment Date`,
      flow_rel_mgr_name AS `RM Name`,
      cust_name AS `Customer Name`,
      cust_mobile_num AS `Customer Mobile Number`,
      region AS `Region`,
      district AS `District`,
      primary_acc_ownership AS `Account Ownership`,
      primary_acc_number AS `Primary Account Number`,
      primary_alt_acc_num AS `Primary Alt Account Number`,
      primary_acc_prvdr_code AS `Primary Account Provide Code`,
      primary_account_id AS `Primary Account ID`,
      can_reactivate AS `Eligible For Reactivation`
  FROM final_table
  HAVING `Eligibility` > 0;