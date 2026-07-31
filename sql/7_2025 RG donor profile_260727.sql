-- Donor Profile (20260313 Update)


-- 1. 기본 데이터 확인 (income_2025)

-- income_2025.csv 파일 google storage 통해서 gcp에 업로드 완료 (unhcr-kor-dl-ana-uat.workspace_joomee.income_2025)

/*
SELECT COUNT(DISTINCT donor_no) AS unique_donors 
FROM unhcr-kor-dl-ana-uat.workspace_joomee.income_2025; -- 229,633

SELECT round(AVG(cast(donation_spend as numeric))) AS avg_donation_online 
FROM unhcr-kor-dl-ana-uat.workspace_joomee.income_2025; -- 20,895
*/


-- 2. 25.12월말 기준 active 기부자 프로파일 생성 (donor_no, name, submit_date, start_month, gift_amount, channel_t)


-- create or replace table unhcr-kor-dl-ana-uat.workspace_joomee.donor_profile_rg_2025 as

with active_donors as (
select donor_no, name, submit_date, start_month, gift_amount, 
CONCAT(
    SPLIT(campaign_raw, '/')[SAFE_OFFSET(0)],
    SPLIT(campaign_raw, '/')[SAFE_OFFSET(1)]
) AS channel_pre, -- 이게 원래 channel_t여야 하는데 잘 안 맞음 -> channel_excl_upgrade로 사용
count(*) over (partition by donor_no) as pledge_count,
row_number() over (partition by donor_no order by submit_date desc) as rn
from unhcr-kor-dl-pii-uat.mrm_db.RG_Pledges
where (submit_date is null or submit_date <= '2025-12-31')
and (all_end_date is null or all_end_date > '2025-12-31')
and campaign_raw is not null
and payment_method in ('CMS', '신용카드', 'NPay', 'KakaoPay')
and start_month is not null
and (end_month is null or end_month > '2025-12')
and oneoff_check is null
and campaign_raw not like 'UPGRADE%'
and campaign_raw not like 'ONEOFF%'
and campaign_raw not like 'UP_%'
and campaign_raw not like 'PPH%'),

active_head_profile_2025 as (
select distinct donor_no, name, channel_pre, pledge_count
from active_donors
where rn=1),

