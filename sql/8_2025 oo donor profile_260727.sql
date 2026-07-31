
--Part 1. LTV data에서 transaction 관련 필요한 table 추출

-- LTV data source: unhcr-kor-dl-ana-uat.ltv_db.LTV_Tran_Output


-- create or replace table unhcr-kor-dl-ana-uat.workspace_joomee.donor_profile_oo_2025_rev as

with oo_transaction_2512 as (
		SELECT * 
		FROM unhcr-kor-dl-ana-uat.ltv_db.LTV_Tran_Output
		where transaction_date between '20250101' and '20251231'
		AND payment_type = '1'
		AND Payment_Method is not null
		and Payment_Method not in ('HappyBean')),
		--AND payment_method NOT IN ('카카오','휴대폰','포인트','NULL', '해피빈','ARS', 'GIK', '공간기부')) -- 이중에 있는 게 해피빈 밖에 없음
		

rg_transaction_2512 as (		
		SELECT * 
		FROM unhcr-kor-dl-ana-uat.ltv_db.LTV_Tran_Output
		where transaction_date between '20250101' and '20251231'
		AND payment_type = '2'),


oo_trans_till2025 as ( -- 과거 전체 수시납부

		SELECT * 
		FROM unhcr-kor-dl-ana-uat.ltv_db.LTV_Tran_Output
		where transaction_date < '20260101'
		AND payment_type = '1'
		AND Payment_Method is not null
		and Payment_Method not in ('HappyBean')),
		

profile_first_tran as ( -- 정기/수시 상관없이 첫번째 납부
		with tran_num as (
		SELECT *,
		row_number() over (partition by supporter_id order by transaction_date asc) as tran_nm
		FROM unhcr-kor-dl-ana-uat.ltv_db.LTV_Tran_Output
		where transaction_date < '20260101'
		)

		select *
		from tran_num 
		where tran_nm = 1),
		


--Part 2. dashboard용 데이터 

oo_donor_2025 as (
select *
from oo_transaction_2512), -- 2501~2512 중 OO 납부를 한 사람

oo_tran_num as (
select *, 
row_number() over (partition by supporter_id order by transaction_date, transaction_amount, source_id) as tran_nm
from oo_donor_2025)

-- 2025 oo gift amount based on donor's LTV: amt, count는 2025 Only가 아니라, 전체 LTV
, oo_trans_2025 as (
SELECT supporter_id, 
AVG(transaction_amount) AS ty_avg_trans_amt, 
SUM(transaction_amount) AS ty_tot_trans_amt, 
COUNT(supporter_id) AS ty_oo_count

from oo_trans_till2025
group by supporter_id)

, oo_tran_num_2 as (
SELECT a.*, 
b.ty_avg_trans_amt, 
b.ty_tot_trans_amt, 
b.ty_oo_count
FROM oo_tran_num a
LEFT JOIN oo_trans_2025 b  -- 2025까지 전체 LTV OO
ON a.supporter_id = b.supporter_id)

, first_tran as (
SELECT * FROM oo_tran_num_2 
WHERE tran_nm = 1) -- 전체 LTV OO 중의 첫번째 OO를 기준으로 분류

, add_channel as (
SELECT a.*, 
b.channel_t, 
b.channel_f
FROM first_tran a
LEFT JOIN unhcr-kor-dl-ana-uat.workspace_yura.ltv_channel_gb_2025 b
ON CONCAT(
     SPLIT(a.source_id, '/')[SAFE_OFFSET(0)],
     SPLIT(a.source_id, '/')[SAFE_OFFSET(1)]
   ) = b.channel_t
WHERE b.acq_gb = 'Acquisition'
OR b.channel_t IS NULL)

, add_don_sec as (
SELECT a.*, 
b.d_sec_kor, 
b.d_sec_eng
FROM add_channel a
LEFT JOIN unhcr-kor-dl-ana-uat.workspace_yura.ltv_don_section_2024 b
ON a.donation_section = b.d_sec_raw)

