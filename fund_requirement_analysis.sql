WITH original_query AS (
    SELECT
      total_os,
      od_os,
      og_os,
      fa_upgrade_amount,
      reg_cust,
      loan_principal,
      loan_amount
    FROM (
      SELECT
        @month month,
        os_val total_os,
        par_1 od_os,
        os_val - par_1 og_os
      FROM
        flow_reports.as_on_metrics
      WHERE
        as_on = @last_day
        AND flow_rel_mgr_id IS NULL
        AND country_code = @country_code
        AND acc_prvdr_code IS NULL
        AND sub_lender_code IS NULL
        AND status = 'enabled'
        AND filter_value IS NULL
        AND filter_type IS NULL
    ) o
    JOIN (
      SELECT
        @month month,
        SUM(
          JSON_UNQUOTE(JSON_EXTRACT(task_json, '$.upgrade_amount')) - 
          JSON_UNQUOTE(JSON_EXTRACT(task_json, '$.crnt_fa_limit'))
        ) fa_upgrade_amount
      FROM tasks
      WHERE task_type = 'fa_upgrade_request'
        AND status = 'approved'
        AND EXTRACT(YEAR_MONTH FROM JSON_UNQUOTE(JSON_EXTRACT(approval_json, '$[1].approved_date'))) = @month
        AND country_code = @country_code
    ) f ON f.month = o.month
    JOIN (
      SELECT
        @month month,
        COUNT(1) reg_cust
      FROM borrowers
      WHERE country_code = @country_code
        AND EXTRACT(YEAR_MONTH FROM reg_date) = @month
    ) r ON o.month = r.month
    JOIN (
      WITH raw_amount AS (
        SELECT
          EXTRACT(YEAR_MONTH FROM reg_date) reg_month,
          b.cust_id,
          loan_principal,
          loan_principal + flow_fee loan_amount
        FROM borrowers b
        JOIN (
          SELECT cust_id, loan_principal, flow_fee
          FROM loans
          WHERE id IN (
            SELECT MIN(id)
            FROM loans
            WHERE status NOT IN ('voided', 'hold', 'pending_disbursal', 'pending_mnl_dsbrsl')
              AND product_id NOT IN (
                SELECT id FROM loan_products WHERE product_type = 'float_vending'
              )
              AND country_code = 'UGA'
            GROUP BY cust_id
          )
        ) l ON b.cust_id = l.cust_id
        WHERE DATE(reg_date) >= '2023-12-01'
          AND b.country_code = 'UGA'
      )
      SELECT reg_month, SUM(loan_principal) loan_principal, SUM(loan_amount) loan_amount
      FROM raw_amount
      GROUP BY reg_month
      HAVING reg_month = @month
    ) l ON l.reg_month = o.month
)
SELECT 'Total OS' AS metric, total_os AS value FROM original_query
UNION ALL
SELECT 'Overdue OS', od_os FROM original_query
UNION ALL
SELECT 'Ongoing OS', og_os FROM original_query
UNION ALL
SELECT 'FA Upgraded Value', fa_upgrade_amount FROM original_query
UNION ALL
SELECT 'New Customers Onboarded', reg_cust FROM original_query
UNION ALL
SELECT 'Total New Customer Loan Principal Value', loan_principal FROM original_query
UNION ALL
SELECT 'Total New Customer Loan Principal + Fee Value', loan_amount FROM original_query;