donor_info_rg_2025_pre_zip as (
select a.donor_no, a.name, a.pledge_count,
b.contact_date as sign_up_date,
b.initial_enroll as first_gb,
case when b.enroll = '개인' then 'Individual'
	 WHEN b.enroll = '기업/단체' THEN 'Group'
     WHEN b.enroll = '외국인' THEN 'Foreigner'
     ELSE NULL 
     END AS indi_corp,
    CASE 
        WHEN b.mvd_type LIKE 'MVD%' AND b.mvd_type <> 'MVD-PP' THEN 'MVD'
        ELSE NULL 
    END AS mvd_gb,
b.gender,
b.age-1 as age, -- 추출시점 기준으로 전년도 나이이므로 -1
b.birth_date as birth,
b.payment_method,
b.first_month as first_payment,
b.start_month as s_month,
b.rg_amount as gift_amount,
b.tot_amt as tot_gift_amount,
b.tot_tran as tot_gift_tran,
--a.channel_t, 
c.channel_excl_upgrade as channel_t,
b.campaign_raw,
  CASE  WHEN b.age-1 BETWEEN 1 AND 18 THEN 'under 18'
        WHEN b.age-1 BETWEEN 19 AND 25 THEN '19~25'
        WHEN b.age-1 BETWEEN 26 AND 30 THEN '26~30'
        WHEN b.age-1 BETWEEN 31 AND 40 THEN '31~40'
        WHEN b.age-1 BETWEEN 41 AND 50 THEN '41~50'
        WHEN b.age-1 BETWEEN 51 AND 60 THEN '51~60'
        WHEN b.age-1 >= 61 THEN 'over 61'
        WHEN b.age IS NULL THEN 'No data'
        ELSE 'No data' 
        end as age_band,
CASE 
    WHEN CAST(b.rg_amount AS INT64) <= 10000 THEN 'under 10,000'
    WHEN CAST(b.rg_amount AS INT64) BETWEEN 10001 AND 15000 THEN '10,001~15,000'
    WHEN CAST(b.rg_amount AS INT64) BETWEEN 15001 AND 20000 THEN '15,001~20,000'
    WHEN CAST(b.rg_amount AS INT64) BETWEEN 20001 AND 30000 THEN '20,001~30,000'
    WHEN CAST(b.rg_amount AS INT64) BETWEEN 30001 AND 50000 THEN '30,001~50,000'
    WHEN CAST(b.rg_amount AS INT64) > 50000 THEN 'over 50,001'
    ELSE 'No data'
END AS gift_band,
FLOOR(DATE_DIFF(DATE '2025-12-31', DATE(b.first_month || '-01'), MONTH) / 12) AS life_year_raw,
CASE 
    WHEN FLOOR(DATE_DIFF(DATE '2025-12-31', DATE(b.first_month || '-01'), MONTH) / 12) < 1 THEN 'New Active'
    WHEN FLOOR(DATE_DIFF(DATE '2025-12-31', DATE(b.first_month || '-01'), MONTH) / 12) < 2 THEN 'Over 1yr'
    WHEN FLOOR(DATE_DIFF(DATE '2025-12-31', DATE(b.first_month || '-01'), MONTH) / 12) < 3 THEN 'Over 2yrs'
    WHEN FLOOR(DATE_DIFF(DATE '2025-12-31', DATE(b.first_month || '-01'), MONTH) / 12) < 4 THEN 'Over 3yrs'
    ELSE 'Over 4yrs'
END AS life_year_band,
--CASE WHEN b.email_opt = 'N' THEN 'N' ELSE 'Y' END AS email_opt,
--CASE WHEN b.mail_opt = '수신안함' THEN 'N' ELSE 'Y' END AS mail_opt,
CASE WHEN b.email_opt = 'N' THEN FALSE ELSE TRUE END AS email_opt,
CASE WHEN b.mail_opt = '수신안함' THEN FALSE ELSE TRUE END AS mail_opt,
b.home_zip,
b.office_zip,
--COALESCE(b.home_zip, b.office_zip, '') AS all_zip,
CASE 
        WHEN b.home_zip LIKE '%-%' OR b.office_zip LIKE '%-%' THEN 'old_zip'
        WHEN b.home_zip NOT LIKE '%-%' OR b.office_zip NOT LIKE '%-%' THEN 'new_zip'
        ELSE '' 
    END AS zip_gb
from active_head_profile_2025 a 
left join unhcr-kor-dl-pii-uat.mrm_db.Contacts b
on a.donor_no = b.donor_no
left join `unhcr-kor-dl-ana-uat.workspace_joomee.channel_gb_2025` c
on a.channel_pre = c.channel_t  
and c.acq_gb = 'Existing'),


donor_info_rg_2025 as (
select a.donor_no, a.name, a.pledge_count,
a.sign_up_date,
a.first_gb,
a.indi_corp,
a.mvd_gb,
a.gender,
a.age, 
a.birth,
a.payment_method,
a.first_payment,
a.s_month,
a.gift_amount,
a.tot_gift_amount,
a.tot_gift_tran,
a.channel_t,
--a.channel,
a.campaign_raw,
a.age_band,
a.gift_band,
a.life_year_raw,
a.life_year_band,
a.email_opt,
a.mail_opt,
LPAD(
    COALESCE(a.home_zip, a.office_zip, ''),
    IF(zip_gb = 'new_zip', 5, LENGTH(COALESCE(a.home_zip, a.office_zip, ''))),
    '0'
) AS all_zip,
a.zip_gb
from donor_info_rg_2025_pre_zip a),