, add_channel_gb as (
SELECT *,
CASE WHEN channel_f LIKE 'F2F%' THEN 'F2F TOTAL' 
	WHEN channel_f IN ('Campaign1', 'ONLINE') THEN 'ONLINE' 
	WHEN channel_f IN ('DRTV') THEN 'DRTV'
	WHEN channel_f in ('Multi_DRTV', 'Multi_MAIL', 'DRTV_SMS Lead', 'Multi_NEWSPAPER', 'Multi_Magazine') then 'DRTV_SMS/Multi_MAIL/NEWSPAPER/Magazine'
	WHEN channel_f IN ('Multi_Digital Lead','Multi_SMS' ) THEN 'Multi_Digital/SMS' 
	WHEN channel_f IN ('HCR_COMP', 'MAIL', 'OTHER', 'MAILWITHU') THEN 'HCR_COMP/MAIL/OTHER'
	WHEN channel_f IN ('PPHCORP', 'PPHFOUNDATION', 'PPHHNWI') THEN 'PPH'
	ELSE channel_f END AS channel_gb1,
CASE WHEN (channel_f LIKE 'F2FSW%' OR channel_f LIKE 'F2FDN%' OR channel_f LIKE 'F2FKDA%' OR channel_f LIKE 'F2FLW%' OR channel_f LIKE 'F2FOM%' OR channel_f LIKE 'F2FPN%') THEN 'F2F AGENCY'
	WHEN (channel_f LIKE 'F2FIH%') THEN 'F2F IH'
	WHEN channel_f IN ('HCR_COMP', 'MAIL', 'OTHER', 'MAILWITHU') THEN 'HCR_COMP/MAIL/OTHER'
	WHEN channel_f in ('Multi_DRTV', 'Multi_MAIL','DRTV_SMS Lead','DRTV','DRRD','DRTVWN', 'Multi_NEWSPAPER', 'Multi_Magazine') then 'DRTV_T'
	WHEN channel_f IN ('Campaign1', 'ONLINE','Multi_Digital Lead','Multi_SMS') THEN 'ONLINE_T'
	WHEN channel_f IN ('PPHCORP', 'PPHFOUNDATION', 'PPHHNWI') THEN 'PPH_T'
	ELSE channel_f END AS channel_gb2,
CASE WHEN (channel_t LIKE 'F2FSW%') AND (channel_t NOT LIKE '%B2B%') THEN 'F2F SW_T'
	WHEN (channel_t LIKE 'F2FSW%') AND (channel_f LIKE '%B2B%') THEN 'F2F SW_B2B_T'
	WHEN (channel_t LIKE 'F2FDN%') THEN 'F2F DN_T'
	WHEN (channel_t LIKE 'F2FPN%') THEN 'F2F PN_T'
	WHEN (channel_t LIKE 'F2FKDA%') THEN 'F2F KDA_T'
	WHEN (channel_t LIKE 'F2FLW%') THEN 'F2F LW_T'
	WHEN (channel_t LIKE 'F2FOM%') THEN 'F2F OM_T'
	WHEN (channel_t LIKE 'F2FIH%') THEN 'F2F IH_T'
	WHEN channel_f IN ('PPHCORP', 'PPHFOUNDATION', 'PPHHNWI') THEN 'PPH_T'
	WHEN channel_f in ('Multi_DRTV', 'Multi_MAIL','DRTV_SMS Lead','DRTV','DRRD','DRTVWN', 'Multi_NEWSPAPER', 'Multi_Magazine') then 'DRTV_T'
	WHEN channel_f IN ('HCR_COMP', 'MAIL', 'OTHER','MAILWITHU') THEN 'HCR_COMP/MAIL/OTHER'
	WHEN channel_f IN ('Campaign1', 'ONLINE','Multi_Digital Lead','Multi_SMS') THEN 'ONLINE_T'
	WHEN channel_f IN ('PPHCORP', 'PPHFOUNDATION', 'PPHHNWI') THEN 'PPH_T'
	ELSE channel_f END AS channel_gb3
FROM add_don_sec)

, rg_trans_2025 as (
SELECT a.*, 
	ROUND(a.rg_tot_don / a.rg_tot_count) AS rg_gift_tyvalue
	FROM (SELECT supporter_id, 
				SUM(transaction_amount) AS rg_tot_don,
				COUNT(supporter_id) AS rg_tot_count
		  FROM rg_transaction_2512
		  GROUP BY supporter_id) a)
		  
