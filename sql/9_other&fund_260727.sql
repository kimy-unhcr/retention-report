-- 1. # one-off donors (Headcount)
select count(distinct donor_no) 
from unhcr-kor-dl-ana-prod.mrm_db.Transactions
where payment_type = '수시'
and pledge_active = 'N'
and send_date between '2026-06-01' and '2026-06-30'

-- 납부구분별 
select donation_section, count(distinct donor_no) as oo_donor
from unhcr-kor-dl-ana-prod.mrm_db.Transactions
where payment_type = '수시'
and pledge_active = 'N'
and send_date between '2026-06-01' and '2026-06-30'
group by donation_section
order by oo_donor desc;


-- 2. # e-mail subscribers
select count(*)
from unhcr-kor-dl-ana-prod.mrm_db.Contacts
where contact_date < '2026-07-01'
and email_opt = 'Y'
and email_yn = 'Y'


-- 3. internal cancellation by route
with xx as (
select *
from unhcr-kor-dl-pii-prod.mrm_db.Contacts 
where FORMAT_DATE('%Y-%m', cancel_date) = '2026-06'
and FORMAT_DATE('%Y-%m', all_end_date) <= '2026-06'
and cancel_route not in ('후원자관리팀')
and payment_method in ('CMS', '신용카드', 'NPay', 'KakaoPay')
AND NOT REGEXP_CONTAINS(LOWER(name), r'test|테스트|삭제'))

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
and (a.campaign_raw not like 'PPH%' and a.campaign_raw not like 'UP%'and a.campaign_raw not like 'ONE%'and a.campaign_raw not like 'Reacti%' and a.campaign_raw is not null))

select cancel_route_eng, count(*)
from yy
left join unhcr-kor-dl-ana-prod.workspace_joomee.channel_gb_2025 gb 
  on yy.channel_t=gb.channel_t
  and gb.acq_gb = 'Existing'
where pledge_nm = 1
and new_site_code_acq NOT IN ('1.3 Reactivation', '2.5 Upgrade', '2.6 Conversion', '2.7 MVD', '5.4 HNWIs', '5.1 Corporate', '5.3 Foundations')
group by cancel_route_eng;


-- 4. external cancellation by route: 아직 GCP 테이블 불완전하여 MRM_DB 복제서버에서 추출 
-- Bank의 경우 익월분 수치도 합산
with x as (
select  회원번호, count(*) as change_count 
from unhcr8351_rep.dbo.UV_UNHCR_Data_Change_History
where 변경항목 = '납부여부' 
and 변경전 = 'Y' 
and 변경자 = 'SCMS' 
and FORMAT(변경일시, 'yyyy-MM') = '2026-06'
group by 회원번호)

, y as (
select 회원번호, 신청일, 외부승인, 신청구분, 처리구분, 납부금액, 처리결과, 결과메세지 
from unhcr8351_rep.dbo.UV_UNHCR_Cms_Enroll_Results
where 신청일 between  '2026-05-31' and '2026-06-29' -- 신청일은 해당연월 -1일로 between
and 외부승인 = 'Y' 
and 신청구분 = '해지'
)

, z as (
select a.회원번호, a.기관, a.성별, a.나이, a.가입일, a.납부여부, a.납부종료일, a.탈퇴여부, a.납부시작년월, a.총납부건수, a.총납부금액, y.처리구분, 
 FORMAT(a.납부종료일, 'yyyy-MM') as 납부종료월,
case when y.처리구분 in ( '고객해지(PayInfo-고객)','고객해지(PayInfo-금융기관)' ) then 'PayInfo'
	when y.처리구분 in ( '고객해지(금융기관)' ) then 'Bank'
	else 'Bank' end as 처리구분_s
		from  unhcr8351_rep.dbo.UV_UNHCR_Contacts a 
inner join x 
on a.회원번호 = x.회원번호 
and a.납부여부='N' 
left join y
on a.회원번호 = y.회원번호 )

select 처리구분_s, 납부종료월, count(*) from z
group by 처리구분_s, 납부종료월
order by 처리구분_s, 납부종료월;


-- 5. Anonymous one-off
KB입출금내역: unhcr-kor-dl-ana-prod.income_db.income_kb_raw에서 관리됨
-- null name donor: 1343
select
case 
    when gb like '취소%'  or spend_out > 0  or name like '이자세금%' or name = 'UNHCR' or name like '공인인증서발급수수료%' then '제외' 
     when tran_method = 'CMS 공동' then 'CMS' 
     when name in ('나이스페이먼츠','NICE페이먼츠(', 'NICE페이먼츠', '나이스정보통신') then 'PG' 
     when name in ('지로입금') then '지로'
     when name like '해피빈%' then '해피빈'
     when name in ('카카오') then '카카오스토리펀딩'
     when name like '네이버페이%' then '네이버페이'
     when name like '카카오페이%' then '카카오페이'
     when name like 'KT02%' then 'KT'
     when name like '신한8%' or name like'신한법인%' then '신한카드 포인트'
     when name = '신한카드자금' then '신한카드 포인트'
     when bank = '하나은행'and name like '하나91%' then '하나카드 포인트'
     when name like '%KB국민%' or name like '%KB포%' or name like '%국민카드%' or name like '%KB 포%' then 'KB카드 포인트'    
     when name like '%/UK%' then '베네비티' 
     else '' end income_gb,
count(*) as donor_num
from unhcr-kor-dl-ana-prod.income_db.income_kb_raw
where report_ym like '2606'
group by 1;

-- MRM의 무통장 입력건수 차감: 146
select count(donor_no)
from unhcr-kor-dl-ana-prod.mrm_db.Transactions
where payment_method = '무통장입금'
and income_date between '2026-06-01' and '2026-06-30'


-- 6. Refund: 아직 GCP 테이블 불완전하여 MRM_DB 복제서버에서 추출 

with x as
(select 회원고유번호, 회원번호, 성명, 기록일시, 기록분류, 상세분류, 제목, 내용 
from unhcr8351_rep.dbo.UV_UNHCR_Case_Management
 where 기록일시 between '2026-06-01' AND '2026-06-30'
 and 기록분류 = '환불' and 상세분류 = '환불완료'
 )

select b.회원번호, b.가입일, b.가입경로, b.총납부금액, a.기록일시, 
PARSENAME(REPLACE(a.제목, '_', '.'), 3) AS 납부방법, 
    PARSENAME(REPLACE(a.제목, '_', '.'), 2) AS 환불금액, 
    PARSENAME(REPLACE(a.제목, '_', '.'), 1) AS 환불사유,  
	a.내용 from x a
inner join unhcr8351_rep.dbo.UV_UNHCR_Contacts b
on a.회원고유번호 = b.회원고유번호
order by 기록일시;