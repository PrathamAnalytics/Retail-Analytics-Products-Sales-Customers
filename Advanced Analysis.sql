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


/*===========================================================================
                              CUSTOMER REPORT
=============================================================================
Purpose:
	- This report consolidates key customer metrics and behaviors.

Highlights:
	1. Gathers essential fields such as names, ages, and transaction details.
	2. Segments customers into categories (VIP, Regular, New) and age groups.
	3. Aggregates customer-level metrics:
		- total orders
		- total sales 
		- total quantity purchased 
		- total products
		- lifespan (in months)
	4. Calculates valuable KPIs: 
		- recency (months since last order)
		- average order value (AOV)
		- average monthly spend
===========================================================================*/

CREATE VIEW customers_report AS 
WITH base_query AS (
/*------------------------------------------------
1. Base Query: Retrieves core columns from tables.
------------------------------------------------*/
	SELECT
		s.order_number,
		s.product_key,
		s.order_date,
		s.sales_amount,
		s.quantity, 
		c.customer_key,
		c.customer_number,
		CONCAT(c.first_name, ' ', c.last_name) AS customer_name,
		EXTRACT(YEAR FROM AGE(current_date, c.birthdate)) AS age
	FROM fact_sales AS s
	LEFT JOIN dim_customers AS c
		ON s.customer_key = c.customer_key
	WHERE order_date IS NOT NULL
),
customer_aggregations AS (
/*---------------------------------------------------------------------
2. Customer Aggregations: Summarizes key metrics at the customer level.
---------------------------------------------------------------------*/
SELECT
	customer_key,
	customer_number,
	customer_name,
    age,
	COUNT(DISTINCT order_number) AS total_sales_orders,
	SUM(sales_amount) AS total_sales,
	SUM(quantity) AS total_quantity,
	COUNT(DISTINCT product_key) AS total_products,
	MAX(order_date) AS last_order_date,
	(EXTRACT(YEAR FROM AGE(MAX(order_date), MIN(order_date))) * 12) + EXTRACT(MONTH FROM AGE(MAX(order_date), MIN(order_date))) AS lifespan
FROM base_query
GROUP BY 
	customer_key,
	customer_number,
	customer_name,
    age
)
/*------------------------------------------------------------
3. Final Query: Combines all customer results into one output.
------------------------------------------------------------*/
SELECT 
	customer_key,
	customer_number,
	customer_name,
    age,
	-- Categorize customers into age groups
	CASE 
		WHEN age < 20 THEN 'Under 20'
		WHEN age BETWEEN 20 AND 29 THEN '20-29'
		WHEN age BETWEEN 30 AND 39 THEN '30-39'
		WHEN age BETWEEN 40 AND 49 THEN '40-49'
		ELSE '50 and above'
	END AS age_group,
	-- Segment customers based on total sales and lifespan
	CASE 
		WHEN lifespan >= 12 AND total_sales > 5000 THEN 'VIP'
		WHEN lifespan >= 12 AND total_sales <= 5000 THEN 'Regular'
		ELSE 'New'
	END AS customer_segment,
	last_order_date,
	-- Calculate months since last order (recency)
	(EXTRACT(YEAR FROM AGE(current_date, last_order_date)) * 12) + EXTRACT(MONTH FROM AGE(current_date, last_order_date)) AS recency,
    total_sales_orders,
	total_sales,
	total_quantity,
	total_products,
	lifespan,
	-- Average Order Value (AOV)
	CASE
		WHEN total_sales = 0 THEN 0
		ELSE total_sales / total_sales_orders 
	END AS avg_order_value,
	-- Average Monthly Spend
	CASE 
		WHEN lifespan = 0 THEN total_sales
		ELSE ROUND((total_sales / lifespan), 0)
	END AS avg_monthly_spend
FROM customer_aggregations;

/*===========================================================================
                                PRODUCT REPORT
=============================================================================
Purpose:
	- This report consolidates key product metrics and behaviors.

Highlights:
	1. Gathers essential fields such as product name, category, subcategory, and cost.
	2. Segments products by revenue to identify High-Performers, Mid-Range, or Low-Performers.
	3. Aggregates product-level metrics:
		- total orders
		- total sales 
		- total quantity sold 
		- total customers (unique)
		- lifespan (in months)
	4. Calculates valuable KPIs: 
		- recency (months since last sale)
		- average order revenue (AOR)
		- average monthly revenue
===========================================================================*/

CREATE VIEW products_report AS 
WITH base_query AS (
/*---------------------------------------------------------------------
1. Base Query: Retrieves core columns from fact_sales and dim_products.
---------------------------------------------------------------------*/
	SELECT
		s.order_number,
		s.order_date,
		s.customer_key,
		s.sales_amount,
		s.quantity,
		p.product_key,
		p.product_name,
		p.category,
		p.subcategory,
		p.cost
	FROM fact_sales AS s
	LEFT JOIN dim_products AS p
		ON s.product_key = p.product_key
	WHERE order_date IS NOT NULL 
),
product_aggregations AS (
/*-------------------------------------------------------------------
2. Product Aggregations: Summarizes key metrics at the product level.
-------------------------------------------------------------------*/
	SELECT 
		product_key,
		product_name,
		category,
		subcategory,
		cost,
		-- Calculate product lifespan in months
		(EXTRACT(YEAR FROM AGE(MAX(order_date), MIN(order_date))) * 12) + EXTRACT(MONTH FROM AGE(MAX(order_date), MIN(order_date))) AS lifespan,
		MAX(order_date) AS last_sale_date,
		COUNT(DISTINCT order_number) AS total_orders,
		COUNT(DISTINCT customer_key) AS total_customers,
		SUM(sales_amount) AS total_sales,
		SUM(quantity) AS total_quantity,
		-- Calculate average selling price per unit
		ROUND(AVG(sales_amount::NUMERIC / NULLIF(quantity, 0))::NUMERIC, 1) AS avg_selling_price
	FROM base_query
	GROUP BY 
		product_key,
		product_name,
		category,
		subcategory,
		cost
)
/*------------------------------------------------------------
3. Final Query: Combines all product results into one output.
------------------------------------------------------------*/
SELECT 
	product_key,
	product_name,
	category,
	subcategory,
	cost,
    last_sale_date,
	-- Calculate months since last sale (recency)
	(EXTRACT(YEAR FROM AGE(current_date, last_sale_date)) * 12) + EXTRACT(MONTH FROM AGE(current_date, last_sale_date)) AS recency,
	-- Segment products based on total revenue
	CASE 
		WHEN total_sales > 50000 THEN 'High-Performer'
		WHEN total_sales >= 10000 THEN 'Mid-Range'
		ELSE 'Low-Performer'
	END AS product_segment,
	lifespan,
	total_orders,
	total_sales,
	total_quantity,
	total_customers,
	avg_selling_price,
	-- Average Order Revenue (AOR)
	CASE
		WHEN total_orders = 0 THEN 0
		ELSE total_sales / total_orders 
	END AS avg_order_revenue,
	-- Average Monthly Revenue
	CASE 
		WHEN lifespan = 0 THEN total_sales
		ELSE ROUND((total_sales / lifespan), 0)
	END AS avg_monthly_revenue
FROM product_aggregations;



