/** for faster access put usertables in memory **/ 
-- backlog
with backlog_curve as (
select * from usertables.mc_backlog_new_curve_csv where days_since_activation >= 0
),
-- country detail mapping
country_code as(
select * from usertables.mc_country_codes_csv),
-- team role and location data [MAKE SURE THIS IS UP TO DATE]
team_role as(
select * from usertables.mc_team_role_csv
),



/** Opti-calculations **/ 

daily_pipeline as (select  
dateadd(day, curve.day_count, pipe.opportunity_expected_go_live_date_date) as fcst_date,
opportunity_created_date_date as opportunity_created_date_date,               
'OPTI__' || pipe.opportunity as sales_merchant_id,
pipe.opportunity_owner as owner,
pipe.opportunity_name as merchant_name, 
pipe.opportunity_merchant_country as merchant_country,
pipe.vertical as vertical,
pipe.opportunity_status as opportunity_status,
pipe.opportunity_expected_go_live_date_date as sales_activation_date,
pipe.opportunity_type,
pipe.opportunity_stage,
pipe.mes_opportunity_amount as wgted_opportunity_amount,
(pipe.mes_opportunity_amount)*first_year_sold_pct as pipeline_npv
from ( 
SELECT 
    salesforcemerchants.opportunity AS "opportunity",
    salesforcemerchants.opportunity_name AS "opportunity_name",
    DATE(salesforcemerchants.opportunity_created_date) AS "opportunity_created_date_date",  
    DATE(salesforcemerchants.opportunity_close_date) AS "opportunity_close_date_date",
    salesforcemerchants.opportunity_owner AS "opportunity_owner",
    salesforcemerchants.opportunity_type AS "opportunity_type",
    DATE(salesforcemerchants.opportunity_expected_go_live_date) AS "opportunity_expected_go_live_date_date",
    -- deal signed not live OR pipeline
    case when salesforcemerchants.opportunity_stage in ('Negotiating', 'Discovering Needs', 'Validating Fit', 'Proposing Solution')  THEN 'pipeline'
         when salesforcemerchants.opportunity_stage in ('Onboarding', 'Live')  THEN 'signed_not_live'
         else 'lost' end as opportunity_status, 
    opportunity_industry AS "vertical",
    salesforcemerchants.opportunity_merchant_country AS "opportunity_merchant_country",
    case when DATE(merchants.sales__expected_go_live_date) < '2017-06-26' THEN 1 ELSE 0 END AS "live_or_not", -- check
    DATE(merchants.sales__expected_go_live_date) AS "unified_funnel__activation_date_date",
    salesforcemerchants.opportunity_stage AS "opportunity_stage",
    (COALESCE(COALESCE( ( SUM(DISTINCT (CAST(FLOOR(COALESCE(salesforcemerchants.opportunity_amount,0)*(1000000*1.0)) AS DECIMAL(38,0))) + CAST(STRTOL(LEFT(MD5(CONVERT(VARCHAR,salesforcemerchants.opportunity)),15),16) AS DECIMAL(38,0))* 1.0e8 + CAST(STRTOL(RIGHT(MD5(CONVERT(VARCHAR,salesforcemerchants.opportunity)),15),16) AS DECIMAL(38,0)) ) - SUM(DISTINCT CAST(STRTOL(LEFT(MD5(CONVERT(VARCHAR,salesforcemerchants.opportunity)),15),16) AS DECIMAL(38,0))* 1.0e8 + CAST(STRTOL(RIGHT(MD5(CONVERT(VARCHAR,salesforcemerchants.opportunity)),15),16) AS DECIMAL(38,0))) )  / (1000000*1.0), 0), 0))*(avg(opportunity_probability)/100) AS "mes_opportunity_amount",
    COALESCE(SUM(datediff (days, opportunity_close_date, getdate())), 0) AS "days_since_close_date"
FROM sales.salesforce AS salesforcemerchants
LEFT JOIN dim.merchants as merchants on stripe_merchant_id = merchants._id
WHERE 
/********
NEED TO UPDATE DATES BELOW    
********/
    
    

(merchants.sales__expected_go_live_date IS NULL or merchants.sales__expected_go_live_date >= '2017-06-26')
AND salesforcemerchants.opportunity_expected_go_live_date >= TIMESTAMP '2017-06-26' -- include things that may be going live this week
AND salesforcemerchants.opportunity_expected_go_live_date <= TIMESTAMP '2017-12-31' -- include all opportunities expected to live this year
AND salesforcemerchants.opportunity_stage in ('Negotiating', 'Discovering Needs', 'Validating Fit', 'Proposing Solution', 'Onboarding', 'Live')

GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13
ORDER BY 8
 )  as pipe 
cross join usertables.day_backlog_curve as curve
where 
(curve.day_count between 0 and 364))


