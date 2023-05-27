/* Query all tables to check dataset*/
select * from cluster_coverage cc limit 10;
select * from commercials c limit 10;
select * from oda_trip_data otd  limit 10;
select * from partners p  limit 10;
select * from regions r limit 10;


--making columns for ODA Detail, Cost type from data in commercial cost
with commercial_cost as(
select 
bp_id,
concat('ODA_', right(split_part(commercial_type, '_',1),1)) as oda_detail,
sum(case when split_part(commercial_type, '_',2) = 'vc' then rate end) as variable_cost,
sum(case when split_part(commercial_type, '_',2) = 'trip' then rate end) as fixed_cost
from commercials c
group by bp_id, oda_detail
order by bp_id, oda_detail),


--making columns for oda type, date, farthest distance dilivered, trip category from Oda_trip_data table
oda_t1 as (
SELECT *,
concat(split_part(serviceability, '_',1),'_',split_part(serviceability, '_',2)) as oda_detail,
date(dispatch_time) as dt,
cast (SPLIT_PART(serviceability , '_', 2) as integer) as oda , 
cast(max(SPLIT_PART(serviceability , '_', 2)) over(partition by trip_id) as integer) as max_oda,
case when
cast(max(SPLIT_PART(serviceability , '_', 2)) 
over(partition by trip_id) as integer) > 2 then 'DNP' else 'NP' end as trip_category,
case when (EXTRACT(DOW FROM dispatch_time) between 1 and 3) then 1 else 2 end as half_of_week
from oda_trip_data otd ),


--tagging trips for current structure, baseline, scenario 1 and scenario 2 
oda_t2 as (
select *,
case when 
	row_number() over(partition by bp_id, dt, trip_id order by oda desc)=1 
		then 1 else 0 end as current_trips,
case when 
	row_number() over(partition by bp_id, dt, trip_category order by oda desc)= 1 
		then 1 else 0 end as baseline_trips,
case 
	when trip_category = 'NP' and row_number() 
		over(partition by bp_id, dt, trip_category order by oda desc)=1 then 1
	when trip_category = 'DNP' and row_number() 
		over(partition by bp_id, trip_category, extract(week from dispatch_time), half_of_week  order by oda desc)=1 then 1
	else 0 end as scenario_1_trips,
case 
	when trip_category = 'DNP' and row_number() 
		over(partition by bp_id, trip_category, extract(week from dispatch_time) order by oda desc)=1 then 1
	when trip_category = 'NP' and row_number() 
		over(partition by bp_id, trip_category, extract(week from dispatch_time), half_of_week  order by oda desc)=1 then 1
	else 0 end as scenario_2_trips
from oda_t1),


--Calculating costs based on trips calculated in various scenarios.
cc_t1 as(
select o.bp_id, o.dt,o.trip_id, o.oda_detail, o.trip_category, o.current_trips, o.baseline_trips, o.weight, o.to_pincode,
round(cast (o.weight * cc.variable_cost as numeric),1) as variable_cost, 
case when o.baseline_trips = 1 then cc.fixed_cost else 0 end as baseline_fixed_cost,
case when o.current_trips = 1 then cc.fixed_cost else 0 end as current_fixed_cost,
case when o.scenario_1_trips = 1 then cc.fixed_cost else 0 end as s1_fixed_cost,
case when o.scenario_2_trips = 1 then cc.fixed_cost else 0 end as s2_fixed_cost
from oda_t2 o
join commercial_cost cc
on o.bp_id = cc.bp_id
and o.oda_detail = cc.oda_detail)


--Final Table is ready will checks for baseline and created scenarios filtering it for month of may
select * from cc_t1
where date_part('month', dt) = 5 