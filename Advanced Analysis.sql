/*========================================================================
                          Advanced Analysis 
========================================================================*/

-- 1. Change Over Time Analysis: Aggregates sales, unique customers, and quantity by year and month.

SELECT 
	EXTRACT(YEAR FROM order_date) AS order_year,
	EXTRACT(MONTH FROM order_date) AS order_month, 
	SUM(sales_amount) AS total_sales,
	COUNT(DISTINCT customer_key) AS total_customers,
	SUM(quantity) as total_quantity
FROM fact_sales
WHERE order_date IS NOT NULL
GROUP BY 
	order_year, 
	order_month
ORDER BY 
	order_year, 
	order_month;

-- 2. Calculate total sales per month using DATE_TRUNC to group by month.

SELECT 
	DATE_TRUNC('month', order_date) :: DATE AS order_month,
	SUM(sales_amount) AS total_sales
FROM fact_sales
GROUP BY DATE_TRUNC('month', order_date) :: DATE
ORDER BY order_month;

-- 3. Calculate the running total of sales over time along with a moving average price.

SELECT
	order_date,
	total_sales,
	SUM(total_sales) OVER (ORDER BY order_date) AS running_total_sales,
	ROUND(AVG(avg_price) OVER (ORDER BY order_date), 2) AS moving_average_price
FROM 
(
	SELECT  
		DATE_TRUNC('year', order_date) :: DATE AS order_date,
		SUM(sales_amount) AS total_sales,
		AVG(price) AS avg_price
	FROM fact_sales
	WHERE order_date IS NOT NULL
	GROUP BY DATE_TRUNC('year', order_date) :: DATE
);

/* 4. Yearly product performance analysis:
   - Compares each product's sales to its average sales across years.
   - Compares sales to the previous year's performance. */

WITH yearly_product_sales AS (
	SELECT
		EXTRACT(YEAR FROM s.order_date) AS order_year,
		p.product_name,
		SUM(s.sales_amount) AS current_sales
	FROM fact_sales AS s
	LEFT JOIN dim_products AS p
		ON s.product_key = p.product_key
	WHERE s.order_date IS NOT NULL
	GROUP BY 
		EXTRACT(YEAR FROM s.order_date),
		p.product_name
)
SELECT 
	order_year,
	product_name,
	current_sales,
	ROUND(AVG(current_sales) OVER (PARTITION BY product_name), 0) AS avg_sales,
	current_sales - ROUND(AVG(current_sales) OVER (PARTITION BY product_name), 0) AS diff_avg,
	CASE 
		WHEN current_sales - ROUND(AVG(current_sales) OVER (PARTITION BY product_name), 0) > 0 THEN 'Above Avg'
		WHEN current_sales - ROUND(AVG(current_sales) OVER (PARTITION BY product_name), 0) < 0 THEN 'Below Avg'
		ELSE 'Avg'
	END AS avg_change,
	LAG(current_sales) OVER (PARTITION BY product_name ORDER BY order_year) AS previous_year_sales,
	current_sales - LAG(current_sales) OVER (PARTITION BY product_name ORDER BY order_year) AS diff_previous_year,
	CASE 
		WHEN current_sales - LAG(current_sales) OVER (PARTITION BY product_name ORDER BY order_year) > 0 THEN 'Increase'
		WHEN current_sales - LAG(current_sales) OVER (PARTITION BY product_name ORDER BY order_year) < 0 THEN 'Decrease'
		ELSE 'No Change'
	END AS previous_year_change
FROM yearly_product_sales
ORDER BY 
	product_name, 
	order_year;

-- 5. Identify categories that contribute most to overall sales.

WITH category_sales AS (
	SELECT
		p.category,
		SUM(s.sales_amount) AS total_sales
	FROM fact_sales AS s
	LEFT JOIN dim_products AS p
		ON p.product_key = s.product_key
	Group BY p.category
)
SELECT 
	category,
	total_sales,
	SUM(total_sales) OVER () AS overall_sales,
	CONCAT(ROUND((total_sales :: NUMERIC / SUM(total_sales) OVER() :: NUMERIC) * 100, 2), '%') AS percentage_of_total_sales
FROM category_sales
ORDER BY total_sales DESC;

-- 6. Segment products into cost ranges and count how many products fall into each segment.

WITH product_segments AS (
	SELECT
		product_key,
		product_name,
		cost,
		CASE 
			WHEN cost < 100 THEN 'Below 100'
			WHEN cost BETWEEN 100 AND 500 THEN '100-500'
			WHEN cost BETWEEN 500 AND 1000 THEN '500-1000'
		    ELSE 'Above 1000'
		END AS cost_range
	FROM dim_products
)
SELECT 
	cost_range,
	COUNT(product_key) AS total_products
FROM product_segments
GROUP BY cost_range
ORDER BY total_products DESC;

/* 7. Segment customers based on spending behavior: 
 - VIP: Customers with at least 12 months of history and spending more than $5000.
 - Regular: Customers with at least 12 months of history but spending $5000 or less.
 - New: Customers with a lifespan less than 12 months.
And find the total number of customers by each group. */

WITH customer_spending AS (
	SELECT 
		c.customer_key,
		SUM(s.sales_amount) AS total_spending,
		MIN(s.order_date) AS first_order,
		MAX(s.order_date) AS last_order,
		EXTRACT(YEAR FROM AGE(MAX(order_date), MIN(order_date))) * 12 + EXTRACT(MONTH FROM AGE(MAX(order_date), MIN(order_date))) AS lifespan
	FROM fact_sales AS s
	LEFT JOIN dim_customers AS c
		ON s.customer_key = c.customer_key
	GROUP BY c.customer_key
)
SELECT 
	customer_segment,
	COUNT(customer_key) AS total_customers
FROM (
	SELECT 
		customer_key,
		CASE 
			WHEN lifespan >= 12 AND total_spending > 5000 THEN 'VIP'
			WHEN lifespan >= 12 AND total_spending <= 5000 THEN 'Regular'
			ELSE 'New'
		END AS customer_segment
	FROM customer_spending
)
GROUP BY customer_segment
ORDER BY total_customers DESC;