, add_donor_info as (
SELECT a.*, 
	c.rg_gift_tyvalue,
	b.contact_date AS contact, 
	b.initial_enroll as first_gb,
	   CASE WHEN b.enroll IN ('개인') THEN 'Individual'
			WHEN b.enroll IN ('기업/단체') THEN 'Group'
			WHEN b.enroll IN ('외국인') THEN 'Foreigner'
			ELSE null END indi_corp,
		b.gender, 
		b.age, 
		b.birth_date as birth,
		CASE WHEN b.email_opt = 'N' THEN 'N'
		     ELSE 'Y' END AS email_opt,
		CASE WHEN b.mail_opt = '수신안함' THEN 'N'
			 ELSE 'Y' END AS mail_opt,
		CASE WHEN b.home_zip IS NULL THEN office_zip
	    	 WHEN b.home_zip IS NOT NULL THEN home_zip
	     	 ELSE '' END AS all_zip,
	    CASE WHEN b.home_zip LIKE '%-%' OR office_zip LIKE '%-%' THEN 'old_zip'
		     WHEN b.home_zip NOT LIKE '%-%' OR office_zip NOT LIKE '%-%' THEN 'new_zip'
		     ELSE '' END AS zip_gb
		FROM add_channel_gb a
		LEFT JOIN unhcr-kor-dl-pii-uat.mrm_db.Contacts b ON a.supporter_id = b.donor_no
		LEFT JOIN rg_trans_2025 c ON a.supporter_id = c.supporter_id )
		

, donor_info_r as (
SELECT a.*, 
	b.region 
	from add_donor_info a
	left join unhcr-kor-dl-ana-uat.workspace_joomee.zip_code_region b
	on substring(a.all_zip,1,2) = b.zip_code
	and a.zip_gb = 'old_zip'
	and b.gb = 'old_zip'
	where a.zip_gb = 'old_zip'
	
	UNION ALL
	
	SELECT a.*, 
	b.region 
	from add_donor_info a
	left join unhcr-kor-dl-ana-uat.workspace_joomee.zip_code_region b -- profile.zip_code_region 필요함
	on substring(a.all_zip,1,2) = b.zip_code
	and a.zip_gb = 'new_zip'
	and b.gb = 'new_zip'
	where a.zip_gb = 'new_zip'
	
	UNION ALL
	
	SELECT a.*,  
	'' as region 
	from add_donor_info a
	where a.zip_gb = '')
	

, first_date_oo as (
SELECT supporter_id, 
	transaction_date AS first_oo_date
	FROM (
		SELECT *,
		ROW_NUMBER()
		OVER (PARTITION BY supporter_id
		ORDER BY transaction_date, supporter_id, transaction_amount, source_id asc) AS tran_nm
		FROM oo_trans_till2025
		) 
    WHERE tran_nm = 1)
	
, cash2 as (
WITH ranked_transactions AS (
SELECT supporter_id,
transaction_date,
source_id,
ROW_NUMBER() OVER (PARTITION BY supporter_id ORDER BY transaction_date) AS row_num
FROM oo_donor_2025
WHERE source_id LIKE '%Cash%')

SELECT DISTINCT supporter_id,
CASE 
    WHEN source_id LIKE '%Cash_SMS%' THEN 'Cash_SMS'
    WHEN source_id LIKE '%Cash_DM%' THEN 'Cash_DM'
    WHEN source_id LIKE '%Cash_EMAIL%' THEN 'Cash_EMAIL'
    WHEN source_id LIKE '%Cash_MULTI%' THEN 'Cash_MULTI'
    ELSE NULL 
    END AS cash_type
FROM ranked_transactions
WHERE row_num = 1) -- 첫번째 cash 후원에 따라 분류

