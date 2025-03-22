CREATE TABLE dim_customers(
	customer_key int,
	customer_id int,
	customer_number nvarchar(50),
	first_name nvarchar(50),
	last_name nvarchar(50),
	country nvarchar(50),
	marital_status nvarchar(50),
	gender nvarchar(50),
	birthdate date,
	create_date date
);

CREATE TABLE dim_products(
	product_key int ,
	product_id int ,
	product_number nvarchar(50) ,
	product_name nvarchar(50) ,
	category_id nvarchar(50) ,
	category nvarchar(50) ,
	subcategory nvarchar(50) ,
	maintenance nvarchar(50) ,
	cost int,
	product_line nvarchar(50),
	start_date date 
);

CREATE TABLE fact_sales(
	order_number nvarchar(50),
	product_key int,
	customer_key int,
	order_date date,
	shipping_date date,
	due_date date,
	sales_amount int,
	quantity tinyint,
	price int 
);

/*==============================================================
LOAD DATA INTO CUSTOMERS, PRODUCTS & SALES TABLES FROM CSV FILES
==============================================================*/

COPY dim_customers FROM 'D:\\Pratham\\sql-data-analytics-project-main\\datasets\\csv-files\\gold.dim_customers.csv' 
DELIMITER ',' 
CSV HEADER;

COPY dim_products FROM 'D:\\Pratham\\sql-data-analytics-project-main\\datasets\\csv-files\\gold.dim_products.csv' 
DELIMITER ',' 
CSV HEADER;

COPY fact_sales FROM 'D:\\Pratham\\sql-data-analytics-project-main\\datasets\\csv-files\\gold.fact_sales.csv' 
DELIMITER ',' 
CSV HEADER;

/*========================================================================
                     Exploratory Data Analysis (EDA) 
========================================================================*/

-- 1. Explore All Countries our customers come from.

SELECT DISTINCT country 
FROM dim_customers;

-- 2. Explore All Categories "The Major Divisons".

SELECT DISTINCT 
	category, 
	subcategory, 
	product_name 
FROM dim_products
ORDER BY 
	category, 
	subcategory, 
	product_name;

-- 3. Find the date of the first and last order date.

SELECT 
    MIN(order_date) AS first_order_date,  -- Earliest order recorded
    MAX(order_date) AS last_order_date   -- Most recent order recorded
FROM fact_sales;

-- 4. Calculate how many years of sales are available.

SELECT 
    EXTRACT(YEAR FROM AGE(MAX(order_date), MIN(order_date))) AS order_range_years  -- Difference in years between first and last order
FROM fact_sales;

-- 5. Find the youngest and the oldest customer based on birthdate.

SELECT
	MAX(birthdate) AS youngest_customer_birthdate,  -- Most recent birthdate (youngest customer)
	EXTRACT(YEAR FROM AGE(CURRENT_DATE, MIN(birthdate))) AS oldest_customer_age,  -- Age of the oldest customer
	MIN(birthdate) AS oldest_customer_birthdate,  -- Earliest birthdate (oldest customer)
	EXTRACT(YEAR FROM AGE(CURRENT_DATE, MAX(birthdate))) AS youngest_customer_age  -- Age of the youngest customer
FROM dim_customers;

-- 6. Find the total sales.

SELECT SUM(sales_amount) AS total_sales 
FROM fact_sales;

-- 7. Find the total number of items sold.

SELECT SUM(quantity) AS total_quantity
FROM fact_sales;

-- 8. Find the average selling price of products.

SELECT ROUND(AVG(price), 0) AS avg_price 
FROM fact_sales;

-- 9. Find the total number of orders placed.

SELECT COUNT(order_number) AS total_orders
FROM fact_sales;

-- 10. Find the number of unique orders placed.

SELECT COUNT(DISTINCT order_number) AS total_orders
FROM fact_sales;

-- 11. Find the total number of products.

SELECT COUNT(product_name) AS total_products 
FROM dim_products;

-- 12. Find the number of unique products.

SELECT COUNT(DISTINCT product_name) AS total_products 
FROM dim_products;

-- 13. Find the total number of customers.

SELECT COUNT(customer_id) AS total_customers
FROM dim_customers;

-- 14. Find the number of unique customers who have placed at least one order.

SELECT COUNT(DISTINCT customer_key) AS total_customers
FROM fact_sales;

-- 15. Generate a Report that shows all key business metrics.

