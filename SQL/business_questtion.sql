use quick_bite
-- Q1. Monthly Order Trend
-- Goal: Measure how severely orders declined after the June 2025 crisis
-- This is the first thing leadership wants to see - the headline decline number
select 
FORMAT(order_timestamp,'yyyy-MM') as month,phase,
count(order_id) as total_orders
from fact_orders
group by FORMAT(order_timestamp,'yyyy-MM'),phase
order by month

-- Q2. Revenue Impact by Business Phase
-- Goal: Quantify the actual revenue loss caused by the crisis
-- Using total_amount which is post-discount, post-fee final amount

SELECT
   phase,

    COUNT(order_id) AS total_orders,

    ROUND(SUM(total_amount), 2) AS total_revenue,

    ROUND(SUM(total_amount) / 10000000, 2) AS revenue_in_crores,

    ROUND(AVG(total_amount), 2) AS avg_order_value

FROM fact_orders
WHERE is_cancelled = 'N'
GROUP BY phase
ORDER BY
    CASE phase
        WHEN 'Pre-Crisis' THEN 1
        WHEN 'Crisis' THEN 2
        ELSE 3
    END;
-- Q3. City-wise Cancellation Rate by Phase
-- Goal: Identify which cities had the worst cancellation problem
-- Helps prioritize where to focus operational recovery efforts
select 
r.city,
f.phase,
count(f.order_id) as total_order,
sum(case  when f.is_cancelled='Y' then 1 else 0 end) as cancelled_order,
 ROUND(
        SUM(CASE WHEN f.is_cancelled = 'Y' THEN 1 ELSE 0 END) * 100.0 / COUNT(f.order_id),
        2
    ) AS cancellation_rate_pct

from fact_orders f left join dim_restaurant r
on f.restaurant_id=r.restaurant_id
group by f.phase,r.city
order by cancellation_rate_pct desc

-- Q4. Restaurants with Highest Order Decline During Crisis
-- Goal: Identify which restaurant partners were most impacted
-- Using monthly average to make pre-crisis (5 months) and crisis (2 months) comparable
-- Threshold set to monthly avg >= 2 orders which equals 10+ total pre-crisis orders

select 
   r.restaurant_name,r.city,r.cuisine_type,
   sum(case phase when 'Pre-Crisis' then  1 else 0 end)/5 *1.0as avg_monthly_pre_crisis,
   sum(case phase when 'Crisis' then  1 else 0 end)/2 *1.0 as avg_Monthly_crisis_avg,
   round(
   ((sum(case phase when 'Pre-Crisis' then  1 else 0 end)/5)-(sum(case phase when 'Crisis' then  1 else 0 end)*1.0/2) )
   /(sum(case phase when 'Pre-Crisis' then  1 else 0 end)/5)  *100
   , 2 )
   as decline_pct
   from fact_orders f left join dim_restaurant r
   on f.restaurant_id=r.restaurant_id
   group by r.restaurant_name,r.city,r.cuisine_type
   having sum(case phase when 'Pre-Crisis' then  1 else 0 end)/5  >= 2
   order by decline_pct desc

  -- Q5. Delivery SLA Performance by Phase
-- Goal: Measure how delivery performance deteriorated across phases
-- SLA breach = actual delivery time exceeded expected delivery time


 select 
 avg(dp.expected_delivery_time_mins - dp.actual_delivery_time_mins) as SLA 
 from fact_orders f left join fact_delivery_performance as dp on 
 f.order_id=dp.order_id
 group by  phase
 order by case phase when 'Pre-Crisis' then 0
                      when 'Cisis' then 1
                      else 2
                      end


-- Q6. Loyal Customer Churn Analysis
-- Goal: Find how many loyal customers stopped ordering during crisis
-- Loyal = customers who placed 2 or more orders before crisis
-- Only counting non-cancelled orders to measure genuine ordering behavior
WITH loyal_customers AS (

    SELECT
        customer_id,
        COUNT(order_id) AS pre_crisis_orders
    FROM fact_orders
    WHERE phase='Pre-Crisis'
      
    GROUP BY customer_id
    HAVING COUNT(order_id) >= 2
),
 crisis_active AS (

    SELECT DISTINCT customer_id
    FROM fact_orders
    WHERE phase='Crisis'
 )