, oo_profile_t as (
SELECT a.supporter_id, 
	a.name, 
	a.contact, 
	a.first_gb, 
	a.indi_corp, 
	a.gender, 
	a.age,
	case when a.age < 19 then 'under 18' 
	     when a.age between 19 and 25 then '19~25'
	     when a.age between 26 and 30  then '26~30'
	     when a.age between 31 and 40  then '31~40'
	     when a.age between 41 and 50  then '41~50'
	     when a.age between 51 and 60  then '51~60'
	     when a.age > 60 then 'over 61'
	     when a.age is null then 'No data'
	     else 'No data' end age_band,
	a.birth,
	a.payment_method AS oo_cy_pay_method,
	b.first_oo_date,
	a.ty_oo_count AS oo_gift_tyfreq, -- not this year, 사실 LTV
	a.ty_tot_trans_amt AS oo_gift_tytot, -- not this year, 사실 LTV
    ROUND(a.ty_tot_trans_amt/a.ty_oo_count) AS oo_gift_tyvalue,
    a.rg_gift_tyvalue, -- this year
    case when a.rg_gift_tyvalue <= 10000 then 'under 10k' 
	     when a.rg_gift_tyvalue <= 20000 and a.rg_gift_tyvalue > 10000 then '10k~20k' 
	     when a.rg_gift_tyvalue <= 30000 and a.rg_gift_tyvalue > 20000 then '20k~30k' 
	     when a.rg_gift_tyvalue <= 50000 and a.rg_gift_tyvalue > 30000 then '30k~50k' 
	     when a.rg_gift_tyvalue <= 100000 and a.rg_gift_tyvalue > 50000 then '50k~100k' 
	     when a.rg_gift_tyvalue <= 1000000 and a.rg_gift_tyvalue > 100000 then '100k~1m' 
	     when a.rg_gift_tyvalue > 1000000 then 'over 1m'  
	     else 'No data' end rg_tygift_band,
	c.cash_type,
	a.first_month,
	CASE WHEN substring(a.first_month,1,4) = '2025' THEN 'New'
	     ELSE 'Existing' END AS donor_gb,
	FLOOR(
  (2025 - CAST(SUBSTR(a.first_month, 1, 4) AS NUMERIC)) +
  (12 - CAST(SUBSTR(a.first_month, 6, 2) AS NUMERIC)) / 12
) AS oo_life_year,
	a.channel_f, 
	a.channel_gb1,
    a.channel_gb2,	
	a.channel_gb3, 
	a.source_id,
	a.all_zip,
	CASE WHEN a.region IS NULL OR a.region = '' OR a.region = 'NA' THEN 'No data'
	    ELSE a.region end region_1,
	CASE WHEN a.region IN ('서울특별시','경기도','인천광역시') then '서울,경기,인천' 
	     WHEN a.region IN ('대구광역시','경상북도') then '대구,경북' 
	     WHEN a.region IN ('울산광역시','부산광역시','경상남도') then '부산,울산,경남'
         WHEN a.region IN ('광주광역시','전라남도', '전라북도') then '광주,전라'
         WHEN a.region IN ('대전광역시','충청남도','충청북도','세종특별자치시') then '대전,충청,세종'
         WHEN a.region IN ('강원도') then '강원'
         WHEN a.region IN ('제주특별자치도') then '제주'
         ELSE 'No data' end region_2,
    CASE WHEN a.region in ('서울특별시','경기도','인천광역시') then 'Seoul Metropolitan Area' 
	     WHEN a.region in ('대구광역시','울산광역시','부산광역시', '광주광역시','대전광역시') then 'Urban Cities' 
	     WHEN a.region in ('경상북도','경상남도','전라남도','전라북도','충청남도','충청북도','세종특별자치시','강원도','제주특별자치도') then 'Other Provinces'
	     ELSE 'No data' end region_3,
	a.email_opt, 
	a.mail_opt,
    a.d_sec_kor AS earmarking_kor, 
	a.d_sec_eng AS earmarking_eng
    FROM donor_info_r a
   	LEFT JOIN first_date_oo b ON a.supporter_id = b.supporter_id
   	LEFT JOIN cash2 c ON a.supporter_id = c.supporter_id)

, first_rg_oo_trans as (
SELECT a.supporter_id, 
	a.oo_transaction_date, 
	b.rg_transaction_date
	FROM (SELECT supporter_id, transaction_date AS oo_transaction_date
				FROM (SELECT *,
					ROW_NUMBER()
					OVER (PARTITION BY supporter_id
					ORDER BY transaction_date, supporter_id, transaction_amount, source_id asc) AS tran_nm
					FROM oo_transaction_2512) 
			WHERE tran_nm = 1
			GROUP BY supporter_id, transaction_date) a -- first oo of 2025
	LEFT JOIN
			(SELECT supporter_id, 
			transaction_date AS rg_transaction_date
				FROM (	SELECT *,
						ROW_NUMBER()
						OVER (PARTITION BY supporter_id
						ORDER BY transaction_date, supporter_id, transaction_amount, source_id asc) AS tran_nm
						FROM rg_transaction_2512) 
				WHERE tran_nm = 1
				GROUP BY supporter_id, transaction_date) b -- first rg of 2025
	ON a.supporter_id = b.supporter_id)
	
