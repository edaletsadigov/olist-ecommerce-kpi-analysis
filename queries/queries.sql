-- Q1 Row counts per table, and the join cardinality between orders and order_items (how many items does an average order have?)
                -- Row counts per table
SELECT 'name_translation' AS table_name, COUNT(*) AS row_count FROM name_translation
UNION ALL SELECT 'olist_customers', COUNT(*) FROM olist_customers
UNION ALL SELECT 'olist_geolocation', COUNT(*) FROM olist_geolocation
UNION ALL SELECT 'olist_orders', COUNT(*) FROM olist_orders
UNION ALL SELECT 'olist_order_items', COUNT(*) FROM olist_order_items
UNION ALL SELECT 'olist_order_payments', COUNT(*) FROM olist_order_payments
UNION ALL SELECT 'olist_order_reviews', COUNT(*) FROM olist_order_reviews
UNION ALL SELECT 'olist_products', COUNT(*) FROM olist_products
UNION ALL SELECT 'olist_sellers', COUNT(*) FROM olist_sellers;
-- Join cardinality: items per order (orders without items are excluded)
WITH order_item_counts AS (
    SELECT order_id, COUNT(*) AS items_per_order
    FROM olist_order_items
    GROUP BY order_id
)
SELECT COUNT(*)                        AS orders_with_items,
       ROUND(AVG(items_per_order), 3)  AS avg_items_per_order,
       MEDIAN(items_per_order)         AS median_items_per_order,
       MAX(items_per_order)            AS max_items_per_order
FROM order_item_counts;

-- Q2 Build the analytical base: orders joined to order_items, products, category translation and reviews, filtered to order_status = 'delivered'. Make this a VIEW or a CTE you reuse.
-- Item grain: one row per order item, delivered orders only
CREATE OR REPLACE VIEW v_analytical_base AS
WITH latest_review AS (
    SELECT order_id, review_score
    FROM (
        SELECT order_id,
               review_score,
               ROW_NUMBER() OVER (
                   PARTITION BY order_id
                   ORDER BY review_answer_timestamp DESC, review_id
               ) AS rn
        FROM olist_order_reviews
    )
    WHERE rn = 1
)
SELECT
    o.order_id,
    o.customer_id,
    TRUNC(o.order_purchase_timestamp)       AS order_purchase_date,
    TRUNC(o.order_delivered_customer_date)  AS order_delivered_date,
    TRUNC(o.order_delivered_customer_date)
      - TRUNC(o.order_purchase_timestamp)   AS delivery_days,
    oi.order_item_id,
    oi.product_id,
    oi.seller_id,
    oi.price,
    oi.freight_value,
    COALESCE(nt.name_english,
             p.product_category_name,
             'unknown')                     AS category_name,
    s.seller_city,
    s.seller_state,
    lr.review_score
FROM olist_orders o
JOIN olist_order_items oi ON oi.order_id = o.order_id
LEFT JOIN olist_products p ON p.product_id = oi.product_id
LEFT JOIN name_translation nt ON nt.name = p.product_category_name
LEFT JOIN olist_sellers s ON s.seller_id = oi.seller_id
LEFT JOIN latest_review lr ON lr.order_id = o.order_id
WHERE o.order_status = 'delivered';
-- Order grain: used for AOV, delivery and review averages
CREATE OR REPLACE VIEW v_order_base AS
SELECT order_id,
       MIN(order_purchase_date) AS order_purchase_date,
       SUM(price)               AS order_revenue,
       MIN(delivery_days)       AS delivery_days,
       MIN(review_score)        AS review_score
FROM v_analytical_base
GROUP BY order_id;
-- Order x category grain: used for category KPIs
CREATE OR REPLACE VIEW v_order_category AS
SELECT order_id,
       category_name,
       SUM(price)         AS category_revenue,
       MIN(delivery_days) AS delivery_days,
       MIN(review_score)  AS review_score
FROM v_analytical_base
GROUP BY order_id, category_name;

