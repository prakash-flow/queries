SELECT
	l.country_code `Country Code`,
	l.id `Lead ID`,
  UPPER(CONCAT_WS(' ', l.first_name, l.last_name)) `Lead Name`,
  UPPER(CONCAT_WS(' ', p.first_name, p.middle_name, p.last_name)) `RM Name`,
  UPPER(CONCAT_WS(' ', a.first_name, a.middle_name, a.last_name)) `Auditor Name`,
	COALESCE(l.lead_date, l.created_at) `Lead Created Time`,
  COALESCE(l.assessment_date, b.reg_date) `Assessment Date`,
  l.rm_kyc_start_date `RM KYC Start Time`,
  l.rm_kyc_end_date `RM KYC End Time`,
  l.actual_audit_start_date `Audit Start Time`,
  l.audit_kyc_end_date `Audit End Time`,
  IFNULL(no_of_reassign, 0) `No of Reassign`,
  l.kyc_reason,
  IF(l.status = '60_customer_onboarded', '1', '0') `KYC Completed`
FROM
  leads l
  JOIN borrowers b on b.cust_id = l.cust_id
  LEFT JOIN persons p on p.id = l.flow_rel_mgr_id
  LEFT JOIN persons a on a.id = l.audited_by
  LEFT JOIN (
  	select lead_id, count(1) no_of_reassign from audit_comments where type = 'reassign' group by lead_id
  ) ac on ac.lead_id = l.id
where
  l.type = 'kyc'
  AND l.country_code in ('UGA', 'RWA')
  AND EXTRACT(
    YEAR_MONTH
    FROM
      COALESCE(l.lead_date, l.created_at)
  ) IN (202507, 202508, 202509)
  AND l.is_removed = 0
  ORDER BY l.country_code DESC;