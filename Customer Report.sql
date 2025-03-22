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