select 
  opportunity_status as data_type,
  to_char(date_trunc('year', fcst_date),'YYYY') as year,
  to_char(date_trunc('quarter', fcst_date), 'YYYY-MM') as quarter,
  to_char(date_trunc('month', fcst_date),'YYYY-MM') as month,
  0 as qtd, 
  0 as this_week, 
  cc.sales_region as region,
  cc.sfdc_country_name as country,
  opportunity_stage as sales_channel,
  case
  -- 1. filter team type first
  --when sales_location = 'Hub' then 'Hub' 
  when role = 'NBA' then 'NBA'
  -- UK verticals
  when cc.sales_region = 'UK' and vertical in ('Ticketing & Events', 'Travel & Hosp') then 'Ticketing/Travel'
  when cc.sales_region = 'UK' and vertical in ('Financial') then 'Financial Services'
  when cc.sales_region = 'UK' and vertical in ('Healthcare', 'Professional Services', 'Other Services','B2B', 'B2C Software', 'Content', 'Other Software & Content', 'B2C (Software)', 'B2B (Software)', 'Real Estate', 'On-Demand Services') then 'Services, Software & Content'
  when cc.sales_region = 'UK' and vertical in ('Fashion', 'Food & Bev', 'Manufacturing', 'Other Retail') then 'Retail'
  when cc.sales_region = 'UK' and vertical in ('Government', 'EDU', 'Non-Profit', 'Utilities', 'Other Public Sector') then 'Public Sector'
  
  
  
  -- US/CA
  when cc.sfdc_country_name = 'United States' and vertical in ('B2B', 'B2C Software', 'Content', 'Other Software & Content', 'B2C (Software)', 'B2B (Software)') then 'Software & Content'
  when cc.sfdc_country_name = 'United States' and  vertical in ('Ticketing & Events', 'Financial', 'Healthcare', 'Professional Services', 'Other Services', 'Travel & Hosp', 'Real Estate', 'On-Demand Services') then 'Services'
  when cc.sfdc_country_name = 'United States' and  vertical in ('Government', 'EDU', 'Non-Profit', 'Utilities', 'Other Public Sector') then 'Public Sector'
  when cc.sfdc_country_name = 'United States' and  vertical in ('Fashion', 'Food & Bev', 'Manufacturing', 'Other Retail') then 'Retail'
  when cc.sfdc_country_name = 'United States' and  vertical is null then 'No industry'
  when cc.sfdc_country_name = 'Canada' then 'CA'  
  -- SouthernEU
  when cc.sales_region = 'Southern EU' then cc.sfdc_country_name
  -- NorthernEU
  when cc.sales_region = 'Northern EU' and cc.sfdc_country_name in ('DE','AT','CH') then 'DACH'
  when cc.sales_region = 'Northern EU' and cc.sfdc_country_name in ('BE','NL','LU') then 'BENELUX'
  when cc.sales_region = 'Northern EU' and cc.sfdc_country_name in ('NO', 'FI', 'SE', 'DK', 'IS') then 'NORDICS'  
  -- AU/NZ
  when cc.sales_region = 'AU/NZ' then cc.sfdc_country_name
  -- SG
  when cc.sales_region = 'SG/HK' then cc.sfdc_country_name
  when cc.sales_region = 'New Markets' then cc.sfdc_country_name
  -- IE
  when cc.sales_region = 'IE' then cc.sfdc_country_name
  else 'other'
end AS sub_region,  
case
  -- UK verticals
  when cc.sales_region = 'UK' and vertical in ('Ticketing & Events', 'Travel & Hosp') then 'Ticketing/Travel'
  when cc.sales_region = 'UK' and vertical in ('Financial') then 'Financial Services'
  when cc.sales_region = 'UK' and vertical in ('Healthcare', 'Professional Services', 'Other Services','B2B', 'B2C Software', 'Content', 'Other Software & Content', 'B2C (Software)', 'B2B (Software)', 'Real Estate', 'On-Demand Services') then 'Services, Software & Content'
  when cc.sales_region = 'UK' and vertical in ('Fashion', 'Food & Bev', 'Manufacturing', 'Other Retail') then 'Retail'
  when cc.sales_region = 'UK' and vertical in ('Government', 'EDU', 'Non-Profit', 'Utilities', 'Other Public Sector') then 'Public Sector'
  
  -- Standard verticals
  when vertical in ('B2B', 'B2C Software', 'Content', 'Other Software & Content', 'B2C (Software)', 'B2B (Software)') then 'Software & Content'
  when vertical in ('Ticketing & Events', 'Financial', 'Healthcare', 'Professional Services', 'Other Services', 'Travel & Hosp', 'Real Estate', 'On-Demand Services')
  then 'Services'
  when vertical in ('Government', 'EDU', 'Non-Profit', 'Utilities', 'Other Public Sector') then 'Public Sector'
  when vertical in ('Fashion', 'Food & Bev', 'Manufacturing', 'Other Retail') then 'Retail'
  when vertical is null then 'No industry'
  else 'other'
end
 AS vertical,  
  owner as owner,
  usr.role as sales_role,
  usr.team AS sales_location,
  sales_merchant_id as sales_merchant_id,
  merchant_name,
  'opportunity' as sales_category,
  to_char(sales_activation_date,'YYYY-MM-DD') as sales_go_live_date,
  case when datediff('d', sales_activation_date, fcst_date) >= 0 and datediff('d', sales_activation_date, fcst_date) < 90 then 1 else 0 end as ninety_day_live,
  case when datediff('d', sales_activation_date, fcst_date) >= 0 and datediff('d', sales_activation_date, fcst_date) < 366 then 1 else 0 end as first_year_sold,
  avg(wgted_opportunity_amount),
  COALESCE(SUM(pipeline_npv), 0) AS npv_fixed_fx,
  count(distinct fcst_date) AS days_in_period

  
  
FROM daily_pipeline dp
JOIN country_code as cc ON dp.merchant_country = cc.sfdc_country_name
JOIN team_role as usr ON usr.sales_owner = dp.owner
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20