--Q3 RECONCILIATION - compute total revenue two ways: (a) SUM(price) over order_items directly (b) SUM(price) over your joined base table If they differ, explain exactly which join caused the inflation and fix it. This step is mandatory and is the most important part of the task.
-- (a) direct vs (b) naive joined base vs fixed base
WITH direct_rev AS (
    SELECT SUM(oi.price) AS revenue_direct
    FROM olist_order_items oi
    JOIN olist_orders o ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
),
naive_rev AS (
    SELECT SUM(oi.price) AS revenue_naive
    FROM olist_orders o
    JOIN olist_order_items oi ON oi.order_id = o.order_id
    LEFT JOIN olist_products p ON p.product_id = oi.product_id
    LEFT JOIN name_translation nt ON nt.name = p.product_category_name
    LEFT JOIN olist_sellers s ON s.seller_id = oi.seller_id
    LEFT JOIN olist_order_reviews r ON r.order_id = o.order_id
    WHERE o.order_status = 'delivered'
),
fixed_rev AS (
    SELECT SUM(price) AS revenue_fixed FROM v_analytical_base
)
SELECT d.revenue_direct,
       n.revenue_naive,
       f.revenue_fixed,
       n.revenue_naive - d.revenue_direct AS inflation_amount,
       ROUND((n.revenue_naive - d.revenue_direct) / d.revenue_direct * 100, 2) AS inflation_pct,
       CASE WHEN f.revenue_fixed = d.revenue_direct THEN 'PASS' ELSE 'FAIL' END AS fixed_status
FROM direct_rev d
CROSS JOIN naive_rev n
CROSS JOIN fixed_rev f;

-- Which join causes it: rows and revenue after adding each join
SELECT 'items only' AS step, COUNT(*) AS row_count, SUM(oi.price) AS revenue
FROM olist_orders o
JOIN olist_order_items oi ON oi.order_id = o.order_id
WHERE o.order_status = 'delivered'
UNION ALL
SELECT '+ products', COUNT(*), SUM(oi.price)
FROM olist_orders o
JOIN olist_order_items oi ON oi.order_id = o.order_id
LEFT JOIN olist_products p ON p.product_id = oi.product_id
WHERE o.order_status = 'delivered'
UNION ALL
SELECT '+ translation', COUNT(*), SUM(oi.price)
FROM olist_orders o
JOIN olist_order_items oi ON oi.order_id = o.order_id
LEFT JOIN olist_products p ON p.product_id = oi.product_id
LEFT JOIN name_translation nt ON nt.name = p.product_category_name
WHERE o.order_status = 'delivered'
UNION ALL
SELECT '+ reviews (raw)', COUNT(*), SUM(oi.price)
FROM olist_orders o
JOIN olist_order_items oi ON oi.order_id = o.order_id
LEFT JOIN olist_products p ON p.product_id = oi.product_id
LEFT JOIN name_translation nt ON nt.name = p.product_category_name
LEFT JOIN olist_order_reviews r ON r.order_id = o.order_id
WHERE o.order_status = 'delivered';

-- Q4: overall KPIs
SELECT
    ROUND(SUM(order_revenue), 2)             AS total_revenue,
    ROUND(SUM(order_revenue) / COUNT(*), 2)  AS aov,       
    ROUND(AVG(delivery_days), 2)             AS avg_delivery_days,
    ROUND(AVG(review_score), 2)              AS avg_review_score
FROM v_order_base;

-- Q5: KPIs grouped by English category name, ordered by revenue desc
SELECT
    category_name,
    COUNT(DISTINCT order_id)                                   AS order_count,
    ROUND(SUM(category_revenue), 2)                            AS total_revenue,
    ROUND(SUM(category_revenue) / COUNT(DISTINCT order_id), 2) AS aov,
    ROUND(AVG(delivery_days), 2)                               AS avg_delivery_days,
    ROUND(AVG(review_score), 2)                                AS avg_review_score
FROM v_order_category
GROUP BY category_name
ORDER BY total_revenue DESC;

