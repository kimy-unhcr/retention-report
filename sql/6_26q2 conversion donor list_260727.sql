1. 데이터 확인 & 추출 

-- insert into unhcr-kor-dl-ana-prod.Qreport_Donor.conversion_donor -- 데이터 이상 없으면 코멘트 처리 해제해서 insert into
with conv_donors as (
select *
from unhcr-kor-dl-ana-prod.DataMarts.korea_transactions_sitecode_table
where campaign_id like 'CONVERSION%'),

tran_num as (
select *,
row_number() over(partition by supporter_id, campaign_id order by transaction_date) as tran_nm_2
from conv_donors),

first_tran as (
select *
from tran_num
where tran_nm_2 = 1
and transaction_date between '2026-04-01' and '2026-06-30'-- 2026 Q2 (납부일 기준)
),

oo_history as (
select *
from unhcr-kor-dl-ana-prod.DataMarts.korea_transactions_sitecode_table
where transaction_type = 'Single'),

oo_tran_num as (
select *,
row_number() over (partition by supporter_id order by transaction_date) as tran_nm_2
from oo_history),

first_oo_tran as (
select * 
from oo_tran_num
where tran_nm_2 = 1)


select a.supporter_id as donor_no,
b.transaction_date as first_oo_transaction_date,
b.campaign_id as first_oo_campaign_id,
b.channel as first_oo_channel,
b.acq_gb_simple as first_oo_acq_gb_simple,
b.sitecode as first_oo_sitecode,
a.transaction_date as conversion_date,
a.acq_gb_simple as conversion_acq_gb_simple,
a.campaign_id as conversion_campaign,
c.tran_amount as conversion_amount,
--c.payment_method,
--a.channel,
c.donation_section as conversion_donation_section,
--a.sitecode
from first_tran a
left join first_oo_tran b on a.supporter_id = b. supporter_id
inner join unhcr-kor-dl-ana-prod.mrm_db.Transactions c
on a.transaction_id = c.tran_uid
order by a.transaction_date;

2. 데이터 추출
--> insert 이후 리스트 추출

select * from unhcr-kor-dl-ana-prod.Qreport_Donor.conversion_donor
where conversion_date between '2026-01-01' and '2026-06-30'
order by conversion_date


## Q Report 리스트 작성시 주의사항 ##
/*
conversion_acq_gb_simple = 'Acquisition'인 후원자는 New Donor List에도 있어야 함. 
그런데 간혹 회원번호 통합/삭제로 안 보이는 경우가 있음 (New Donor List는 매달 업로드 vs. Conversion Donor는 분기별 업로드)

따라서

1. in_new_donor인 케이스 확인
select
c.*,
case when n.donor_no is not null then 'Y'
else 'N'
end as in_new_donor

from unhcr-kor-dl-ana-prod.Qreport_Donor.conversion_donor c
left join unhcr-kor-dl-ana-prod.Qreport_Donor.new_donor n
on c.donor_no = n.donor_no
where conversion_date between '2026-01-01' and '2026-06-30'
and conversion_acq_gb_simple = 'Acquisition'

2. MRM DB에서 통합이력 찾기
select *
from unhcr8351_rep.dbo.UV_UNHCR_Tbl_Contacts_Integration_History
where MemberNumber = '00885246' -- 통합 후 회원번호

--> ID = 5132 확인

select *
from unhcr8351_rep.dbo.UV_UNHCR_Tbl_Contacts_Integration_History_Belonging -- 통합 전
where ID = 5132

--> MemberNumber = 00881446 확인

3. New Donor List 수정