SET @cur_date = '2026-01-13';
SET @country_code = 'UGA';

WITH latest_accounts AS (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY alt_acc_num
               ORDER BY id DESC
           ) AS rn
    FROM accounts
    WHERE acc_prvdr_code = 'UMTN'
      AND status = 'enabled'
),

base AS (
    SELECT 
        a.cust_id,
        p.full_name AS borrower_name,
        a.acc_number,
        a.alt_acc_num,
        b.reg_date,
        EXTRACT(YEAR_MONTH FROM b.reg_date) AS reg_month
    FROM borrowers b
    JOIN latest_accounts a
        ON a.cust_id = b.cust_id
       AND a.rn = 1
    LEFT JOIN persons p 
        ON b.owner_person_id = p.id
    WHERE b.country_code = @country_code
),

cust_comms AS (
    SELECT 
        identifier,
        CAST(month AS UNSIGNED) AS month_num,
        commission
    FROM cust_commissions
),

comm_growth AS (
    SELECT 
        b.alt_acc_num,
        b.reg_month,

        DATE_FORMAT(DATE_SUB(STR_TO_DATE(CONCAT(b.reg_month,'01'),'%Y%m%d'), INTERVAL 6 MONTH),'%Y%m') AS prev_m6_month,
        DATE_FORMAT(DATE_SUB(STR_TO_DATE(CONCAT(b.reg_month,'01'),'%Y%m%d'), INTERVAL 5 MONTH),'%Y%m') AS prev_m5_month,
        DATE_FORMAT(DATE_SUB(STR_TO_DATE(CONCAT(b.reg_month,'01'),'%Y%m%d'), INTERVAL 4 MONTH),'%Y%m') AS prev_m4_month,
        DATE_FORMAT(DATE_SUB(STR_TO_DATE(CONCAT(b.reg_month,'01'),'%Y%m%d'), INTERVAL 3 MONTH),'%Y%m') AS prev_m3_month,
        DATE_FORMAT(DATE_SUB(STR_TO_DATE(CONCAT(b.reg_month,'01'),'%Y%m%d'), INTERVAL 2 MONTH),'%Y%m') AS prev_m2_month,
        DATE_FORMAT(DATE_SUB(STR_TO_DATE(CONCAT(b.reg_month,'01'),'%Y%m%d'), INTERVAL 1 MONTH),'%Y%m') AS prev_m1_month,

        b.reg_month AS reg_month_key,

        DATE_FORMAT(DATE_ADD(STR_TO_DATE(CONCAT(b.reg_month,'01'),'%Y%m%d'), INTERVAL 1 MONTH),'%Y%m') AS next_m1_month,
        DATE_FORMAT(DATE_ADD(STR_TO_DATE(CONCAT(b.reg_month,'01'),'%Y%m%d'), INTERVAL 2 MONTH),'%Y%m') AS next_m2_month,
        DATE_FORMAT(DATE_ADD(STR_TO_DATE(CONCAT(b.reg_month,'01'),'%Y%m%d'), INTERVAL 3 MONTH),'%Y%m') AS next_m3_month,
        DATE_FORMAT(DATE_ADD(STR_TO_DATE(CONCAT(b.reg_month,'01'),'%Y%m%d'), INTERVAL 4 MONTH),'%Y%m') AS next_m4_month,
        DATE_FORMAT(DATE_ADD(STR_TO_DATE(CONCAT(b.reg_month,'01'),'%Y%m%d'), INTERVAL 5 MONTH),'%Y%m') AS next_m5_month,
        DATE_FORMAT(DATE_ADD(STR_TO_DATE(CONCAT(b.reg_month,'01'),'%Y%m%d'), INTERVAL 6 MONTH),'%Y%m') AS next_m6_month,

        MAX(CASE WHEN c.month_num = DATE_FORMAT(DATE_SUB(STR_TO_DATE(CONCAT(b.reg_month,'01'),'%Y%m%d'), INTERVAL 6 MONTH),'%Y%m')+0 THEN c.commission END) AS prev_m6,
        MAX(CASE WHEN c.month_num = DATE_FORMAT(DATE_SUB(STR_TO_DATE(CONCAT(b.reg_month,'01'),'%Y%m%d'), INTERVAL 5 MONTH),'%Y%m')+0 THEN c.commission END) AS prev_m5,
        MAX(CASE WHEN c.month_num = DATE_FORMAT(DATE_SUB(STR_TO_DATE(CONCAT(b.reg_month,'01'),'%Y%m%d'), INTERVAL 4 MONTH),'%Y%m')+0 THEN c.commission END) AS prev_m4,
        MAX(CASE WHEN c.month_num = DATE_FORMAT(DATE_SUB(STR_TO_DATE(CONCAT(b.reg_month,'01'),'%Y%m%d'), INTERVAL 3 MONTH),'%Y%m')+0 THEN c.commission END) AS prev_m3,
        MAX(CASE WHEN c.month_num = DATE_FORMAT(DATE_SUB(STR_TO_DATE(CONCAT(b.reg_month,'01'),'%Y%m%d'), INTERVAL 2 MONTH),'%Y%m')+0 THEN c.commission END) AS prev_m2,
        MAX(CASE WHEN c.month_num = DATE_FORMAT(DATE_SUB(STR_TO_DATE(CONCAT(b.reg_month,'01'),'%Y%m%d'), INTERVAL 1 MONTH),'%Y%m')+0 THEN c.commission END) AS prev_m1,

        MAX(CASE WHEN c.month_num = b.reg_month+0 THEN c.commission END) AS reg_comm,

        MAX(CASE WHEN c.month_num = DATE_FORMAT(DATE_ADD(STR_TO_DATE(CONCAT(b.reg_month,'01'),'%Y%m%d'), INTERVAL 1 MONTH),'%Y%m')+0 THEN c.commission END) AS next_m1,
        MAX(CASE WHEN c.month_num = DATE_FORMAT(DATE_ADD(STR_TO_DATE(CONCAT(b.reg_month,'01'),'%Y%m%d'), INTERVAL 2 MONTH),'%Y%m')+0 THEN c.commission END) AS next_m2,
        MAX(CASE WHEN c.month_num = DATE_FORMAT(DATE_ADD(STR_TO_DATE(CONCAT(b.reg_month,'01'),'%Y%m%d'), INTERVAL 3 MONTH),'%Y%m')+0 THEN c.commission END) AS next_m3,
        MAX(CASE WHEN c.month_num = DATE_FORMAT(DATE_ADD(STR_TO_DATE(CONCAT(b.reg_month,'01'),'%Y%m%d'), INTERVAL 4 MONTH),'%Y%m')+0 THEN c.commission END) AS next_m4,
        MAX(CASE WHEN c.month_num = DATE_FORMAT(DATE_ADD(STR_TO_DATE(CONCAT(b.reg_month,'01'),'%Y%m%d'), INTERVAL 5 MONTH),'%Y%m')+0 THEN c.commission END) AS next_m5,
        MAX(CASE WHEN c.month_num = DATE_FORMAT(DATE_ADD(STR_TO_DATE(CONCAT(b.reg_month,'01'),'%Y%m%d'), INTERVAL 6 MONTH),'%Y%m')+0 THEN c.commission END) AS next_m6

    FROM base b
    LEFT JOIN cust_comms c 
        ON c.identifier = b.alt_acc_num
    GROUP BY b.alt_acc_num, b.reg_month
),

