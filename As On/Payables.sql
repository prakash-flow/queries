set
    @month = 202511;

  set
    @country_code = 'UGA';

  set
    @closure_date = (
      select
        closure_date
      from
        closure_date_records
      where
        country_code = @country_code
        and status = 'enabled'
        and month = @month
    );

  set
    @prev_closure_date = (
      select
        closure_date
      from
        closure_date_records
      where
        country_code = @country_code
        and status = 'enabled'
        and month = DATE_FORMAT(
          DATE_SUB(DATE(CONCAT(@month, '01')), INTERVAL 1 MONTH),
          '%Y%m'
        )
    );

  select
    @country_code,
    @month,
    @closure_date,
    @prev_closure_date;

  WITH
    pri AS (
      SELECT
        l.loan_doc_id,
        SUM(IF(txn_type = 'payment', lt.excess, lt.amount)) AS excess,
        l.country_code
      FROM
        loans l
        JOIN loan_txns lt ON lt.loan_doc_id = l.loan_doc_id
      WHERE
        lt.txn_type IN ("payment")
        AND l.country_code = @country_code
        AND (
          (
            extract(
              year_month
              from
                txn_date
            ) <= @month
            AND realization_date <= @closure_date
          )
        )
        AND product_id NOT IN(
          SELECT
            id
          FROM
            loan_products
          WHERE
            product_type = 'float_vending'
        )
        AND status NOT IN(
          'voided',
          'hold',
          'pending_disbursal',
          'pending_mnl_dsbrsl'
        )
      GROUP BY
        l.loan_doc_id
      HAVING
        excess > 0
    ),
    sec as (
      SELECT
        l.loan_doc_id,
        IFNULL(SUM(lt.amount), 0) AS excess_reversal,
        l.country_code
      FROM
        loans l
        JOIN loan_txns lt ON lt.loan_doc_id = l.loan_doc_id
      WHERE
        lt.txn_type IN ("excess_reversal")
        AND l.country_code = @country_code
        AND (
          (
            extract(
              year_month
              from
                txn_date
            ) <= @month
            AND realization_date <= @closure_date
          )
        )
        AND product_id NOT IN(
          SELECT
            id
          FROM
            loan_products
          WHERE
            product_type = 'float_vending'
        )
        AND status NOT IN(
          'voided',
          'hold',
          'pending_disbursal',
          'pending_mnl_dsbrsl'
        )
      GROUP BY
        l.loan_doc_id
    ),
    metricByLoan as (
      SELECT
        pri.loan_doc_id,
        IFNULL(pri.excess, 0) excess,
        IFNULL(sec.excess_reversal, 0) excess_reversal,
        IFNULL(pri.excess, 0) - ifnull(sec.excess_reversal, 0) unreversed_excess
      FROM
        pri
        LEFT JOIN sec ON pri.loan_doc_id = sec.loan_doc_id
      WHERE
        pri.country_code = @country_code
      UNION
      SELECT
        sec.loan_doc_id,
        IFNULL(pri.excess, 0) excess,
        IFNULL(sec.excess_reversal, 0) excess_reversal,
        IFNULL(pri.excess, 0) - ifnull(sec.excess_reversal, 0) unreversed_excess
      FROM
        pri
        RIGHT JOIN sec ON pri.loan_doc_id = sec.loan_doc_id
      WHERE
        sec.country_code = @country_code
    ),
    loan_date as (
      select
      	LAST_DAY(DATE(CONCAT(@month, '01'))) `As OF`,
        m.loan_doc_id `Loan ID`,
        l.cust_id `Customer ID`,
        l.acc_prvdr_code `Account Provider Code`,
        concat_ws(' ', p.first_name, p.middle_name, p.last_name) `Customer Name`,
        l.acc_number `Account Number`,
        concat_ws(' ', rm.first_name, rm.middle_name, rm.last_name) `RM Name`,
        m.excess `Excess`,
        m.excess_reversal `Reversal`,
        m.unreversed_excess `Unreversed`
      from
        loans l
        join metricByLoan m on l.loan_doc_id = m.loan_doc_id
        join borrowers b on l.cust_id = b.cust_id
        left join persons p on p.id = b.owner_person_id
        left join persons rm on rm.id = l.flow_rel_mgr_id
    )
  select
 		*
  from
    loan_date;