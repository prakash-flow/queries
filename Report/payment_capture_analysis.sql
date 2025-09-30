WITH payments AS (
  SELECT
    COALESCE(lt.txn_exec_by, 0) AS txn_exec_by,
    ac.created_at AS import_time,
    lt.created_at AS captured_time, 
    SUBSTRING_INDEX(lt.loan_doc_id, '-', 2) AS cust_id,
    CASE 
    WHEN ac.account_id = 34119 THEN 'phonecom_nyarugenge'
    WHEN ac.account_id = 34120 THEN 'phonecom_south'
    WHEN ac.account_id = 40795 THEN 'ets_bart_musanze'
    WHEN ac.account_id = 40796 THEN 'ets_bart_gicumbi'
    WHEN ac.account_id = 8285 THEN 'airtel'
    WHEN ac.account_id = 4182 THEN 'bk'
    WHEN ac.account_id in (9192,16919) THEN 'merchant' ELSE 'unknown' END `repayment_line`,
    ac.acc_number as repayment_number,
    lt.txn_id,
    lt.txn_date,
    ac.loan_doc_id,
    ac.descr,
    SUBSTRING_INDEX(ac.descr, '/', -1) AS recon_descr,
    ac.acc_prvdr_code,
    ac.recon_desc,
    ac.ref_account_num,
    ac.ref_alt_acc_num,
    COALESCE(ac.cr_amt, ac.amount) AS amount,
    lt.to_ac_id
  FROM loan_txns lt
  JOIN account_stmts ac 
    ON ac.stmt_txn_id = lt.txn_id 
    AND lt.txn_type = 'payment'
  WHERE
    YEAR(lt.txn_date) = 2025
    AND ac.country_code = 'RWA'
    AND lt.to_ac_id IN (
      SELECT id
      FROM accounts
      WHERE acc_prvdr_code = 'RMTN'
        AND cust_id IS NULL
        AND status = 'enabled'
    )
),
with_account_check AS (
  SELECT
    p.*,
    CASE 
      WHEN a.id IS NULL THEN 0 
      ELSE 1 
    END AS account_exists
  FROM payments p
  LEFT JOIN accounts a 
    ON a.acc_number = SUBSTRING(p.ref_account_num, 4) 
    AND a.created_at >= p.txn_date
),
with_person_matches AS (
  SELECT
    wac.*,
    COALESCE(pm.person_matches, '[]') AS person_matches,
    COALESCE(pm.no_of_person_match, 0) AS no_of_person_match,
    CASE 
      WHEN COALESCE(pm.no_of_person_match, 0) = 1 THEN 1 
      ELSE 0 
    END AS name_match
  FROM with_account_check wac
  LEFT JOIN (
    SELECT
      p.txn_id,
      CONCAT(
        '[',
        GROUP_CONCAT(
          CONCAT(
            '{"id":', per.id,
            ',"first_name":"', per.first_name,
            '","last_name":"', per.last_name, '"}'
          ) SEPARATOR ','
        ),
        ']'
      ) AS person_matches,
      COUNT(per.id) AS no_of_person_match
    FROM payments p
    LEFT JOIN persons per
      ON per.country_code = 'RWA'
      AND (
        (
          SUBSTRING_INDEX(p.descr, '/', -1) LIKE CONCAT(per.first_name, '%')
          AND SUBSTRING_INDEX(p.descr, '/', -1) LIKE CONCAT('%', per.last_name)
        )
        OR
        (
          SUBSTRING_INDEX(p.descr, '/', -1) LIKE CONCAT(per.last_name, '%')
          AND SUBSTRING_INDEX(p.descr, '/', -1) LIKE CONCAT('%', per.first_name)
        )
      )
    GROUP BY p.txn_id
  ) pm 
    ON wac.txn_id = pm.txn_id
),
with_match_reason AS (
  SELECT
    wpm.*,
    CASE
      WHEN wpm.txn_exec_by = 0 AND wpm.account_exists = 1 THEN 'account_match'
      WHEN wpm.txn_exec_by = 0 AND wpm.account_exists = 0 AND wpm.no_of_person_match = 1 THEN 'name_match'
      ELSE 'manual_captured'
    END AS match_reason
  FROM with_person_matches wpm
),
with_captured_by AS (
  SELECT
    wmr.*,
    UPPER(CASE
      WHEN wmr.txn_exec_by = 0 THEN 'system'
      ELSE CONCAT_WS(' ', per.first_name, per.middle_name, per.last_name)
    END) AS captured_by_name
  FROM with_match_reason wmr
  LEFT JOIN persons per 
    ON per.id = wmr.txn_exec_by
),
with_customer_info AS (
  SELECT
    wcb.*,
    CASE 
      WHEN l.self_reg_status = 'self_reg_completed' THEN 1
      ELSE 0
    END AS is_self_reg_customer,
    CASE
      WHEN l.status = '60_customer_onboarded' THEN 1
      ELSE 0
    END AS is_kyc_completed,
    b.reg_date AS registration_date
  FROM with_captured_by wcb
  LEFT JOIN leads l 
    ON l.cust_id = wcb.cust_id
    AND l.type = 'kyc'
    AND l.is_removed = 0
  LEFT JOIN borrowers b 
    ON b.cust_id = wcb.cust_id
)
SELECT 
  EXTRACT(year_month FROM txn_date) `Month`,
  cust_id `Customer ID`,
  txn_id AS `Transaction ID`,
  txn_date AS `Transaction Date`,
  repayment_line AS `Repayment Line`,
  repayment_number AS `Repayment Number`,
  amount AS `Transaction Amount`,
  import_time AS `Import Time`,
  captured_time AS `Captured Time`,
  captured_by_name AS `Captured By`,
  match_reason AS `Captured Method`,
  account_exists AS `Account Exists`,
  name_match AS `Name Match`,
  no_of_person_match AS `No of Person Matched`,
  TIMESTAMPDIFF(MINUTE, txn_date, import_time) AS `Import Time Diff (Minutes)`,
  TIMESTAMPDIFF(MINUTE, import_time, captured_time) AS `Capture Time Diff (Minutes)`,
  is_self_reg_customer AS `Is Self Registered Customer`,
  is_kyc_completed AS `KYC Completed`,
  registration_date AS `Registration Date`,
  ref_account_num AS `Ref Account Num`,
  recon_descr AS `Recon Description`,
  person_matches AS `Name Matched`
FROM with_customer_info
ORDER BY txn_date;