-- Q6: KPIs grouped by month
SELECT
    TO_CHAR(order_purchase_date, 'YYYY-MM')  AS month_id,
    COUNT(*)                                 AS order_count,
    ROUND(SUM(order_revenue), 2)             AS total_revenue,
    ROUND(SUM(order_revenue) / COUNT(*), 2)  AS aov,
    ROUND(AVG(delivery_days), 2)             AS avg_delivery_days,
    ROUND(AVG(review_score), 2)              AS avg_review_score
FROM v_order_base
GROUP BY TO_CHAR(order_purchase_date, 'YYYY-MM')
ORDER BY month_id;

-- Q7: top 5 and bottom 5 categories by revenue
WITH category_revenue AS (
    SELECT category_name, SUM(price) AS total_revenue
    FROM v_analytical_base
    GROUP BY category_name
),
ranked AS (
    SELECT category_name,
           total_revenue,
           ROW_NUMBER() OVER (ORDER BY total_revenue DESC, category_name) AS rn_top,
           ROW_NUMBER() OVER (ORDER BY total_revenue ASC,  category_name) AS rn_bottom
    FROM category_revenue
)
SELECT category_name,
       ROUND(total_revenue, 2) AS total_revenue,
       CASE WHEN rn_top <= 5 THEN 'TOP_5' ELSE 'BOTTOM_5' END AS bucket
FROM ranked
WHERE rn_top <= 5 OR rn_bottom <= 5
ORDER BY CASE WHEN rn_top <= 5 THEN 0 ELSE 1 END, total_revenue DESC;

-- Q8: top 5 and bottom 5 categories by avg review score, excluding tiny categories
WITH category_review AS (
    SELECT category_name,
           COUNT(DISTINCT order_id) AS order_count,
           AVG(review_score)        AS avg_score      -- unrounded for ranking
    FROM v_order_category
    GROUP BY category_name
    HAVING COUNT(DISTINCT order_id) >= 100
),
ranked AS (
    SELECT category_name,
           order_count,
           avg_score,
           ROW_NUMBER() OVER (ORDER BY avg_score DESC, category_name) AS rn_top,
           ROW_NUMBER() OVER (ORDER BY avg_score ASC,  category_name) AS rn_bottom
    FROM category_review
)
SELECT category_name,
       order_count,
       ROUND(avg_score, 2) AS avg_review_score,
       CASE WHEN rn_top <= 5 THEN 'TOP_5' ELSE 'BOTTOM_5' END AS bucket
FROM ranked
WHERE rn_top <= 5 OR rn_bottom <= 5
ORDER BY CASE WHEN rn_top <= 5 THEN 0 ELSE 1 END, avg_score DESC;

-- Q9: seller-level KPIs with a RANK() over revenue
WITH seller_order AS (
    SELECT seller_id,
           order_id,
           MIN(seller_city)   AS seller_city,
           MIN(seller_state)  AS seller_state,
           SUM(price)         AS revenue,
           MIN(delivery_days) AS delivery_days,
           MIN(review_score)  AS review_score
    FROM v_analytical_base
    GROUP BY seller_id, order_id
)
SELECT
    seller_id,
    MIN(seller_city)                          AS seller_city,
    MIN(seller_state)                         AS seller_state,
    COUNT(*)                                  AS order_count,
    ROUND(SUM(revenue), 2)                    AS total_revenue,
    ROUND(SUM(revenue) / COUNT(*), 2)         AS aov,
    ROUND(AVG(delivery_days), 2)              AS avg_delivery_days,
    ROUND(AVG(review_score), 2)               AS avg_review_score,
    RANK() OVER (ORDER BY SUM(revenue) DESC)  AS revenue_rank
FROM seller_order
GROUP BY seller_id
ORDER BY revenue_rank;

-- Q10: per category, avg delivery days and avg review score side by side for correlation
SELECT
    category_name,
    COUNT(DISTINCT order_id)         AS order_count,
    ROUND(AVG(delivery_days), 2)     AS avg_delivery_days,
    ROUND(AVG(review_score), 2)      AS avg_review_score
FROM v_order_category
GROUP BY category_name
HAVING COUNT(DISTINCT order_id) >= 100
ORDER BY avg_delivery_days;