upgrade_info as (
select donor_no, 
count(donor_no) as up_count,
round(AVG(cast(donation_spend as numeric))) as avg_up_amt,
sum(cast(donation_spend as numeric)) as tot_up_amt
from unhcr-kor-dl-ana-uat.workspace_joomee.income_2025
where channel_raw like '%UP%'
group by donor_no),

donor_info_rg_2025_add1 as (
select a.*,
case when b.up_count > 0 then 'RG_Upgrade'
	 else 'No_Upgrade' end as upgrade,
b.up_count,
b.avg_up_amt,
b.tot_up_amt
from donor_info_rg_2025 a
left join upgrade_info b
on a.donor_no = b.donor_no),

cash_donor as (
select donor_no,
CASE 
    WHEN channel_raw LIKE '%Cash_SMS%' THEN 'Cash_SMS'
    WHEN channel_raw LIKE '%Cash_DM%' THEN 'Cash_DM'
    WHEN channel_raw LIKE '%Cash_EMAIL%' THEN 'Cash_EMAIL'
    WHEN channel_raw LIKE '%Cash_MULTI%' THEN 'Cash_MULTI'
    ELSE 'No_cash_donor' 
    END AS cash_type,
    COUNT(donor_no) AS cash_count, 
    ROUND(AVG(cast(donation_spend as numeric))) AS avg_cash_amt,
	sum(cast(donation_spend as numeric)) as tot_cash_amt
	from unhcr-kor-dl-ana-uat.workspace_joomee.income_2025
	where channel_raw like '%Cash%'
	group by donor_no, cash_type),
	
	
donor_info_rg_2025_add2 as (
select a.*,
b.cash_type,
b.cash_count,
b.avg_cash_amt,
b.tot_cash_amt
from donor_info_rg_2025_add1 a 
left join cash_donor b 
on a.donor_no = b.donor_no),


zip_region as (
select a.donor_no,
COALESCE(b.region, '') AS region
from donor_info_rg_2025 a
left join `unhcr-kor-dl-ana-uat.workspace_joomee.zip_code_region` b
on substring(a.all_zip,1,2) = b.zip_code 
and a.zip_gb = b.gb),


donor_info_rg_2025_add3 as (
select a.*,
b.region
from donor_info_rg_2025_add2 a 
left join zip_region b 
on a.donor_no = b.donor_no),

donor_info_rg_2025_add4 as (
select a.*,
CASE WHEN region IS NULL OR region = '' OR region = 'NA' THEN 'No data'
     ELSE region 
     END as region_1,
CASE 
    WHEN region IN ('서울특별시','경기도','인천광역시') THEN '서울,경기,인천' 
    WHEN region IN ('대구광역시','경상북도') THEN '대구,경북' 
    WHEN region IN ('울산광역시','부산광역시','경상남도') THEN '부산,울산,경남'
    WHEN region IN ('광주광역시','전라남도', '전라북도') THEN '광주,전라'
    WHEN region IN ('대전광역시','충청남도','충청북도','세종특별자치시') THEN '대전,충청,세종'
    WHEN region IN ('강원도') THEN '강원'
    WHEN region IN ('제주특별자치도') THEN '제주'
    ELSE 'No data' 
    END as region_2,
CASE 
    WHEN region IN ('서울특별시','경기도','인천광역시') THEN 'Seoul Metropolitan Area' 
    WHEN region IN ('대구광역시','울산광역시','부산광역시', '광주광역시','대전광역시') THEN 'Urban Cities' 
    WHEN region IN ('경상북도','경상남도','전라남도','전라북도','충청남도','충청북도','세종특별자치시','강원도','제주특별자치도') THEN 'Other Provinces'
    ELSE 'No data' 
    END as region_3
from donor_info_rg_2025_add3 a),


