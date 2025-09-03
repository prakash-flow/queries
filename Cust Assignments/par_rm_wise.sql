set 
  @country_code = 'UGA';
set 
  @month = '202503';
set 
  @last_day = (
    LAST_DAY(
      DATE(
        CONCAT(@month, "01")
      )
    )
  );
set 
  @realization_date = (
    IFNULL(
      (
        select 
          closure_date 
        from 
          closure_date_records 
        where 
          month = @month 
          and status = 'enabled' 
          and country_code = @country_code
      ), 
      now()
    )
  );
select 
  @last_day, 
  @realization_date;
WITH recentReassignments AS (
  SELECT 
    cust_id, 
    from_rm_id 
  FROM 
    (
      SELECT 
        cust_id, 
        from_rm_id, 
        ROW_NUMBER() OVER (
          PARTITION BY cust_id 
          ORDER BY 
            from_date ASC
        ) rn 
      FROM 
        rm_cust_assignments rm_cust 
      WHERE 
        rm_cust.country_code = @country_code 
        AND rm_cust.reason_for_reassign NOT IN ('initial_assignment') 
        AND DATE(rm_cust.from_date) > @last_day
    ) t 
  WHERE 
    rn = 1
) 
SELECT 
  COALESCE(r.from_rm_id, l.flow_rel_mgr_id) AS rm_id, 
  SUM(
    IF(
      DATEDIFF(@last_day, l.due_date) > 10, 
      IF(
        l.loan_principal - t.total_amount > 0, 
        l.loan_principal - t.total_amount, 
        0
      ), 
      0
    )
  ) AS `PAR 10` 
FROM 
  (
    SELECT 
      loan_doc_id, 
      SUM(
        IF(txn_type = 'payment', principal, 0)
      ) AS total_amount 
    FROM 
      loan_txns 
    WHERE 
      DATE(txn_date) <= @last_day 
      AND realization_date <= @realization_date 
    GROUP BY 
      loan_doc_id
  ) t 
  JOIN loans l ON l.loan_doc_id = t.loan_doc_id 
  LEFT JOIN recentReassignments r ON l.cust_id = r.cust_id 
WHERE 
  l.status NOT IN (
    'voided', 'hold', 'pending_disbursal', 
    'pending_mnl_dsbrsl'
  ) 
  AND DATE(l.disbursal_Date) <= @last_day 
  AND l.product_id NOT IN ('43', '75', '300') 
  AND l.loan_doc_id NOT IN (
    SELECT 
      loan_doc_id 
    FROM 
      loan_write_off 
    WHERE 
      write_off_date <= @last_day 
      AND write_off_status IN (
        'approved', 'partially_recovered', 
        'recovered'
      ) 
      AND country_code = @country_code
  ) 
  AND l.country_code = @country_code 
GROUP BY 
  rm_id;