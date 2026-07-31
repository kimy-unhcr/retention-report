-- 아래 수치 확인한 뒤 문제 없으면 comment 해제 후 데이터 insert
/*
insert into
unhcr-kor-dl-ana-uat.workspace_joomee.headcount_new_donor_native

(donor_no,
transaction_type,
first_transaction_date,
tran_amount,
payment_method,
campaign_id,
channel,
donation_section,
acq_gb_simple,
sitecode
)
*/

with ig_donor as (
select * 
from unhcr-kor-dl-ana-prod.DataMarts.korea_transactions_sitecode_table
where extract(year from transaction_date) = 2026 AND extract(month from transaction_date) <= 6 -- 2026 June YTD (납부일 기준)
and acq_gb_simple = 'Acquisition' and sitecode not in ('2.%') -- Acquisition -> New Donor
 and (campaign_id  not like 'UP%' 
 and campaign_id not like'Reactivation%' 
 and campaign_id not like 'Cash%'
 and lower(campaign_id) not like 'pph%') 
),

rg_donor as (
select supporter_id, count(*) 
from unhcr-kor-dl-ana-prod.DataMarts.korea_transactions_sitecode_table
where extract(year from transaction_date) = 2026 AND extract(month from transaction_date) <= 6 -- 2026 June YTD (납부일 기준)
and transaction_type = 'Regular' -- 정기납부건만
and acq_gb_simple = 'Acquisition' and sitecode not in ('2.%') -- new donor
 and (campaign_id  not like 'UP%' 
 and campaign_id not like'Reactivation%'
 and campaign_id not like 'Cash%'
 and lower(campaign_id) not like 'pph%') 
group by supporter_id
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

-- Output1. new donor list 
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
where a.transaction_date between '2026-06-01' and '2026-06-30' -- 해당월의 New Donor