donor_info_rg_2025_add5 as (
select a.*,
CASE 
        WHEN channel_t LIKE 'F2F%' THEN 'F2F TOTAL' 
        WHEN channel_t = 'ONLINE' THEN 'Online' 
        WHEN channel_t = 'DRTV' THEN 'DRTV' 
        WHEN channel_t IN ('Multi_DRTV', 'Multi_MAIL', 'DRTV_SMS Lead', 'Multi_NEWSPAPER', 'Multi_Magazine') 
             THEN 'DRTV_SMS/Multi_MAIL/NEWSPAPER/Magazine'
        WHEN channel_t IN ('Multi_Digital Lead','Multi_SMS') THEN 'Multi_Digital/SMS' 
        WHEN channel_t IN ('HCR_COMP', 'MAIL', 'OTHER') THEN 'HCR_COMP/MAIL/OTHER'
        ELSE channel_t 
    END as channel_g1,
CASE 
        WHEN channel_t LIKE 'F2F SW%' OR channel_t LIKE 'F2F DN%' OR 
             channel_t LIKE 'F2F KDA%' OR channel_t LIKE 'F2F LW%' OR 
             channel_t LIKE 'F2F OM%' OR channel_t LIKE 'F2F PN%' 
			 or channel_t like 'F2F_AGENCY'
             THEN 'F2F AGENCY'
        WHEN channel_t LIKE 'F2F IH%' THEN 'F2F IH'
        WHEN channel_t IN ('HCR_COMP', 'MAIL', 'OTHER') THEN 'Others'
        WHEN channel_t IN ('HopeTV', 'Multi_Digital Lead','Multi_SMS') THEN 'ONLINE' 
        WHEN channel_t IN ('Multi_DRTV', 'Multi_MAIL','DRTV_SMS Lead','DRTV','DRRD','DRTVWN', 
                           'Multi_NEWSPAPER', 'Multi_Magazine') THEN 'DRTV'
        ELSE channel_t 
    END as channel_g2,
CASE 
        WHEN channel_t LIKE 'F2F_SW%' AND channel_t NOT LIKE '%B2B%' THEN 'F2F SW_Street'
        WHEN channel_t LIKE 'F2F_SW%' AND channel_t LIKE '%B2B%' THEN 'F2F SW_B2B'
        WHEN channel_t LIKE 'F2F_DN%' THEN 'F2F DN'
        WHEN channel_t LIKE 'F2F_PN%' THEN 'F2F PN'
        WHEN channel_t LIKE 'F2F_KDA%' THEN 'F2F KDA'
        WHEN channel_t LIKE 'F2F_LW%' THEN 'F2F LW'
        WHEN channel_t LIKE 'F2F_OM%' THEN 'F2F OM'
        WHEN channel_t LIKE 'F2F_IH%' THEN 'F2F IH'
		when channel_t like 'F2F_AGENCY' then 'F2F AGENCY'
        ELSE 'Not F2F Agency'
    END as channel_g3,
CASE 
        WHEN channel_t LIKE 'F2F_SW%' THEN 'F2F SW'
        WHEN channel_t LIKE 'F2F_DN%' THEN 'F2F DN'
        WHEN channel_t LIKE 'F2F_PN%' THEN 'F2F PN'
        WHEN channel_t LIKE 'F2F_KDA%' THEN 'F2F KDA'
        WHEN channel_t LIKE 'F2F_LW%' THEN 'F2F LW'
        WHEN channel_t LIKE 'F2F_OM%' THEN 'F2F OM'
        WHEN channel_t LIKE 'F2F_IH%' THEN 'F2F IH'      
        ELSE channel_t 
    END as channel_g4
from donor_info_rg_2025_add4 a),


oo_donor as (
select donor_no, 
count(*) as oo_count,
avg(cast(donation_spend as numeric)) as avg_oo_gift,
sum(cast(donation_spend as numeric)) as tot_oo_gift
from unhcr-kor-dl-ana-uat.workspace_joomee.income_2025
where donor_type = '수시'
group by donor_no),