SELECT 'Total Sales' AS measure_name, SUM(sales_amount) AS measure_value 
FROM fact_sales
UNION ALL 
SELECT 'Total Quantity', SUM(quantity)  
FROM fact_sales
UNION ALL 
SELECT 'Average Price', ROUND(AVG(price), 0) 
FROM fact_sales
UNION ALL
SELECT 'Total Orders', COUNT(DISTINCT order_number) 
FROM fact_sales
UNION ALL
SELECT 'Total Products', COUNT(DISTINCT product_name) 
FROM dim_products
UNION ALL
SELECT 'Total Customers', COUNT(customer_id) 
FROM dim_customers;

-- 16. Find total customers by country.

SELECT 
	country,
	COUNT(customer_id) AS total_customers
FROM dim_customers
GROUP BY country
ORDER BY total_customers DESC; 

-- 17. Find total customers by gender.

SELECT 
	gender,
	COUNT(customer_id) AS total_customers
FROM dim_customers
GROUP BY gender
ORDER BY total_customers DESC; 

-- 18. Find total products by category.

SELECT 
	category,
	COUNT(product_name) AS total_products
FROM dim_products
GROUP BY category
ORDER BY total_products DESC; 

-- 19. Find the average cost of products in each category.

SELECT 
	category,
	ROUND(AVG(cost), 0) AS avg_costs
FROM dim_products
GROUP BY category
ORDER BY avg_costs DESC; 

-- 20. Find total revenue generated for each category.

SELECT 
	p.category,
	SUM(s.sales_amount) AS total_revenue
FROM dim_products AS p
JOIN fact_sales AS s
	ON p.product_key = s.product_key
GROUP BY p.category
ORDER BY total_revenue DESC; 

-- 21. Find total revenue generated by each customer.

SELECT 
	c.customer_id,
	c.first_name,
	c.last_name,
	SUM(s.sales_amount) AS total_revenue
FROM dim_customers AS c
JOIN fact_sales AS s
	ON c.customer_key = s.customer_key
GROUP BY 
	c.customer_id,
	c.first_name,
	c.last_name
ORDER BY total_revenue DESC; 

-- 22. Find the distribution of sold items across countries.

SELECT 
	c.country,
	SUM(s.quantity) AS total_sold_items
FROM dim_customers AS c
JOIN fact_sales AS s
	ON c.customer_key = s.customer_key
GROUP BY c.country
ORDER BY total_sold_items DESC;

-- 23. Find the top 5 products generating the highest revenue.

SELECT 
	p.product_name,
	SUM(s.sales_amount) AS total_revenue
FROM dim_products AS p
JOIN fact_sales AS s
	ON p.product_key = s.product_key
GROUP BY p.product_name
ORDER BY total_revenue DESC
LIMIT 5;

-- 24. Alternative: Using ROW_NUMBER() to rank the top 5 products by revenue.

SELECT *
FROM 
	 (SELECT 
		p.product_name,
		SUM(s.sales_amount) AS total_revenue,
		ROW_NUMBER() OVER(ORDER BY SUM(s.sales_amount) DESC) AS rank_products
	FROM dim_products AS p
	JOIN fact_sales AS s
		ON p.product_key = s.product_key
	GROUP BY p.product_name)
WHERE rank_products <= 5;

-- 25. Find the 5 worst-performing products in terms of revenue.

SELECT 
	p.product_name,
	SUM(s.sales_amount) AS total_revenue
FROM dim_products AS p
JOIN fact_sales AS s
	ON p.product_key = s.product_key
GROUP BY p.product_name
ORDER BY total_revenue ASC
LIMIT 5;

-- 26. Find the Top 10 customers who have generated the highest revenue.

SELECT 
	c.customer_id,
	c.first_name,
	c.last_name,
	SUM(s.sales_amount) AS total_revenue
FROM dim_customers AS c
JOIN fact_sales AS s
	ON c.customer_key = s.customer_key
GROUP BY 
	c.customer_id,
	c.first_name,
	c.last_name
ORDER BY total_revenue DESC
LIMIT 10; 

-- 27. Find the 3 customers with the fewest orders placed.

SELECT 
	c.customer_id,
	c.first_name,
	c.last_name,
	COUNT(DISTINCT order_number) AS total_orders
FROM dim_customers AS c
JOIN fact_sales AS s
	ON c.customer_key = s.customer_key
GROUP BY 
	c.customer_id,
	c.first_name,
	c.last_name
ORDER BY total_orders ASC
LIMIT 3; 