, rg_oo_donor as (
SELECT a.supporter_id, b.donor_type
		FROM donor_info_r a
		LEFT JOIN (SELECT supporter_id,
				CASE 
  WHEN rg_transaction_date IS NULL THEN 'only_oo_donor'
  WHEN PARSE_DATE('%Y%m%d', oo_transaction_date) 
       < PARSE_DATE('%Y%m%d', rg_transaction_date) THEN 'oo_to_rg_donor'
  WHEN PARSE_DATE('%Y%m%d', oo_transaction_date) 
       >= PARSE_DATE('%Y%m%d', rg_transaction_date) THEN 'rg_to_oo_donor'
  ELSE NULL
END AS donor_type
				from first_rg_oo_trans) b
		ON a.supporter_id = b.supporter_id
		GROUP BY a.supporter_id, b.donor_type)
		
, oo_profile_t2 as (
SELECT a.supporter_id, name, contact, first_gb, indi_corp, gender, age, age_band, birth, oo_cy_pay_method, first_oo_date, oo_gift_tyfreq, oo_gift_tytot, oo_gift_tyvalue,
		case when oo_gift_tyvalue <= 10000 then 'under 10k' 
		     when oo_gift_tyvalue <= 20000 and oo_gift_tyvalue > 10000 then '10k~20k' 
		     when oo_gift_tyvalue <= 30000 and oo_gift_tyvalue > 20000 then '20k~30k' 
		     when oo_gift_tyvalue <= 50000 and oo_gift_tyvalue > 30000 then '30k~50k' 
		     when oo_gift_tyvalue <= 100000 and oo_gift_tyvalue > 50000 then '50k~100k' 
		     when oo_gift_tyvalue <= 1000000 and oo_gift_tyvalue > 100000 then '100k~1m' 
		     when oo_gift_tyvalue > 1000000 then 'over 1m'  
		     else 'No data' end oo_tygift_band,
		     rg_gift_tyvalue, 
			 rg_tygift_band,
		     b.donor_type,
		     cash_type, 
			 first_month, 
			 donor_gb,
			CASE WHEN oo_life_year < 1 OR oo_life_year IS NULL THEN 0
			WHEN oo_life_year >= 1 AND oo_life_year < 2 THEN 1
			WHEN oo_life_year >= 2 AND oo_life_year < 3 THEN 2
			WHEN oo_life_year >= 3 AND oo_life_year < 4 THEN 3
			WHEN oo_life_year >= 4  THEN 4
			ELSE oo_life_year END oo_life_year,	
			channel_f, channel_gb1, channel_gb2, channel_gb3, source_id, all_zip, region_1, region_2, region_3, email_opt, mail_opt, earmarking_kor, earmarking_eng
		FROM oo_profile_t a
		LEFT JOIN rg_oo_donor b ON a.supporter_id = b.supporter_id)
		
		
, first_type_for_gb as (
SELECT supporter_id, 
			CASE WHEN payment_type = '1' THEN '수시'
			WHEN payment_type = '2' THEN '정기'
			ELSE NULL END AS payment_type, 
			payment_method, 
			transaction_date, 
			source_id, 
			donation_section, 
			b.d_sec_kor, 
			b.d_sec_eng
	FROM (
		SELECT *		
		FROM first_tran
		WHERE payment_type = '1' -- annotation this when just checking the ltv(rg+oo) first gb
		) a
		LEFT JOIN unhcr-kor-dl-ana-uat.workspace_yura.ltv_don_section_2024 b
		ON a.donation_section = b.d_sec_raw
		--WHERE tran_nm = '1' -- 아예 first_tran 테이블에서 가져옴
		)
		
