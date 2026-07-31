** 2026년부터는 new donor headcount list를 매달 unhcr-kor-dl-ana-uat.workspace_joomee.headcount_new_donor_native에 적재함

select *
from unhcr-kor-dl-ana-uat.workspace_joomee.headcount_new_donor_native
where first_transaction_date between '2026-01-01' and '2026-06-30' -- for Q2 2026
order by first_transaction_date; 

--로 전체 리스트 (new donor list_raw) 파일을 뽑으면 되고

--`unhcr-kor-dl-ana-prod.Qreport_Donor.new_donor`에도 해당 분기 자료 추가

INSERT INTO `unhcr-kor-dl-ana-prod.Qreport_Donor.new_donor`
SELECT *
FROM `unhcr-kor-dl-ana-uat.workspace_joomee.headcount_new_donor_native`
WHERE first_transaction_date BETWEEN '2026-04-01' AND '2026-06-30';






** new donor headcount list 월별 적재 vs. 분기별 추출시 donor_no 등 데이터가 바뀔 수 있음. 분기말 기준으로 새로 뽑는다면, 아래 쿼리 사용


with ig_donor as (
select * 
from unhcr-kor-dl-ana-prod.DataMarts.korea_transactions_sitecode_table
where extract(year from transaction_date) = 2026 AND extract(month from transaction_date) <= 6 -- 2026 Q2 YTD
and acq_gb_simple = 'Acquisition' and sitecode not in ('2.%') -- Acquisition -> New Donor
-- and (campaign_id  not like 'UP%' -- 2026 Q2부터 upgrade, reactivation, cash 캠페인을 통한 acquisition도 원채널의 acquisition으로 집계하기로 함. 
-- and campaign_id not like'Reactivation%' 
-- and campaign_id not like 'Cash%'
 and lower(campaign_id) not like 'pph%' 
),


tran_num as (
SELECT *, 
ROW_NUMBER()
    OVER (PARTITION BY supporter_id
    ORDER BY transaction_date) AS tran_nm_2
    FROM ig_donor
),

first_tran as (
select * 
from tran_num 
where tran_nm_2 = 1 -- 첫번째 납부를 기준으로 sitecode, tran_type 구분
)

select a.supporter_id as donor_no, 
a.transaction_type as transaction_type, 
a.transaction_date as first_transaction_date, 
cast(b.tran_amount as int64) as  tran_amount, 
b.payment_method as payment_method, 
a.campaign_id as campaign_id, 
a.channel as channel, 
b.donation_section as donation_section, 
a.acq_gb_simple as acq_gb_simple, 
a.sitecode as sitecode
from first_tran a
inner join unhcr-kor-dl-ana-prod.mrm_db.Transactions b
on a.transaction_id = b.tran_uid
where a.transaction_date between '2026-01-01' and '2026-06-30' -- first tran in 2026 Q1