SELECT
    COUNT(l.customer_id) AS total_loyal_customers,

    SUM(CASE WHEN ca.customer_id IS NULL THEN 1 ELSE 0 END) AS churned_loyal_customers,

    SUM(CASE WHEN ca.customer_id IS NOT NULL THEN 1 ELSE 0 END) AS retained_loyal_customers,

    ROUND(
        SUM(CASE WHEN ca.customer_id IS NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(l.customer_id),
        2
    ) AS churn_rate_pct

FROM loyal_customers as l
LEFT JOIN crisis_active ca ON l.customer_id = ca.customer_id;


 -- Q7. High-Value Customers by City
-- Goal: Identify which cities have the most high-value customers
-- High-value = top 5% by total spend during pre-crisis period
-- Using NTILE(20) window function - group 1 represents top 5%

with high_value_cust as (
select 
f.customer_id,c.city,
sum(f.total_amount) as total_amount
from
fact_orders f
left join dim_customer c on f.customer_id=c.customer_id
where phase ='Pre-Crisis'
group by c.city, f.customer_id
), 
ranked_customers  as(
select 
customer_id,
city,
total_amount,
ntile(20) over( order by total_amount desc ) as top_
from high_value_cust)


SELECT
    city,
    COUNT(customer_id) AS high_value_customers,
    ROUND(AVG(total_amount), 2) AS avg_spend_per_customer,
    ROUND(MIN(total_amount), 2) AS min_spend_threshold
FROM ranked_customers
WHERE top_ = 1
GROUP BY city

-- Q8. Monthly Customer Rating and Sentiment Trend
-- Goal: Track when customer satisfaction dropped and by how much
-- Joining on order_id to get the phase context from fact_orders

SELECT
    FORMAT(o.order_timestamp, 'yyyy-MM') AS order_month,
    phase,

    COUNT(r.order_id) AS total_reviews,

    ROUND(AVG(r.rating), 2) AS avg_rating,

    ROUND(AVG(r.sentiment_score), 2) AS avg_sentiment_score

FROM fact_orders o
JOIN fact_ratings r ON o.order_id = r.order_id

GROUP BY FORMAT(o.order_timestamp, 'yyyy-MM'), phase

ORDER BY order_month;


-- Q9. Delivery Delay Impact on Customer Ratings
-- Goal: Confirm whether late deliveries directly caused lower ratings
-- This validates that fixing delivery will improve satisfaction scores

SELECT
    CASE
        WHEN d.actual_delivery_time_mins > d.expected_delivery_time_mins
        THEN 'Delayed'
        ELSE 'On Time'
    END AS delivery_status,
    COUNT(o.order_id) AS total_orders,
    ROUND(AVG(r.rating), 2) AS avg_customer_rating,
    ROUND(AVG(r.sentiment_score), 2) AS avg_sentiment_score,
    ROUND(AVG(d.actual_delivery_time_mins), 2) AS avg_delivery_mins
FROM fact_orders o
JOIN fact_delivery_performance d ON o.order_id = d.order_id
JOIN fact_ratings r ON o.order_id = r.order_id
GROUP BY CASE WHEN d.actual_delivery_time_mins > d.expected_delivery_time_mins
        THEN 'Delayed'
        ELSE 'On Time'
        end
-- Q10. Recovery Phase Effectiveness
-- Goal: Evaluate whether recovery efforts actually improved anything
-- This is a consolidated phase comparison across all key metrics
-- Critical finding: recovery phase metrics remain identical to crisis levels

SELECT
   phase,

    COUNT(o.order_id) AS total_orders,
    ROUND(AVG(r.rating), 2) AS avg_rating,
    ROUND(AVG(r.sentiment_score), 2) AS avg_sentiment,
    ROUND(AVG(d.actual_delivery_time_mins), 2) AS avg_delivery_mins,
    ROUND(
        SUM(CASE WHEN d.actual_delivery_time_mins > d.expected_delivery_time_mins THEN 1 ELSE 0 END)
        * 100.0 / COUNT(o.order_id),
        2
    ) AS sla_breach_pct,
   ROUND(
        SUM(CASE WHEN o.is_cancelled = 'Y' THEN 1 ELSE 0 END) * 100.0 / COUNT(o.order_id),
        2
    ) AS cancellation_rate_pct

FROM fact_orders o
LEFT JOIN fact_ratings r ON o.order_id = r.order_id
LEFT JOIN fact_delivery_performance d ON o.order_id = d.order_id

GROUP BY phase
ORDER BY
    CASE phase
        WHEN 'Pre-Crisis' THEN 1
        WHEN 'Crisis' THEN 2
        ELSE 3
    END;




























