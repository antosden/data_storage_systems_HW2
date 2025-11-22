-- 1. Вывести все уникальные бренды, у которых есть хотя бы один продукт со стандартной стоимостью выше 1500 долларов, и суммарными продажами не менее 1000 единиц.

select p.brand from product p 
join order_items oi on oi.product_id = p.product_id 
group by p.brand
having sum(oi.quantity) >= 1000
	and max(p.standard_cost) > 1500

-- 2. Для каждого дня в диапазоне с 2017-04-01 по 2017-04-09 включительно вывести количество подтвержденных онлайн-заказов и количество уникальных клиентов, совершивших эти заказы.

select order_date, count(o.order_id) as orders, count(distinct o.customer_id) unique_customers from orders o 
where 1=1
	and o.order_date::date between '2017-04-01' and '2017-04-09'
	and o.order_status = 'Approved'
group by order_date

/*  3. Вывести профессии клиентов:
        из сферы IT, чья профессия начинается с Senior;
        из сферы Financial Services, чья профессия начинается с Lead.

        Для обеих групп учитывать только клиентов старше 35 лет. Объединить выборки с помощью UNION ALL.
*/

with jobs as (
	select job_title, c.job_industry_category from customer c 
		where 1=1 
		and c."DOB" <> ''
		and c."DOB"::date <= current_date - interval '35 year'
		and c.job_industry_category in ('IT', 'Financial Services')
)
select job_title from jobs 
	where 1=1
	and job_industry_category = 'IT' and job_title like 'Senior%'
union all
select job_title from jobs 
	where 1=1
	and job_industry_category = 'Financial Services' and job_title like 'Lead%';

--  4. Вывести бренды, которые были куплены клиентами из сферы Financial Services, но не были куплены клиентами из сферы IT.

with brands_fs as (
    select distinct p.brand 
    from orders o 
    join customer c on c.customer_id = o.customer_id
    join order_items oi on oi.order_id = o.order_id 
    join product p on oi.product_id = p.product_id 
    where c.job_industry_category = 'Financial Services'
),
brands_it as (
    select distinct p.brand 
    from orders o 
    join customer c on c.customer_id = o.customer_id
    join order_items oi on oi.order_id = o.order_id 
    join product p on oi.product_id = p.product_id 
    where c.job_industry_category = 'IT'
)
select brand 
from brands_fs
where brand not in (select brand from brands_it);

-- 5. Вывести 10 клиентов (ID, имя, фамилия), которые совершили наибольшее количество онлайн-заказов (в штуках) брендов Giant Bicycles, Norco Bicycles, Trek Bicycles, при условии, 
-- что они активны и имеют оценку имущества (property_valuation) выше среднего среди клиентов из того же штата.

with avg_prop_val as (
	-- Средняя оценка имущества по штату
	select c.state, avg(c.property_valuation) avg_prop_val from customer c
	group by 1
),
popular_customers as (
	-- Клиенты с покупками по указанным брендам, отсортированные по количеству покупок по убыванию
	select c.customer_id, count(1) from customer c 
		join orders o on c.customer_id = o.customer_id 
		join order_items oi on oi.order_id = o.order_id 
		join product p on p.product_id = oi.product_id 
		where 1=1 
			and p.brand in ('Giant Bicycles', 'Norco Bicycles', 'Trek Bicycles')
			and o.online_order is true
			group by 1
			order by 2 desc
),
top_prop_val as (
-- Все активные клиенты у которых оценка имущества выше среднего
select c.customer_id, c.first_name, c.last_name, c.state  from customer c
		join avg_prop_val apv on c.state = apv.state 
		where 1=1
			and c.deceased_indicator = 'N'
			and c.property_valuation > apv.avg_prop_val 
		)
-- Отбираем из всех клиентов top_prop_val тех что входят в popular_customers
select tpv.customer_id, tpv.first_name, tpv.last_name from popular_customers pc
join top_prop_val tpv on pc.customer_id = tpv.customer_id 
order by pc.count desc
limit 10

-- 6. Вывести всех клиентов (ID, имя, фамилия), у которых нет подтвержденных онлайн-заказов за последний год, но при этом они владеют автомобилем и их сегмент благосостояния не Mass Customer.
select customer_id, first_name, last_name from customer c 
	where 1=1
		and c.wealth_segment <> 'Mass Customer'
		and c.owns_car = 'Yes'
		and c.customer_id not in (
			select customer_id from orders
				where 1=1
					and online_order is true
					and order_status = 'Approved'
					and order_date::date > current_date - interval '1 year'
		);

-- 7. Вывести всех клиентов из сферы 'IT' (ID, имя, фамилия), которые купили 2 из 5 продуктов с самой высокой list_price в продуктовой линейке Road.

with top_products as (
    select product_id from product 
    where product_line = 'Road'
    order by list_price desc 
    limit 5
)
select 
    c.customer_id,
    c.first_name,
    c.last_name
from customer c
join orders o on o.customer_id = c.customer_id 
join order_items oi on oi.order_id = o.order_id 
where c.job_industry_category = 'IT'
  and oi.product_id in (select product_id from top_products)
group by c.customer_id, c.first_name, c.last_name
having count(distinct oi.product_id) = 2;


/* 8. Вывести клиентов (ID, имя, фамилия, сфера деятельности) из сфер IT или Health, которые совершили не менее 3 подтвержденных заказов в период 2017-01-01 по 2017-03-01, и при этом их общий доход от этих заказов превышает 10 000 долларов.

    Разделить вывод на две группы (IT и Health) с помощью UNION.	
    */	

with customer_orders as (
    select 
        c.customer_id,
        c.first_name,
        c.last_name, 
        c.job_industry_category,
        count(*) as order_count,
        sum(oi.quantity * p.list_price) as total_revenue
    from customer c
    join orders o on c.customer_id = o.customer_id
    join order_items oi on o.order_id = oi.order_id
    join product p on oi.product_id = p.product_id
    where c.job_industry_category in ('IT', 'Health')
      and o.order_date::date between '2017-01-01' and '2017-03-01'
      and o.order_status = 'Approved'
    group by c.customer_id, c.first_name, c.last_name, c.job_industry_category
    having count(1) >= 3 
       and sum(oi.quantity * p.list_price) > 10000
)
select 
    customer_id,
    first_name,
    last_name,
    job_industry_category
from customer_orders 
where job_industry_category = 'IT'
union all
select 
    customer_id,
    first_name,
    last_name,
    job_industry_category  
from customer_orders 
where job_industry_category = 'Health'
order by job_industry_category, customer_id;

