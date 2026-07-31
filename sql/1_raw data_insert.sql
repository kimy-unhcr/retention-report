Step 1. 데이터 클렌징: 오류값 있는지 확인 (오류 발견시 DCU 등에 수정 요청)

SELECT *
FROM `unhcr-kor-dl-pii-prod.mrm_db.RG_Pledges`
where submit_date between '2026-06-01' and '2026-06-30'
and campaign_raw is null
and name not like '%테스트%'
and name not like '%test%'

SELECT *
FROM `unhcr-kor-dl-ana-prod.mrm_db.RG_Pledges`
where
replace(campaign_raw, '/', '') like 'F2FIH%'
and submit_date between '2026-06-01' and '2026-06-30'
and campaign_raw not like '%Reactivation%' -- 재개콜 TM이 아니라 후원자 본인의 자발 인입콜로 재개될 경우, 캠페인회차에 Reactivation 안 붙을 수 있음 


Step 2. Bella VIEW replace

create or replace view `unhcr-kor-dl-ana-prod.DataMarts.korea_vw_dim_commitment` as (

WITH transactions AS (
SELECT
	C.pledge_uid
	,'KRW' AS transaction_currency --- changed
	--,CASE when  T.CloseDate is null then T.Date_Authorised__c 	 else  T.CloseDate END 
  ,date (T.send_date) AS transaction_date
	,CAST(T.tran_amount AS NUMERIC) AS transaction_amount
	,RANK() OVER (PARTITION BY C.pledge_uid ORDER BY date (T.send_date) ASC, T.tran_uid ASC) AS txn_rank_asc
	,RANK() OVER (PARTITION BY C.pledge_uid ORDER BY date (T.send_date) DESC, T.tran_uid DESC) AS txn_rank_desc
  
FROM 	  `unhcr-kor-dl-ana-prod.mrm_db.RG_Pledges` 	C
LEFT JOIN 	 `unhcr-kor-dl-ana-prod.mrm_db.Transactions`   T
    ON 	C.pledge_uid = T.pledge_uid ---T.npsp__CommitmentId__c
)
-------------------------------------
---, final as (
SELECT
	R.pledge_uid AS commitment_id --- confirmed
	,R.donor_no AS supporter_id
	,R.submit_date  AS commitment_date
	,R.start_month
	,R.start_date
	,R.end_month
	,R.end_check --- need for donor table
	,R.all_end_date --- need for donor table
	,R.payment_method --- need for donor table
	,R.org --- need for donor table
	,P.name --- need for donor table 
	,P.cancel_date as cancel_date_contact_level --- need for donor table
	,P.all_end_date as all_end_date_contact_level --- need for donor table
	,P.payment_method as payment_method_contact_level --- need for donor table
	,P.cancel_route as cancel_route_contact_level --- need for donor table
	,P.contact_date --- need for donor table
	,CASE 
			WHEN  R.frequency = 1 THEN 'Monthly'
			WHEN  R.frequency = 12 THEN 'Annual'
      WHEN  R.frequency is NULL THEN 'check' ----- need to come back to this; 
			ELSE 'Other'
	END AS commitment_frequency
	,'KRW' AS currency_code 
	,R.donation_section
	,R.user_type1 as developer_old
	,R.user_type2 as oneoff_check
	,R.entered
    ,R.campaign_raw as campaign_id
	,CONCAT(
    SPLIT(R.campaign_raw, '/')[SAFE_OFFSET(0)],
    SPLIT(R.campaign_raw, '/')[SAFE_OFFSET(1)]
) AS channel_t ----- --- need for donor table 
	,C.campaign AS commitment_description ---- no campaign name 
	,FT.transaction_amount AS original_commitment_amount
	,LT.transaction_amount AS commitment_amount
	,R.pledge_active AS commitment_status --- can also use Status (1,2,3) or pledge_status (in korean)
	,R.status
	,R.pledge_status
	,case when R.pledge_status = '종료' then 'end'
							when R.pledge_status = '진행' then 'progress'
							when R.pledge_status = '일시중지' then 'pause'
							when R.pledge_status = '대기' then '?' end as pledge_status_eng
	,R.rg_amount as gift_amount --- need for donor table
	,NULL AS commitment_last_changed_date --- R.unig__Status_Date__c ; couldn't find equivalnet field
  ----------------------------------------------
  /*
  what to do with frequency NULL??
  */
	,CASE 
		WHEN 	R.end_date IS NOT NULL THEN R.end_date
        WHEN 	R.frequency = 1 
				AND LT.transaction_date < DATE_SUB(CURRENT_DATE(), INTERVAL 3 MONTH)
				THEN DATE_ADD(LT.transaction_date, INTERVAL 3 MONTH)
		WHEN 	R.frequency = 12
				AND LT.transaction_date < DATE_SUB(CURRENT_DATE(), INTERVAL 13 MONTH)
				THEN DATE_ADD(LT.transaction_date, INTERVAL 13 MONTH) 
    END AS commitment_end_date

    ---------------------------------------------------
	,P.cancel_reason AS cancellation_reason   ---npsp__ClosedReason__c; couldn't see equivalent  in RG_Pledge
	,CAST(R.submit_date AS TIMESTAMP) AS created_date
	,NULL AS modified_date ---CAST(R.LastModifiedDate AS TIMESTAMP)
	,R.cancel_cal_date

	,CURRENT_TIMESTAMP() AS dl_load_date


  
FROM  `unhcr-kor-dl-ana-prod.mrm_db.RG_Pledges`   	R  
LEFT JOIN  `unhcr-kor-dl-ana-prod.mrm_db.Campaign` 	C
			ON 	R.campaign_raw = C.campaign_raw
LEFT JOIN `unhcr-kor-dl-pii-prod.mrm_db.Contacts`  P
			ON R.donor_no = P.donor_no
LEFT JOIN 	transactions 																			FT
			ON 	R.pledge_uid = FT.pledge_uid
			AND FT.txn_rank_asc = 1

LEFT JOIN 	transactions 																			LT
			ON 	R.pledge_uid = LT.pledge_uid
			AND LT.txn_rank_desc = 1

where R.user_type2 <> '수시'
or R.user_type2 is null

)


Step 3. Check & Insert

declare review_month date default date '2026-06-01'; -- report 해당월 1일을 입력


/* step 2 & 4
insert into 파트를 코멘트 아웃한 뒤, select 결과부터 확인하고
수치/구조가 정상적이면, 언코멘트한 뒤 전체 쿼리를 돌려 report_raw_native 테이블에 insert
*/

/*
insert into unhcr-kor-dl-ana-uat.workspace_joomee.retention_report_raw_native
(
  period,
  month_first,
  channel_sitecode,
  channel_gb,
  recruit_channel,
  f2f_type_street_b2b,
  f2f_channel_gb,
  new_donor,
  active_donor,
  lapsed_donor,
  lapsed_3m,
  lapsed_12m,
  reactivation_donor,
  conversion_donor
)
*/


-- PLEDGE BASE: used for active, new, reactivation, conversion
with 

 pledge as (
  select
  x.org,
  x.supporter_id, -- donor_no
  x.commitment_id, 
  x.name, 
  x.pledge_status, 
  x.pledge_status_eng,
  x.commitment_status, -- pledge_active
  x.end_check,
  x.payment_method, 
  x.commitment_date,  -- submit_date
  row_number() over (partition by x.supporter_id order by x.commitment_date asc,  x.start_month asc) as pledge_nm,
  x.all_end_date,
  x.start_month, 
  x.end_month, 
  x.commitment_frequency, 
  x.donation_section, 
  x.developer_old, 
  x.oneoff_check, 
  x.gift_amount, 
  x.campaign_id, -- campaign_raw
  x.channel_t,
  x.entered,
  x.cancel_cal_date,
  case when x.status = '3' then 'Y' else 'N' end as cancel_status,
  b.channel_excl_upgrade as channel,
  b.acq_gb ,
  b.new_site_code_acq,
  b.channel as channel_gb

from unhcr-kor-dl-ana-prod.DataMarts.korea_vw_dim_commitment  x
left join unhcr-kor-dl-ana-prod.workspace_joomee.channel_gb_2025 b 
            on x.channel_t = b.channel_t  
            and b.acq_gb = 'Existing' -- not to have duplicates

WHERE NOT REGEXP_CONTAINS(
  LOWER(x.name),
  r'test|테스트|비회원|benevity|이니스트|unhcr|kt ars|해피빈|카카오펀딩스토리|카카오 같이가치|비회원 문의|온라인 무통장입금|중복후원삭제|현장취소삭제'
)
 )


, final_donor as (

  select   
  ds.*
  , cast (date_trunc (ds.commitment_date, month)as date) as commitment_month
  
  -- 1. Active Donor
  ,case  when
            (ds.commitment_date is null or cast (date_trunc (ds.commitment_date, month)as date) <= review_month) -- 신청일
            AND (c.all_end_date IS NULL OR cast (date_trunc (c.all_end_date, month) as date) > review_month ) -- 납부여부 = 'Y'
            AND ds.campaign_id is not null -- 캠페인회차 is not null
            AND (ds.cancel_cal_date IS NULL OR DATE_TRUNC(PARSE_DATE('%Y-%m-%d', ds.cancel_cal_date), MONTH) > review_month) -- cancel_status = 'N'
            AND ds.payment_method IN ('CMS','신용카드','NPay','KakaoPay')   
            -- AND ds.pledge_status in ('대기', '진행')
            AND ds.start_month IS NOT NULL -- 후원개시일 있음
            and (ds.end_month is null or PARSE_DATE('%Y-%m-%d', CONCAT(ds.end_month, '-01')) > review_month)   
            AND ds.oneoff_check IS NULL -- 수시 아님

            AND ds.channel NOT IN ('UPGRADE', 'ONEOFF') -- upgrade, oneoff 채널 아님 
            and ds.channel not like 'UP_%' 
            and ds.channel not like 'PPH%'
                   
  then 'y' else 'n' end as active_donor,


-- 2. New Donor
case when 
    cast (date_trunc (ds.commitment_date, month) as date) =  review_month   -- 신청일
     AND (c.all_end_date IS NULL OR cast (date_trunc (c.all_end_date, month) as date) > review_month) -- 납부여부 = 'Y'
     AND ds.campaign_id is not null 
     and (ds.cancel_cal_date IS NULL OR DATE_TRUNC(PARSE_DATE('%Y-%m-%d', ds.cancel_cal_date), MONTH) > review_month) -- cancel_status = 'N'
     AND ds.payment_method IN ('CMS','신용카드','NPay','KakaoPay') 
     -- AND ds.pledge_status in ('대기', '진행')
     AND ds.start_month IS NOT NULL -- 후원개시일 있음 
     and (ds.end_month is null or PARSE_DATE('%Y-%m-%d', CONCAT(ds.end_month, '-01')) > review_month)
     /* any criteria on end date?? */
--   AND ds.Acq_gb = 'Existing' 
     
    AND ds.oneoff_check IS NULL
    AND ds.new_site_code_acq NOT IN ('1.3 Reactivation', '2.6 Conversion') --???

    AND ds.channel NOT IN ('UPGRADE', 'ONEOFF') 
    and ds.channel not like 'UP_%'
    and ds.channel not like 'PPH%'
    
   
then 'y' else 'n' end as new_donor,


-- 3. Reactivation Donor
   case when 
      cast (date_trunc (ds.commitment_date, month) as date) =  review_month
       AND (c.all_end_date IS NULL OR cast (date_trunc (c.all_end_date, month) as date) > review_month)
       AND ds.campaign_id is not null

            AND (ds.cancel_cal_date IS NULL OR DATE_TRUNC(PARSE_DATE('%Y-%m-%d', ds.cancel_cal_date), MONTH) > review_month) -- cancel_status = 'N'
            AND ds.payment_method IN ('CMS','신용카드','NPay','KakaoPay')   
 --         AND ds.pledge_status in ('대기', '진행')
            AND ds.start_month IS NOT NULL -- 후원개시일 있음
            and (ds.end_month is null or PARSE_DATE('%Y-%m-%d', CONCAT(ds.end_month, '-01')) > review_month)   
            AND ds.oneoff_check IS NULL -- 수시 아님


       AND ds.acq_gb = 'Existing' 
       AND ds.new_site_code_acq IN ('1.3 Reactivation') 
    then 'y' else 'n' end as reactivation



-- 4. Conversion Donor
 ,case 
      when 
            cast (date_trunc (ds.commitment_date, month) as date) =  review_month
            AND (c.all_end_date IS NULL OR cast (date_trunc (c.all_end_date, month) as date) > review_month )
      and ds.campaign_id is not null

            AND (ds.cancel_cal_date IS NULL OR DATE_TRUNC(PARSE_DATE('%Y-%m-%d', ds.cancel_cal_date), MONTH) > review_month) -- cancel_status = 'N'
            AND ds.payment_method IN ('CMS','신용카드','NPay','KakaoPay')   
     --     AND ds.pledge_status in ('대기', '진행')
            AND ds.start_month IS NOT NULL -- 후원개시일 있음
            and (ds.end_month is null or PARSE_DATE('%Y-%m-%d', CONCAT(ds.end_month, '-01')) > review_month)   
            AND ds.oneoff_check IS NULL -- 수시 아님


      and ds.acq_gb = 'Existing' 
      and ds.new_site_code_acq IN ('2.6 Conversion') 
  then 'y' else 'n' end as conversion
   ,review_month

from pledge ds 
left join unhcr-kor-dl-ana-prod.mrm_db.Contacts c 
on ds.supporter_id = c.donor_no
)



-- CONTACT BASED: used for lapsed(all, 3M, 12M)
, xx  as (
  select x.* 
  from `unhcr-kor-dl-ana-prod.mrm_db.Contacts` x
  left join unhcr-kor-dl-pii-prod.mrm_db.Contacts p on x.donor_no = p.donor_no 
  where cast (date_trunc (x.cancel_date, month) as date) = review_month  
  --AND x.all_end_date IS NOT NULL 
  AND cast (date_trunc (x.all_end_date, month) as date)<= review_month  
  AND x.cancel_route not in ('후원자관리팀')
  AND x.payment_method in ('CMS', '신용카드', 'NPay', 'KakaoPay')
  AND NOT REGEXP_CONTAINS(LOWER(p.name), r'test|테스트|삭제')
  )


, yy as (
  select a. donor_no, 
  a.org, 
  a.rg_amount as gift_amount, 
  b.contact_date, 
  b.cancel_date,
  date_diff(cancel_date, contact_date, MONTH) as lifetime,
  format_date('%Y', cancel_date) as cancel_year,
  format_date('%y%m', cancel_date) as cancel_month,
  CONCAT(
    SPLIT(a.campaign_raw, '/')[SAFE_OFFSET(0)],
    SPLIT(a.campaign_raw, '/')[SAFE_OFFSET(1)]
) AS channel_t,
b.tot_amt, 
b.tot_tran, 
a.user_type1 as developer_old, 
a.user_input_1 as location, 
b.cancel_route,
CASE WHEN b.cancel_route = '홈페이지' THEN 'UNHCR Website'
WHEN b.cancel_route IN ('전화', '콜센터 IN', '콜센터 OUT') THEN 'Donorcare line'
WHEN b.cancel_route IN ('이메일', '우편') THEN 'Email/Mail'
WHEN b.cancel_route IN ('우편') THEN 'Mail'
WHEN b.cancel_route IN ('후원자관리팀') AND b.cancel_reason NOT LIKE '장기미납%' THEN 'No data'
WHEN b.cancel_route IS NULL THEN 'Donorcare line'
ELSE 'ERROR' END cancel_route_eng,
CASE 
    WHEN DATE_DIFF(cancel_date, contact_date, MONTH) BETWEEN 0 AND 3 THEN '0M~3M'
    WHEN DATE_DIFF(cancel_date, contact_date, MONTH) BETWEEN 4 AND 6 THEN '4M~6M'
    WHEN DATE_DIFF(cancel_date, contact_date, MONTH) BETWEEN 7 AND 9 THEN '7M~9M'
    WHEN DATE_DIFF(cancel_date, contact_date, MONTH) BETWEEN 10 AND 12 THEN '10M~12M'
    ELSE '' 
END AS ltm_band,
CASE 
    WHEN DATE_DIFF(cancel_date, contact_date, MONTH) BETWEEN 0 AND 12 THEN '1YR'
    ELSE '' 
END AS lty_band,
a.submit_date,
row_number() over (partition by a.donor_no order by a.donor_no, a.submit_date asc, a.start_month asc) as pledge_nm
from unhcr-kor-dl-ana-prod.mrm_db.RG_Pledges a
inner join xx b
on a.donor_no = b.donor_no
and b.cancel_reason NOT LIKE '장기미납%'
and (a.campaign_raw not like 'PPH%' and a.campaign_raw not like 'UP%'and a.campaign_raw not like 'ONE%'and a.campaign_raw not like 'Reacti%' and a.campaign_raw is not null)
)


, lapsed as (
  select yy.*,
  gb.new_site_code_acq,
  gb.channel_excl_upgrade as channel,
  gb.channel as channel_gb
  from yy
  left join unhcr-kor-dl-ana-prod.workspace_joomee.channel_gb_2025 gb 
  on yy.channel_t=gb.channel_t
  and gb.acq_gb = 'Existing'
  where pledge_nm = 1
  and new_site_code_acq NOT IN ('1.3 Reactivation', '2.5 Upgrade', '2.6 Conversion', '2.7 MVD', '5.4 HNWIs', '5.1 Corporate', '5.3 Foundations')
)



, final_lapsed as (
select l.*

-- 5. Lapsed Donor
,case when 
cast (date_trunc (date(l.cancel_date), month) as date) =  review_month
then 'y' else 'n' end as lapsed

-- 5-1. Lapsed 3M
,
case when 
cast (date_trunc (date(l.cancel_date), month) as date) =  review_month
and l.ltm_band = '0M~3M' then 'y' else 'n' end as lapsed_3m

-- 5-2. Lapsed 12M
,case when 
cast (date_trunc (date(l.cancel_date), month) as date) =  review_month
and  l.lty_band = '1YR' then 'y' else 'n' end as lapsed_12m

, review_month

from lapsed l

)


/*
select 
active_donor
,new_donor
,reactivation
,conversion
,lapsed
,lapsed_3m
,lapsed_12m
,count (supporter_id) as nmbr
,count (distinct supporter_id) as dist_nmbr

from final 
group by 1,2,3,4,5,6,7
*/

, dash_donor as (
select
review_month,
new_site_code_acq as channel_sitecode,
channel_gb,
CASE 
WHEN (a.channel LIKE 'F2F APPCO%' OR a.channel LIKE 'F2F SW%') THEN 'F2F SW'
WHEN a.channel LIKE 'F2F DN%' THEN 'F2F DN'
WHEN a.channel LIKE 'F2F KDA%' THEN 'F2F KDA'
WHEN a.channel LIKE 'F2F LW%' THEN 'F2F LW'
WHEN a.channel LIKE 'F2F OM%' THEN 'F2F OM'
WHEN a.channel LIKE 'F2F PN%' THEN 'F2F PN'
when a.channel like 'F2F GW%' then 'F2F GW' -- 26.4월에 GW 지부 추가 
ELSE a.channel 
END AS recruit_channel, 

CASE 
WHEN a.channel LIKE '%B2B' THEN 'B2B'
WHEN (a.channel LIKE 'F2F%' AND a.channel NOT LIKE '%B2B') THEN 'Street'
ELSE 'Other' 
END AS f2f_type_street_b2b, 

CASE 
WHEN (a.channel LIKE 'F2F APPCO%' OR a.channel LIKE 'F2F SW%') THEN a.channel
WHEN a.channel LIKE 'F2F DN%' THEN a.channel
WHEN a.channel LIKE 'F2F KDA%' THEN a.channel
WHEN a.channel LIKE 'F2F LW%' THEN a.channel
WHEN a.channel LIKE 'F2F OM%' THEN a.channel
WHEN a.channel LIKE 'F2F PN%' THEN a.channel
WHEN a.channel LIKE 'F2F IH%' THEN a.channel
when a.channel like 'F2F GW%' then a.channel -- 26.4월에 GW 지부 추가 
ELSE 'Not F2F' 
END AS f2f_channel_gb, 


count(case when new_donor = 'y' then supporter_id end) as new_donors,
count(case when active_donor = 'y' then supporter_id end) as active_donors,
--count(case when lapsed = 'y' then supporter_id end) as lapsed_donors,
count(case when reactivation = 'y' then supporter_id end) as reactivation_donors,
count(case when conversion = 'y' then supporter_id end) as conversion_donors

from final_donor a
group by 1,2,3,4,5,6
)

, dash_lapsed as (
select
review_month,
new_site_code_acq as channel_sitecode,
channel_gb,
CASE 
WHEN (a.channel LIKE 'F2F APPCO%' OR a.channel LIKE 'F2F SW%') THEN 'F2F SW'
WHEN a.channel LIKE 'F2F DN%' THEN 'F2F DN'
WHEN a.channel LIKE 'F2F KDA%' THEN 'F2F KDA'
WHEN a.channel LIKE 'F2F LW%' THEN 'F2F LW'
WHEN a.channel LIKE 'F2F OM%' THEN 'F2F OM'
WHEN a.channel LIKE 'F2F PN%' THEN 'F2F PN'
when a.channel like 'F2F GW%' then 'F2F GW' -- 26.4월에 GW 지부 추가 
ELSE a.channel 
END AS recruit_channel, 

CASE 
WHEN a.channel LIKE '%B2B' THEN 'B2B'
WHEN (a.channel LIKE 'F2F%' AND a.channel NOT LIKE '%B2B') THEN 'Street'
ELSE 'Other' 
END AS f2f_type_street_b2b, 

CASE 
WHEN (a.channel LIKE 'F2F APPCO%' OR a.channel LIKE 'F2F SW%') THEN a.channel
WHEN a.channel LIKE 'F2F DN%' THEN a.channel
WHEN a.channel LIKE 'F2F KDA%' THEN a.channel
WHEN a.channel LIKE 'F2F LW%' THEN a.channel
WHEN a.channel LIKE 'F2F OM%' THEN a.channel
WHEN a.channel LIKE 'F2F PN%' THEN a.channel
WHEN a.channel LIKE 'F2F IH%' THEN a.channel
when a.channel like 'F2F GW%' then a.channel -- 26.4월에 GW 지부 추가 
ELSE 'Not F2F' 
END AS f2f_channel_gb, 


--count(case when new_donor = 'y' then supporter_id end) as new_donors,
--count(case when active_donor = 'y' then supporter_id end) as active_donors,
count(case when lapsed = 'y' then donor_no end) as lapsed_donors,
count(case when lapsed_3m = 'y' then donor_no end) as lapsed_donors_3m,
count(case when lapsed_12m = 'y' then donor_no end) as lapsed_donors_12m,
--count(case when reactivation = 'y' then supporter_id end) as reactivation_donors,
--count(case when conversion = 'y' then supporter_id end) as conversion_donors

from final_lapsed a
group by 1,2,3,4,5,6
)

SELECT 
  format_date('%Y-%m', d.review_month) as period,
  d.review_month as month_first,
  COALESCE(d.channel_sitecode, l.channel_sitecode) AS channel_sitecode,
  COALESCE(d.channel_gb, l.channel_gb) AS channel_gb,
  COALESCE(d.recruit_channel, l.recruit_channel) AS recruit_channel,
  COALESCE(d.f2f_type_street_b2b, l.f2f_type_street_b2b) AS f2f_type_street_b2b,
  COALESCE(d.f2f_channel_gb, l.f2f_channel_gb) AS f2f_channel_gb,
  d.new_donors as new_donor,
  d.active_donors as active_donor,
  l.lapsed_donors as lapsed_donor,
  l.lapsed_donors_3m as lapsed_3m,
  l.lapsed_donors_12m as lapsed_12m,
  d.reactivation_donors as reactivation_donor,
  d.conversion_donors as conversion_donor

FROM dash_donor d
FULL OUTER JOIN dash_lapsed l 
  ON d.review_month = l.review_month
  AND d.channel_sitecode = l.channel_sitecode
  AND d.channel_gb = l.channel_gb
  AND d.recruit_channel = l.recruit_channel
  AND d.f2f_type_street_b2b = l.f2f_type_street_b2b
  AND d.f2f_channel_gb = l.f2f_channel_gb
WHERE 
  COALESCE(d.new_donors, 0)
+ COALESCE(d.active_donors, 0)
+ COALESCE(d.reactivation_donors, 0)
+ COALESCE(d.conversion_donors, 0)
+ COALESCE(l.lapsed_donors, 0)
+ COALESCE(l.lapsed_donors_3m, 0)
+ COALESCE(l.lapsed_donors_12m, 0) > 0
order by channel_sitecode;