WITH
  account_cte AS (
    SELECT
      cust_id,
      acc_number,
      if(
        startsWith (alt_acc_num, '0'),
        substring(alt_acc_num, 2),
        alt_acc_num
      ) AS alt_acc_num,
      status
    FROM
      (
        SELECT
          cust_id,
          acc_number,
          alt_acc_num,
          status,
          ROW_NUMBER() OVER (
            PARTITION BY
              alt_acc_num
            ORDER BY
              CASE
                WHEN status = 'enabled' THEN 1
                ELSE 2
              END,
              created_at DESC
          ) AS rn
        FROM
          accounts
        WHERE
          country_code = 'UGA'
          AND acc_prvdr_code = 'UMTN'
          AND cust_id IS NOT NULL
          AND is_removed = 0
          AND alt_acc_num IS NOT NULL
          AND status NOT IN (
            'pending_otp_verification',
            'pending_verification'
          )
          AND length(alt_acc_num) > 0
      ) a
    WHERE
      rn = 1
  )
SELECT
  a.cust_id AS `Customer ID`,
  a.acc_number AS `Account Number`,
  concat('256', a.alt_acc_num) AS `Agent Line Number`,
  p.mobile_num AS `Mobile Number`
FROM
  account_cte a
  INNER JOIN borrowers b ON b.cust_id = a.cust_id
  INNER JOIN persons p ON p.id = b.owner_person_id;