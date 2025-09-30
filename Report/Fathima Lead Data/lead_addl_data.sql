SELECT
	l.country_code `Country Code`,
  l.type `Lead Type`,
	l.id `Lead ID`,
  UPPER(CONCAT_WS(' ', l.first_name, l.last_name)) `Lead Name`,
  UPPER(CONCAT_WS(' ', p.first_name, p.middle_name, p.last_name)) `RM Name`,
  UPPER(CONCAT_WS(' ', a.first_name, a.middle_name, a.last_name)) `Auditor Name`,
  ac.section `Reassigned Section`,
  ac.comment `Reassigned Reason`,
  ac.created_at `Reassigned Time`,
  ac.resolved_at `Resolved Time`
FROM
  leads l
  JOIN borrowers b on b.cust_id = l.cust_id
  LEFT JOIN persons p on p.id = l.flow_rel_mgr_id
  LEFT JOIN persons a on a.id = l.audited_by
  LEFT JOIN audit_comments ac on ac.lead_id = l.id
where
  l.country_code in ('UGA', 'RWA')
  AND EXTRACT(
    YEAR_MONTH
    FROM
      COALESCE(l.lead_date, l.created_at)
  ) IN (202507, 202508, 202509)
  AND l.is_removed = 0
  ORDER BY l.country_code DESC, l.type, l.id;