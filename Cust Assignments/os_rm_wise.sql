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
  COALESCE(
    r.from_rm_id, pri.flow_rel_mgr_id
  ) AS rm_id, 
  SUM(
    IF(
      pri.principal - IFNULL(pp.partial_pay, 0) < 0, 
      0, 
      pri.principal - IFNULL(pp.partial_pay, 0)
    )
  ) AS `Net portfolio` 
FROM 
  (
    SELECT 
      l.loan_doc_id, 
      loan_principal AS principal, 
      l.flow_rel_mgr_id, 
      l.cust_id 
    FROM 
      loans l 
      JOIN loan_txns lt ON lt.loan_doc_id = l.loan_doc_id 
    WHERE 
      lt.txn_type IN ('disbursal') 
      AND lt.realization_date <= @realization_date 
      AND l.country_code = @country_code 
      AND DATE(l.disbursal_date) <= @last_day 
      AND l.product_id NOT IN (43, 75, 300) 
      AND l.status NOT IN (
        'voided', 'hold', 'pending_disbursal', 
        'pending_mnl_dsbrsl'
      ) 
      AND l.loan_doc_id NOT IN (
        SELECT 
          loan_doc_id 
        FROM 
          loan_write_off 
        WHERE 
          loan_write_off.country_code = @country_code 
          AND DATE(write_off_date) <= @last_day 
          AND write_off_status IN (
            'approved', 'partially_recovered', 
            'recovered'
          )
      )
  ) AS pri 
  LEFT JOIN (
    SELECT 
      loan_doc_id, 
      SUM(principal) AS partial_pay 
    FROM 
      loan_txns t 
    WHERE 
      t.country_code = @country_code 
      AND t.realization_date <= @realization_date 
      AND DATE(t.txn_date) <= @last_day 
      AND t.txn_type = 'payment' 
    GROUP BY 
      loan_doc_id
  ) AS pp ON pri.loan_doc_id = pp.loan_doc_id 
  LEFT JOIN recentReassignments AS r ON r.cust_id = pri.cust_id 
GROUP BY 
  rm_id;