, duration_er as (
WITH A AS ( -- 2025년도의 최초 oo
    SELECT supporter_id, 
	MIN(transaction_date) AS min_oo_cy_date
    FROM oo_transaction_2512
    GROUP BY supporter_id), 
	B AS ( -- 2025년도 최초 oo 이전의 마지막 oo 
    SELECT a.supporter_id, 
	MAX(b.transaction_date) AS max_tran, 
	a.min_oo_cy_date
    FROM A a
    LEFT JOIN oo_trans_till2025 b ON a.supporter_id = b.supporter_id
    WHERE a.min_oo_cy_date IS NOT NULL 
    AND b.transaction_date < a.min_oo_cy_date 
    GROUP BY a.supporter_id, a.min_oo_cy_date) 
SELECT a.supporter_id, 
b.max_tran, 
a.min_oo_cy_date, 
CASE 
  WHEN b.max_tran IS NOT NULL 
  THEN DATE_DIFF(
         PARSE_DATE('%Y%m%d', a.min_oo_cy_date),
         PARSE_DATE('%Y%m%d', b.max_tran),
         DAY
       )
  ELSE 0
END AS duration_before_er
FROM A a
LEFT JOIN B b
ON a.supporter_id = b.supporter_id)

, oo_profile_t3 as (
SELECT a.supporter_id, name, contact, first_gb, indi_corp, gender, age, age_band, birth, oo_cy_pay_method, first_oo_date, oo_gift_tyfreq, oo_gift_tytot, oo_gift_tyvalue, oo_tygift_band, rg_gift_tyvalue, rg_tygift_band, cash_type, donor_type, first_month, donor_gb, CAST(oo_life_year AS STRING) as oo_life_year,	channel_f, channel_gb1, channel_gb2, channel_gb3, a.source_id, all_zip, region_1, region_2, region_3, email_opt, mail_opt, earmarking_kor, earmarking_eng,
			CASE WHEN b.d_sec_eng = 'Earthquakes in Türkiye and Syria' THEN 'TS ER'
					WHEN b.d_sec_eng = 'Syria Emergency' THEN 'SYR ER'
					WHEN b.d_sec_eng = 'Ukraine Emergency' THEN 'UKR ER'
					WHEN b.d_sec_eng = 'Unearmarked Donations' THEN 'Unearmarked'
					WHEN b.d_sec_eng = 'Global Shelter Campaign' THEN 'Global Shelter'
					WHEN b.d_sec_eng LIKE '%Emergency%' AND ( b.d_sec_eng NOT IN ( 'Earthquakes in Türkiye and Syria', 'Syria Emergency', 'Ukraine Emergency')) THEN 'Other ER'
					ELSE 'General' END AS first_earmarking_before,
			CASE WHEN duration_before_er = 0 THEN 'None'
				WHEN duration_before_er BETWEEN 1 AND 364 THEN 'less than 1yr'
				WHEN duration_before_er BETWEEN 365 AND 729 THEN '1yr'
				WHEN duration_before_er BETWEEN 730 AND 1097 THEN '2yrs'
				WHEN duration_before_er >= 1098 THEN 'Over 3yrs'
				ELSE NULL END AS duration_before_er,
				b.payment_method AS ltv_payment_method
		FROM oo_profile_t2 a
		LEFT JOIN first_type_for_gb b ON a.supporter_id = b.supporter_id
		LEFT JOIN duration_er c	ON a.supporter_id = c.supporter_id)
		

, cross_sell as (
SELECT c.supporter_id AS donor_no, 
CASE WHEN rg_donor IS NOT NULL THEN 'Cross-sell donor'
	 ELSE NULL END AS donor_type_ty
FROM (SELECT DISTINCT a.supporter_id, -- 2025 oo인데
			b.supporter_id AS rg_donor -- 2025 rg도 한 사람
			FROM oo_donor_2025 a
			LEFT JOIN (SELECT DISTINCT supporter_id FROM rg_transaction_2512) b
			ON a.supporter_id = b.supporter_id) c)
			
, oo_donor_2025_cash as (
SELECT *
FROM oo_transaction_2512 
WHERE source_id LIKE 'Cash%' 

)

, cash as (
SELECT a.supporter_id,
	  CASE WHEN source_id LIKE '%Cash_SMS%' THEN 'Cash_SMS'
	       WHEN source_id LIKE '%Cash_DM%' THEN 'Cash_DM'
		   WHEN source_id LIKE '%Cash_EMAIL%' THEN 'Cash_EMAIL'
		   WHEN source_id LIKE '%Cash_MULTI%' THEN 'Cash_MULTI'
		   ELSE null END AS cash_type
FROM oo_donor_2025_cash a
GROUP BY supporter_id, cash_type)


