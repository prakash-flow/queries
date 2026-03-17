WITH RawBase AS (
  SELECT 
      ra.country_code AS c_code,
      ra.record_code AS r_code,
      trim(toString(ra.record_id)) AS c_id_join, 
      ra.created_at AS e_time, 
      ra.created_by AS creator_id,
      JSONExtractString(ra.data_after, 'status') AS s_val,
      replaceRegexpAll(coalesce(ra.remarks, JSONExtractString(ra.data_after, 'reason')), '[\[\]"_ ]', ' ') AS r_val,
      a.role_codes AS d_role_raw,
      db.full_name AS d_name_raw
  FROM record_audits AS ra
  LEFT JOIN app_users AS a ON a.id = ra.created_by
  LEFT JOIN persons AS db ON db.id = a.person_id
  WHERE ra.created_at >= now() - INTERVAL 12 MONTH
    AND JSONExtractString(ra.data_after, 'status') IN ('disabled', 'enabled')
    AND ra.country_code = 'RWA'
),
CalculatedDates AS (
  SELECT 
      *,
      minIf(e_time, s_val = 'enabled') OVER (
          PARTITION BY r_code 
          ORDER BY e_time ASC 
          ROWS BETWEEN 1 FOLLOWING AND UNBOUNDED FOLLOWING
      ) AS re_enabled_time_raw
  FROM RawBase
),
-- Step 1: Get the latest limit per customer for any given point in time
LatestLimits AS (
    SELECT 
        cust_id,
        last_upgraded_amount,
        created_at
    FROM customer_repayment_limits
),
-- Step 2: Prepare Loan History and use ASOF JOIN to match the limit to the loan
LoanWithLimits AS (
    SELECT 
        l.cust_id,
        l.loan_doc_id,
        l.loan_principal,
        l.flow_fee,
        l.due_date,
        l.paid_date,
        l.disbursal_date,
        toDateTime(l.disbursal_date) AS loan_time,
        -- If no limit found, use loan_principal as the base
        greatest(toFloat64(l.loan_principal), ifNull(toFloat64(lim.last_upgraded_amount), 0)) AS limit_val
    FROM loans AS l
    ASOF LEFT JOIN LatestLimits AS lim 
        ON l.cust_id = lim.cust_id AND l.disbursal_date >= lim.created_at
    WHERE l.country_code = 'RWA'
      AND l.product_id NOT IN (43, 75, 300)
      AND l.status NOT IN ('voided','hold','pending_disbursal','pending_mnl_dsbrsl')
      AND l.loan_purpose = 'float_advance'
),
VisitDetails AS (
    SELECT
        b.cust_id AS cust_id,
        max(toDate(fv.visit_end_time)) AS last_visit_date,
        p.full_name AS customer_name,
        p.mobile_num AS customer_mobile_num
    FROM borrowers b
    LEFT JOIN field_visits fv
        ON fv.cust_id = b.cust_id
        AND fv.country_code = 'RWA'
        AND fv.sch_status = 'checked_out'
        AND toDate(fv.visit_end_time) <= today()
    LEFT JOIN persons p
        ON b.owner_person_id = p.id
    WHERE b.country_code = 'RWA'
    GROUP BY
        b.cust_id,
        p.full_name,
        p.mobile_num
)
SELECT 
  cd.c_code AS `Country Code`,
  toYYYYMM(cd.e_time) AS `Disabled Month`,
  cd.r_code AS `Customer ID`,
  vd.customer_name AS `Customer Name`,
  vd.customer_mobile_num AS `Customer Mobile Number`,
  vd.last_visit_date AS `Last Visit Date`,
  l.loan_doc_id AS `Last Loan ID`,  
  l.loan_principal AS `Last FA amount`,
  l.flow_fee AS `Last FA fee`,
  toDate(l.due_date) AS `Last FA Due date`,
  toDate(l.paid_date) AS `Last FA Paid date`,
  -- Calculate the FA Limit bucket from the joined limit_val
  if(
      ifNull(
          arrayMax(
              arrayFilter(
                  x -> x <= l.limit_val,
                  [70000,100000,150000,200000,300000,400000,500000,600000,700000,800000,900000,1000000,1500000,2000000,2500000,3000000]
              )
          ),
          0
      ) = 0,
      l.limit_val,
      arrayMax(
          arrayFilter(
              x -> x <= l.limit_val,
              [70000,100000,150000,200000,300000,400000,500000,600000,700000,800000,900000,1000000,1500000,2000000,2500000,3000000]
          )
      )
  ) AS `FA limit at the time of FA`,
  toDate(cd.e_time) AS `Disabled On`,
  concat(
      upper(multiIf(cd.creator_id = 0, 'System', cd.d_role_raw = '', 'Unknown', replaceAll(cd.d_role_raw, '_', ' '))),
      ' / ',
      upper(multiIf(cd.creator_id = 0, 'System', cd.d_name_raw = '', 'Unknown', cd.d_name_raw))
  ) AS `Disabled By`,
  cd.r_val AS `Disable Reason`,
  if(cd.re_enabled_time_raw > '1970-01-01', toString(toDate(cd.re_enabled_time_raw)), 'Still Disabled') AS `Re-enabled At`,
  if(cd.re_enabled_time_raw > '1970-01-01', toString(dateDiff('day', toDate(cd.e_time), toDate(cd.re_enabled_time_raw))), 'N/A') AS `Days Disabled`
FROM CalculatedDates AS cd
ASOF LEFT JOIN LoanWithLimits AS l 
  ON cd.r_code = toString(l.cust_id) AND cd.e_time >= l.loan_time
LEFT JOIN VisitDetails vd
    ON vd.cust_id = cd.r_code
WHERE cd.s_val = 'disabled'
  AND cd.e_time >= now() - INTERVAL 7 MONTH
ORDER BY `Disabled On` ASC;