donor_info_rg_2025_add6 as (
select a.*,
CASE 
    WHEN o.oo_count > 0 THEN 'cross_sell'
    ELSE '' 
    END as cross_sell,
CASE 
        WHEN o.avg_oo_gift <= 10000 THEN 'under 10,000'
        WHEN o.avg_oo_gift BETWEEN 10001 AND 50000 THEN '10,001~50,000'
        WHEN o.avg_oo_gift BETWEEN 50001 AND 100000 THEN '50,001~100,000'
        WHEN o.avg_oo_gift BETWEEN 100001 AND 500000 THEN '100,001~500,000'
        WHEN o.avg_oo_gift BETWEEN 500001 AND 1000000 THEN '500,001~1,000,000'
        WHEN o.avg_oo_gift > 1000000 THEN 'over 1,000,001'
        ELSE 'rg_only_donor'
    END as avg_oo_gift_band,
o.oo_count as oo_count
from donor_info_rg_2025_add5 a
left join oo_donor o
on a.donor_no = o.donor_no)

select '2025' as year,
channel_g2, 
channel_g3, 
channel_g4, 
channel_t, 
--channel,
gift_band, 
age_band, 
gender, 
region_3, 
email_opt, 
mail_opt, 
mvd_gb, 
upgrade, 
cross_sell, 
life_year_band as life_year, 
case when cash_type is not null then cash_type
else 'No_cash_donor' END as cash_type, 
COUNT(*) as count, 
sum(age) AS tot_avg_age, 
sum(cast(gift_amount as numeric)) AS tot_gift_amt, 
sum(avg_up_amt)as avg_up_amt, 
sum(avg_cash_amt) as avg_cash_amt 
from donor_info_rg_2025_add6
group by year, channel_g2, channel_g3, channel_g4, channel_t, gift_band, age_band, gender, region_3, email_opt, mail_opt, mvd_gb, upgrade, cross_sell, life_year, cash_type;




Step 2. 유라샘 기존 빅쿼리 테이블에 추가 (data type 변환 필요)

INSERT INTO `unhcr-kor-dl-ana-uat.workspace_yura.donor_profile`
SELECT
CAST(year AS INT64) AS year,
channel_g2,
channel_g3,
channel_g4,
channel_t,
gift_band,
age_band,
gender,
region_3,
email_opt,
mail_opt,
mvd_gb,
upgrade,
cross_sell,
life_year,
cash_type,
count,
CAST(tot_avg_age AS INT64) AS tot_avg_age,
CAST(tot_gift_amt AS INT64) AS avg_gift_amt,
CAST(avg_up_amt AS STRING) AS avg_up_amt,
CAST(avg_cash_amt AS STRING) AS avg_cash_amt
FROM `unhcr-kor-dl-ana-uat.workspace_joomee.donor_profile_rg_2025`;


Step 3. 필요시 수기 조정 작업 
-- Online에서 오류 수치(금액이 10억원, 9,999,999억원인 약정)가 발견되어 수기로 지워줌

-- case 1
select *
from unhcr-kor-dl-ana-uat.workspace_yura.donor_profile
where Year = 2025
and channel_g2 = 'ONLINE'
and avg_gift_amt = 1000000000;

DELETE FROM `unhcr-kor-dl-ana-uat.workspace_yura.donor_profile`
WHERE Year = 2025
  AND channel_g2 = 'ONLINE'
  AND avg_gift_amt = 1000000000;
  
  
-- case 2
select *
from unhcr-kor-dl-ana-uat.workspace_yura.donor_profile
where Year = 2025
and channel_g2 = 'ONLINE'
and avg_gift_amt = 9999999;

DELETE FROM `unhcr-kor-dl-ana-uat.workspace_yura.donor_profile`
WHERE Year = 2025
  AND channel_g2 = 'ONLINE'
  AND avg_gift_amt = 9999999;