, cash_pivot as (
SELECT supporter_id,
CASE WHEN cash_sms > 0 THEN 'cash_sms' ELSE '' END AS ty_cash_sms,
CASE WHEN cash_dm > 0 THEN 'cash_dm' ELSE '' END AS ty_cash_dm,
CASE WHEN cash_email > 0 THEN 'cash_email' ELSE '' END AS ty_cash_email,
CASE WHEN cash_multi > 0 THEN 'cash_multi' ELSE '' END AS ty_cash_multi,
CASE WHEN (cash_sms + cash_dm + cash_email + cash_multi) > 1 THEN 'cash_more' ELSE '' END AS cash_more
FROM (SELECT supporter_id,
	  COUNT(CASE WHEN cash_type = 'Cash_SMS' THEN supporter_id END) AS cash_sms,
	  COUNT(CASE WHEN cash_type = 'Cash_DM' THEN supporter_id END) AS cash_dm,
	  COUNT(CASE WHEN cash_type = 'Cash_EMAIL' THEN supporter_id END) AS cash_email,
	  COUNT(CASE WHEN cash_type = 'Cash_MULTI' THEN supporter_id END) AS cash_multi
	  FROM cash
	  GROUP BY supporter_id) cash_p)
	  
	  
, oo_profile_2025 as (
SELECT a.supporter_id, 
	a.name, 
	a.contact, 
	a.first_gb, 
	a.indi_corp, 
	a.gender, 
	a.age, 
	a.age_band, 
	a.birth, 
	a.oo_cy_pay_method, 
	a.first_oo_date, 
	a.oo_gift_tyfreq, 
	a.oo_gift_tytot,
	a.oo_gift_tyvalue, 
	a.oo_tygift_band, 
	a.rg_gift_tyvalue, 
	a.rg_tygift_band,
	a.donor_type AS donor_type_origin,
	CASE WHEN b.donor_type_ty IS NULL THEN 'OO only donor'
	     ELSE b.donor_type_ty END donor_type_ty,
	a.cash_type,
	CASE WHEN c.cash_more = 'cash_more' THEN 'Cash_MORE'
	     ELSE a.cash_type END AS cash_type_2,
	a.first_month, 
	a.donor_gb, 
	a.oo_life_year,
	CASE WHEN a.oo_life_year = '0' THEN 'New Active'
		 WHEN a.oo_life_year = '1' THEN 'Over 1yr'
		 WHEN a.oo_life_year = '2' THEN 'Over 2yrs'
		 WHEN a.oo_life_year = '3' THEN 'Over 3yrs'
		 WHEN a.oo_life_year = '4' THEN 'Over 4yrs'
		 ELSE a.oo_life_year END AS life_year,
	a.channel_f, 
	a.channel_gb1, 
	a.channel_gb2, 
	a.channel_gb3, 
	a.source_id,
	a.all_zip, 
	a.region_1, 
	a.region_2, 
	a.region_3, 
	a.email_opt, 
	a.mail_opt,
	a.earmarking_kor, 
	a.earmarking_eng,
	c.ty_cash_sms, 
	c.ty_cash_dm, 
	c.ty_cash_email, 
	c.ty_cash_multi, 
	c.cash_more,
	a.first_earmarking_before,	
	CASE WHEN a.duration_before_er IS NOT NULL THEN a.duration_before_er
		 ELSE 'No TSER donor' END AS duration_before_er, 

	CASE WHEN oo_cy_pay_method NOT IN ('Credit Card', 'Virtual Account', 'Wire Transfer', 'Real Time Wire Transfer', 'CMS') THEN 'Others'	
    ELSE oo_cy_pay_method END AS oo_cy_pay_method_gb 

	FROM oo_profile_t3 a 
	LEFT JOIN cross_sell b ON a.supporter_id = b.donor_no 
	LEFT JOIN cash_pivot c ON a.supporter_id = c.supporter_id)
	

