/* ===============================
   Parameters
================================ */
SET @country_code = 'RWA';
SET @month = '202508';

SET @last_day = (
    SELECT LAST_DAY(DATE(CONCAT(@month, '01')))
);

SET @closure_date = (
    SELECT closure_date
    FROM flow_api.closure_date_records
    WHERE status = 'enabled'
      AND month = @month
      AND country_code = @country_code
);

/* ===============================
   CTEs
================================ */
WITH loan AS (
    SELECT
        l.loan_doc_id,
        l.loan_purpose
    FROM loans l
    JOIN loan_txns lt
        ON lt.loan_doc_id = l.loan_doc_id
    WHERE lt.txn_type IN ('af_disbursal')
      AND l.loan_purpose IN ('growth_financing', 'asset_financing')
      AND l.country_code = @country_code
      AND DATE(disbursal_date) <= @last_day
      AND realization_date <= @closure_date
      AND product_id NOT IN (
          SELECT id
          FROM loan_products
          WHERE product_type = 'float_vending'
      )
      AND status NOT IN (
          'voided', 'hold',
          'pending_disbursal',
          'pending_mnl_dsbrsl'
      )
      AND l.loan_doc_id NOT IN (
          SELECT loan_doc_id
          FROM loan_write_off
          WHERE country_code = @country_code
            AND write_off_date <= @last_day
            AND write_off_status IN (
                'approved',
                'partially_recovered',
                'recovered'
            )
      )
    GROUP BY l.loan_doc_id
),

loan_installment AS (
    SELECT
        loan_doc_id,
        installment_number,
        principal_due AS installment_principal,
        fee_due AS installment_fee,
        due_date
    FROM loan_installments
    WHERE loan_doc_id IN (SELECT loan_doc_id FROM loan)
),

payment AS (
    SELECT
        p.loan_doc_id,
        p.installment_number,
        SUM(p.principal_amount) AS paid_principal,
        SUM(p.fee_amount) AS paid_fee
    FROM payment_allocation_items p
    JOIN account_stmts a
        ON a.id = p.account_stmt_id
    WHERE EXTRACT(YEAR_MONTH FROM stmt_txn_date) <= @month
      AND realization_date <= @closure_date
      AND p.country_code = @country_code
      AND a.country_code = @country_code
    GROUP BY p.loan_doc_id, p.installment_number
),

/* ===============================
   Installment-level OS & PAR Analysis
   Logic: 
   1. Only include installments that are DUE (due_date <= @last_day)
   2. Calculate outstanding fee amount per installment
   3. Calculate PAR days per installment individually
================================ */
installment_level_analysis AS (
    SELECT
        l.loan_doc_id,
        l.loan_purpose,
        li.due_date,
        
        /* Outstanding Fee Amount */
        GREATEST(
            li.installment_fee - IFNULL(p.paid_fee, 0),
            0
        ) AS os_fee_amount,

        /* PAR Days Calculation (Per Installment) */
        DATEDIFF(@last_day, li.due_date) AS par_days

    FROM loan l
    JOIN loan_installment li
        ON li.loan_doc_id = l.loan_doc_id
    LEFT JOIN payment p
        ON p.loan_doc_id = li.loan_doc_id
       AND p.installment_number = li.installment_number
    WHERE li.due_date <= @last_day
)

/* ===============================
   Aggregation: Summing Installment Buckets
================================ */
SELECT
    loan_purpose AS `Loan Purpose`,

    /* Total Fee Outstanding (Sum of all overdue fee amounts) */
    SUM(os_fee_amount) AS `Total Fee Outstanding`,

    /* PAR Buckets: Summing the specific installments that fall into each bucket */
    SUM(CASE WHEN par_days > 1   THEN os_fee_amount ELSE 0 END) AS `Par 1`,
    SUM(CASE WHEN par_days > 5   THEN os_fee_amount ELSE 0 END) AS `Par 5`,
    SUM(CASE WHEN par_days > 10  THEN os_fee_amount ELSE 0 END) AS `Par 10`,
    SUM(CASE WHEN par_days > 15  THEN os_fee_amount ELSE 0 END) AS `Par 15`,
    SUM(CASE WHEN par_days > 30  THEN os_fee_amount ELSE 0 END) AS `Par 30`,
    SUM(CASE WHEN par_days > 60  THEN os_fee_amount ELSE 0 END) AS `Par 60`,
    SUM(CASE WHEN par_days > 90  THEN os_fee_amount ELSE 0 END) AS `Par 90`,
    SUM(CASE WHEN par_days > 120 THEN os_fee_amount ELSE 0 END) AS `Par 120`,
    SUM(CASE WHEN par_days > 180 THEN os_fee_amount ELSE 0 END) AS `Par 180`,
    SUM(CASE WHEN par_days > 270 THEN os_fee_amount ELSE 0 END) AS `Par 270`,
    SUM(CASE WHEN par_days > 360 THEN os_fee_amount ELSE 0 END) AS `Par 360`

FROM installment_level_analysis
GROUP BY loan_purpose
ORDER BY loan_purpose;
