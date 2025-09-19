select
  c.entity_id `Lead ID`,
  UPPER(
    COALESCE(
      JSON_UNQUOTE(JSON_EXTRACT(lead_json, '$."cust_name"')),
      CONCAT_WS(' ', l.first_name, l.last_name),
      JSON_UNQUOTE(JSON_EXTRACT(lead_json, '$."cust_name"')),
      CONCAT_WS(
        ' ',
        JSON_UNQUOTE(JSON_EXTRACT(lead_json, '$.first_name')),
        JSON_UNQUOTE(JSON_EXTRACT(lead_json, '$.last_name'))
      )
    )
  ) `Customer Name`,
  c.acc_number `Agent ID`,
  c.alt_acc_num `Agent Line Number`,
  COALESCE(
    l.mobile_num,
    JSON_EXTRACT(lead_json, '$.mobile_num')
  ) `Customer Number`,
  c.result AS `Result`,
  c.limit `Limit`,
  UPPER(
    concat_ws(' ', p.first_name, p.middle_name, p.last_name)
  ) `RM Name`,
  p.mobile_num `RM Number`
from
  customer_statements c
  join leads l on c.entity_id = l.id
  left join persons p on p.id = l.flow_rel_mgr_id
where
  c.batch_reassessment_id = 3;
