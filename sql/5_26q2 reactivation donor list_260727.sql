
1. 데이터 확인&추가

-- insert into unhcr-kor-dl-ana-prod.Qreport_Donor.reactivation_donor -- 수치 이상 없으면 코멘트 해제해서 insert into

with react_donor as ( 
select *
from unhcr-kor-dl-ana-prod.DataMarts.korea_transactions_sitecode_table
where campaign_id like 'Reactivation%'
and acq_gb_simple = 'Existing' -- 2026 Q2부터 Existing Reactivation만 Reactivation으로 분류하도록 변경
),

tran_num as (
select * ,
row_number() over(partition by supporter_id, campaign_id order by transaction_date) as tran_nm_2 -- React 캠페인 여러번 참여할 수도 있으니
from react_donor),

first_tran as (
select *
from tran_num
where tran_nm_2 = 1
and transaction_date between '2026-04-01' and '2026-06-30' -- 2026 Q2 (납부일 기준) 
)

select a.supporter_id as donor_no, 
a.transaction_type, 
a.transaction_date as reactivation_date, 
b.tran_amount as rg_amount, 
b.payment_method, 
a.campaign_id, 
a.channel, 
b.donation_section, 
a.acq_gb_simple, -
a.sitecode 
from first_tran a
inner join unhcr-kor-dl-ana-prod.mrm_db.Transactions b
on a.transaction_id = b.tran_uid;


2. 데이터 추출
--> insert 이후에 
select *
from unhcr-kor-dl-ana-prod.Qreport_Donor.reactivation_donor
where reactivation_date between '2026-01-01' and '2026-06-30'
order by reactivation_date;