growth_calc AS (
    SELECT *,
        (prev_m1 + prev_m2 + prev_m3 + prev_m4 + prev_m5 + prev_m6)/6 AS prev6_avg,

        (next_m1 - ((prev_m1 + prev_m2 + prev_m3 + prev_m4 + prev_m5 + prev_m6)/6))
        / NULLIF(((prev_m1 + prev_m2 + prev_m3 + prev_m4 + prev_m5 + prev_m6)/6),0) AS growth_next1,

        (next_m2 - ((prev_m1 + prev_m2 + prev_m3 + prev_m4 + prev_m5 + prev_m6)/6))
        / NULLIF(((prev_m1 + prev_m2 + prev_m3 + prev_m4 + prev_m5 + prev_m6)/6),0) AS growth_next2,

        (next_m3 - ((prev_m1 + prev_m2 + prev_m3 + prev_m4 + prev_m5 + prev_m6)/6))
        / NULLIF(((prev_m1 + prev_m2 + prev_m3 + prev_m4 + prev_m5 + prev_m6)/6),0) AS growth_next3,

        (next_m4 - ((prev_m1 + prev_m2 + prev_m3 + prev_m4 + prev_m5 + prev_m6)/6))
        / NULLIF(((prev_m1 + prev_m2 + prev_m3 + prev_m4 + prev_m5 + prev_m6)/6),0) AS growth_next4,

        (next_m5 - ((prev_m1 + prev_m2 + prev_m3 + prev_m4 + prev_m5 + prev_m6)/6))
        / NULLIF(((prev_m1 + prev_m2 + prev_m3 + prev_m4 + prev_m5 + prev_m6)/6),0) AS growth_next5,

        (next_m6 - ((prev_m1 + prev_m2 + prev_m3 + prev_m4 + prev_m5 + prev_m6)/6))
        / NULLIF(((prev_m1 + prev_m2 + prev_m3 + prev_m4 + prev_m5 + prev_m6)/6),0) AS growth_next6
    FROM comm_growth
)

SELECT 
    bi.cust_id,
    bi.borrower_name,
    bi.acc_number,
    bi.alt_acc_num,
    bi.reg_date,
    gc.reg_month_key AS reg_month,

    prev6_avg,

    prev_m6_month AS month_prev6, prev_m6 AS comm_prev6,
    prev_m5_month AS month_prev5, prev_m5 AS comm_prev5,
    prev_m4_month AS month_prev4, prev_m4 AS comm_prev4,
    prev_m3_month AS month_prev3, prev_m3 AS comm_prev3,
    prev_m2_month AS month_prev2, prev_m2 AS comm_prev2,
    prev_m1_month AS month_prev1, prev_m1 AS comm_prev1,

    reg_comm AS comm_reg,

    next_m1_month AS month_next1, next_m1 AS comm_next1,
    next_m2_month AS month_next2, next_m2 AS comm_next2,
    next_m3_month AS month_next3, next_m3 AS comm_next3,
    next_m4_month AS month_next4, next_m4 AS comm_next4,
    next_m5_month AS month_next5, next_m5 AS comm_next5,
    next_m6_month AS month_next6, next_m6 AS comm_next6,

    growth_next1,
    growth_next2,
    growth_next3,
    growth_next4,
    growth_next5,
    growth_next6

FROM base bi
LEFT JOIN growth_calc gc 
    ON bi.alt_acc_num = gc.alt_acc_num
ORDER BY growth_next6 DESC;