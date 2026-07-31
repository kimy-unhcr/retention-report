with
-- donors having RG payment history in the last 12m (transaction_date based)
donor_rg AS (
  SELECT supporter_id
  FROM `unhcr-kor-dl-ana-prod.DataMarts.korea_fact_transaction`
  WHERE transaction_type = 'Regular'
  AND transaction_date  >= DATE '2025-07-01'
  AND transaction_date <= DATE '2026-06-30'
  group by supporter_id
),

-- total transaction history of the last 12m
 ig_tran_base AS (
    SELECT transaction_id,
    supporter_id,
    campaign_id,
    transaction_type,
    payment_method, -- Regular/Single
    transaction_date, 
    first_month,
    transaction_amount,
    product, 
    mvd_income_auto, 
    transaction_date + 365 AS grace_12,
           
-- rg/oo ROW numbering
    ROW_NUMBER() OVER (
    PARTITION BY supporter_id, transaction_type
    ORDER BY transaction_date DESC, supporter_id
    ) AS tran_nm_2,
  		
	CASE 
    WHEN transaction_date  >= DATE '2025-07-01'
    AND transaction_date <= DATE '2026-06-30'
    THEN 'Y'
    ELSE 'N'
    END AS tran_ty

    FROM `unhcr-kor-dl-ana-prod.DataMarts.korea_fact_transaction`
    WHERE transaction_date >= DATE '2025-07-01'
      AND transaction_date <= DATE '2026-06-30'
),


ig_tran_donor_type as (
SELECT 
    a.*,
    CASE 
      WHEN a.tran_ty = 'Y' THEN 
      CASE WHEN rg.supporter_id  IS NOT NULL THEN 'RG' -- RG if within the RG list
      ELSE 'Pure OO' END -- else Pure OO
     ELSE  NULL
     END AS donor_type_ty,
    c.all_end_date
  FROM ig_tran_base a
  LEFT JOIN donor_rg rg ON a.supporter_id = rg.supporter_id
  inner join unhcr-kor-dl-ana-uat.mrm_db.Contacts c on a.supporter_id =c.donor_no
)

--active donor summary
SELECT 
  '2026Q2' AS reporting, 
  donor_type_ty AS donor_type, 
  COUNT(DISTINCT supporter_id) AS supporter_count
FROM ig_tran_donor_type a
WHERE tran_ty = 'Y'
  AND (
    (donor_type_ty = 'RG' AND (all_end_date IS NULL or all_end_date < date '2025-07-01' 
	OR all_end_date > DATE '2026-06-30')) -- Still active RG as of Q2 2026
  OR donor_type_ty = 'Pure OO'
  )
GROUP BY donor_type_ty