-- Final Raw Data for Dashboard	
SELECT
		CASE WHEN channel_gb2 = 'DRTV_T' THEN 'DRTV'
			 WHEN channel_gb2 = 'Multi_Channel_T' THEN 'Multi_Channel'
			 WHEN channel_gb2 = 'HCR_COMP/MAIL/OTHER' OR channel_gb2 = 'HOPETV' THEN 'Others'
			 WHEN channel_gb2 = 'ONLINE_T' THEN 'ONLINE'
			 WHEN channel_gb2 = 'PPH_T' THEN 'PPH'
			 WHEN channel_gb2 = 'F2F AGENCY' OR channel_gb2 = 'F2F_AGENCY' THEN 'F2F AGENCY'
			 ELSE channel_gb2 END AS channel_s,
		channel_f AS channel_f_wncash,
		CASE WHEN cash_type_2 IS NULL THEN 'No Cash donor'
			 ELSE cash_type_2 END AS cash_type_2,
		donor_type_TY, 
		donor_type_origin,
		donor_gb,
		oo_TYgift_band, 
		rg_TYgift_band,
		age_band, 
		gender, 
		region_3, 
		email_opt, 
		mail_opt,
		life_year,
		earmarking_eng, 
		COUNT(supporter_id) AS count,
		SUM(oo_gift_tytot) AS tot_oo_TYgift,
		SUM(oo_gift_tyfreq) AS tot_oo_gift_tyfreq,
		SUM(age) AS tot_avg_age,
		--cp_gb AS er_check,
		first_earmarking_before, 
		duration_before_er AS oo_donation_freq, 
		oo_cy_pay_method_gb AS oo_cy_pay_method
		FROM oo_profile_2025 a
		GROUP BY channel_gb2, channel_f, cash_type_2, donor_type_ty, donor_type_origin, donor_gb, oo_tygift_band, rg_tygift_band, age_band, gender, region_3, email_opt, mail_opt, life_year, earmarking_eng, --cp_gb, 
		oo_cy_pay_method_gb, first_earmarking_before, duration_before_er;
		
		
		
Step 2. 2022-2025 aggregated table에 INSERT

insert into unhcr-kor-dl-ana-uat.workspace_joomee.donor_profile_oo_2022_2025
select 
'2025' as Year,
channel_s,
channel_f_wncash,
cash_type_2 as cash_donor_type_TY,
donor_type_TY,
donor_type_origin,
donor_gb,
oo_TYgift_band,
rg_TYgift_band,
age_band,
gender,
region_3,
email_opt,
mail_opt,
life_year,
earmarking_eng,
cast(count as numeric),
tot_oo_TYgift,
cast(tot_oo_gift_tyfreq as numeric),
tot_avg_age,
oo_cy_pay_method,
oo_cy_pay_method as oo_cy_pay_method_combined, -- for PBI combining
  CASE 
    WHEN oo_TYgift_band = 'under 10k' THEN 1
    WHEN oo_TYgift_band = '10k~20k' THEN 2
    WHEN oo_TYgift_band = '20k~30k' THEN 3
    WHEN oo_TYgift_band = '30k~50k' THEN 4
    WHEN oo_TYgift_band = '50k~100k' THEN 5
    WHEN oo_TYgift_band = '100k~1m' THEN 6
    WHEN oo_TYgift_band = 'over 1m' THEN 7
    ELSE 999
  END as oo_TYgift_band_order, -- for PBI ordering
 CASE 
    WHEN age_band = 'under 18' THEN 1
    WHEN age_band = '19~25' THEN 2
    WHEN age_band = '26~30' THEN 3
    WHEN age_band = '31~40' THEN 4
    WHEN age_band = '41~50' THEN 5
    WHEN age_band = '51~60' THEN 6
    WHEN age_band = 'over 61' THEN 7
    WHEN age_band = 'No data' THEN 8
    ELSE 999
  END as age_band_order, -- for PBI ordering
CASE 
    WHEN life_year = 'New Active' THEN 1
    WHEN life_year = 'Over 1yr' THEN 2
    WHEN life_year = 'Over 2yrs' THEN 3
    WHEN life_year = 'Over 3yrs' THEN 4
    WHEN life_year = 'Over 4yrs' THEN 5
    ELSE 999
  END as life_year_band_order, -- for PBI ordering
CASE 
    WHEN region_3 = 'Seoul Metropolitan Area' THEN 1
    WHEN region_3 = 'Urban Cities' THEN 2
    WHEN region_3 = 'Other Provinces' THEN 3
    WHEN region_3 = 'No data' THEN 4
    ELSE 999
END  as region_3_order -- for PBI ordering

  FROM `unhcr-kor-dl-ana-uat.workspace_joomee.donor_profile_oo_2025_rev` 