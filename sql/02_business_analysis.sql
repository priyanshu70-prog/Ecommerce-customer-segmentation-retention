/* =====================================================================
   02_business_analysis.sql
   PURPOSE : Answer core business questions with SQL BEFORE building
             segments. Each query has: the business question, the idea,
             the query (commented line by line) and what I learned.
   SKILLS  : GROUP BY, CTEs, window functions (LAG, RANK, DENSE_RANK,
             NTILE, SUM() OVER), UNION ALL, conditional aggregation
   ===================================================================== */
USE ecom_retention;

/* ---------------------------------------------------------------------
   Q1. What are the headline KPIs?
   Idea: gross sales come from `transactions`, returns from `cancellations`
         (stored as negative numbers). Net revenue = gross + returns.
   --------------------------------------------------------------------- */
SELECT
    ROUND(s.gross_sales, 0)                                  AS gross_sales,      -- money from sales lines
    ROUND(-c.returned_value, 0)                              AS returned_value,   -- flip sign: returns are negative
    ROUND(s.gross_sales + c.returned_value, 0)               AS net_revenue,      -- what the business kept
    ROUND(-c.returned_value / s.gross_sales * 100, 1)        AS return_rate_pct,  -- share of sales value returned
    s.orders,                                                                     -- number of distinct invoices
    s.customers,                                                                  -- number of distinct customers
    ROUND(s.gross_sales / s.orders, 2)                       AS avg_order_value   -- AOV = sales / orders
FROM (SELECT SUM(revenue) AS gross_sales,
             COUNT(DISTINCT invoice) AS orders,
             COUNT(DISTINCT customer_id) AS customers
      FROM transactions) AS s                                -- subquery 1: sales side
CROSS JOIN (SELECT SUM(revenue) AS returned_value
            FROM cancellations) AS c;                        -- subquery 2: returns side (1 row each, so CROSS JOIN is safe)
-- LEARNED: returns are ~4% of sales value; AOV is high (~£466) because customers are mostly wholesale buyers.


/* ---------------------------------------------------------------------
   Q2. How does NET revenue change month by month (MoM growth)?
   Idea: stack both tables with UNION ALL, sum per month, then use
         LAG() to bring the previous month's value onto the same row.
   --------------------------------------------------------------------- */
WITH all_lines AS (                                          -- CTE 1: sales and returns in ONE list
    SELECT invoice_date, revenue FROM transactions
    UNION ALL                                                -- UNION ALL keeps every row (no de-duplication, faster)
    SELECT invoice_date, revenue FROM cancellations
),
monthly AS (                                                 -- CTE 2: one row per month
    SELECT DATE_FORMAT(invoice_date, '%Y-%m') AS ym,         -- turn the date into 'YYYY-MM'
           SUM(revenue)                       AS net_revenue
    FROM all_lines
    GROUP BY DATE_FORMAT(invoice_date, '%Y-%m')
)
SELECT ym,
       ROUND(net_revenue, 0)                                 AS net_revenue,
       ROUND(LAG(net_revenue) OVER (ORDER BY ym), 0)         AS prev_month,      -- previous month's revenue
       ROUND((net_revenue - LAG(net_revenue) OVER (ORDER BY ym))
             / LAG(net_revenue) OVER (ORDER BY ym) * 100, 1) AS mom_growth_pct   -- (this - last) / last * 100
FROM monthly
ORDER BY ym;
-- LEARNED: Sept-Nov jump every year (Nov is the peak), then a sharp fall in Dec/Jan. Dec 2011 is incomplete (data ends 9 Dec).


/* ---------------------------------------------------------------------
   Q3. Which countries bring the revenue, and what share is that?
   Idea: SUM(revenue) OVER () is a window function with no partition,
         so it gives the GRAND TOTAL on every row -> easy % share.
   --------------------------------------------------------------------- */
SELECT country,
       COUNT(DISTINCT customer_id)                           AS customers,
       ROUND(SUM(revenue), 0)                                AS revenue,
       ROUND(SUM(revenue) / SUM(SUM(revenue)) OVER () * 100, 1) AS revenue_share_pct  -- SUM of the group sums = grand total
FROM transactions
GROUP BY country
ORDER BY revenue DESC
LIMIT 10;
-- LEARNED: UK = ~84%. EIRE has just 3 customers but ~3.4% of revenue (a few very big accounts).


/* ---------------------------------------------------------------------
   Q4. Top 10 products by NET revenue (sales minus returns)
   Idea: my first version used sales only and the cancelled £168k
         'PAPER CRAFT, LITTLE BIRDIE' order was in the top 3.
         Using both tables fixes that. RANK() gives the position.
   --------------------------------------------------------------------- */
WITH product_lines AS (
    SELECT description, revenue FROM transactions
    UNION ALL
    SELECT description, revenue FROM cancellations           -- negative values reduce the product's total
)
SELECT RANK() OVER (ORDER BY SUM(revenue) DESC) AS revenue_rank,   -- 1 = best product
       description,
       ROUND(SUM(revenue), 0)                   AS net_revenue
FROM product_lines
WHERE description IS NOT NULL                                -- a few lines have no product name
GROUP BY description
ORDER BY revenue_rank
LIMIT 10;
-- LEARNED: REGENCY CAKESTAND 3 TIER and WHITE HANGING HEART T-LIGHT HOLDER lead; no cancelled-order ghosts any more.


/* ---------------------------------------------------------------------
   Q5. How concentrated is revenue? (Pareto check using deciles)
   Idea: NTILE(10) cuts customers into 10 equal groups ordered by net
         revenue. Decile 1 = the top 10% of customers.
   --------------------------------------------------------------------- */
WITH customer_net AS (                                       -- net revenue per customer
    SELECT customer_id, SUM(revenue) AS net_revenue
    FROM (SELECT customer_id, revenue FROM transactions
          UNION ALL
          SELECT customer_id, revenue FROM cancellations) AS x
    GROUP BY customer_id
    HAVING SUM(revenue) > 0                                  -- ignore customers who returned everything
),
deciles AS (
    SELECT customer_id, net_revenue,
           NTILE(10) OVER (ORDER BY net_revenue DESC) AS decile   -- 1 = biggest spenders
    FROM customer_net
)
SELECT decile,
       COUNT(*)                                              AS customers,
       ROUND(SUM(net_revenue), 0)                            AS revenue,
       ROUND(SUM(net_revenue) / SUM(SUM(net_revenue)) OVER () * 100, 1) AS revenue_share_pct,
       ROUND(SUM(SUM(net_revenue)) OVER (ORDER BY decile)    -- running total across deciles
             / SUM(SUM(net_revenue)) OVER () * 100, 1)       AS cumulative_share_pct
FROM deciles
GROUP BY decile
ORDER BY decile;
-- LEARNED: top 20% of customers (deciles 1-2) = ~77% of revenue, matching my Python result (cross-check passed).


/* ---------------------------------------------------------------------
   Q6. Top 10 customers by net revenue (DENSE_RANK)
   Idea: DENSE_RANK gives no gaps after ties. I also show how many
         orders and when they last bought.
   --------------------------------------------------------------------- */
WITH customer_net AS (
    SELECT t.customer_id,
           SUM(t.revenue)                  AS gross_sales,
           COUNT(DISTINCT t.invoice)       AS orders,
           MAX(t.invoice_date)             AS last_order
    FROM transactions t
    GROUP BY t.customer_id
),
customer_returns AS (
    SELECT customer_id, SUM(revenue) AS returned          -- negative number
    FROM cancellations
    GROUP BY customer_id
)
SELECT DENSE_RANK() OVER (ORDER BY n.gross_sales + COALESCE(r.returned, 0) DESC) AS value_rank,
       n.customer_id,
       n.orders,
       ROUND(n.gross_sales + COALESCE(r.returned, 0), 0)  AS net_revenue,   -- COALESCE: no returns -> treat as 0
       DATE(n.last_order)                                 AS last_order
FROM customer_net n
LEFT JOIN customer_returns r ON r.customer_id = n.customer_id   -- LEFT JOIN keeps customers with no returns
ORDER BY value_rank
LIMIT 10;
-- LEARNED: after netting returns, customers 16446 and 12346 (the cancelled giant orders) no longer appear at the top.


/* ---------------------------------------------------------------------
   Q7. New vs returning customers per month
   Idea: a customer is "new" in the month of their FIRST order, and
         "returning" in every later month they order.
   --------------------------------------------------------------------- */
WITH first_order AS (                                        -- first month each customer ever ordered
    SELECT customer_id,
           DATE_FORMAT(MIN(invoice_date), '%Y-%m') AS first_month
    FROM transactions
    GROUP BY customer_id
),
monthly_activity AS (                                        -- which customers were active in which months
    SELECT DISTINCT customer_id,
           DATE_FORMAT(invoice_date, '%Y-%m') AS ym
    FROM transactions
)
SELECT a.ym,
       SUM(a.ym = f.first_month)   AS new_customers,         -- comparison returns 1/0, so SUM counts the TRUEs
       SUM(a.ym > f.first_month)   AS returning_customers,   -- text 'YYYY-MM' sorts correctly
       COUNT(*)                    AS active_customers
FROM monthly_activity a
JOIN first_order f ON f.customer_id = a.customer_id
GROUP BY a.ym
ORDER BY a.ym;
-- LEARNED: Dec 2009 shows every customer as "new" only because the data starts there (a data-window limitation).
--          From Feb 2010 onwards returning customers outnumber new customers in almost every month,
--          so the business depends on repeat buyers -> retention matters more than acquisition here.


/* ---------------------------------------------------------------------
   Q8. How long do customers wait between orders?
   Idea: LAG() on each customer's order dates gives the previous order,
         DATEDIFF gives the gap in days. This helps me choose a sensible
         "churn" definition later (how long is "too long" to be silent?).
   --------------------------------------------------------------------- */
WITH order_dates AS (                                        -- one row per customer per order day
    SELECT DISTINCT customer_id, DATE(invoice_date) AS order_day
    FROM transactions
),
gaps AS (
    SELECT customer_id,
           DATEDIFF(order_day,
                    LAG(order_day) OVER (PARTITION BY customer_id ORDER BY order_day)) AS gap_days
           -- PARTITION BY customer_id: restart the LAG for every customer, so gaps never cross customers
    FROM order_dates
)
SELECT CASE WHEN gap_days <= 30  THEN '1) 0-30 days'
            WHEN gap_days <= 60  THEN '2) 31-60 days'
            WHEN gap_days <= 90  THEN '3) 61-90 days'
            WHEN gap_days <= 180 THEN '4) 91-180 days'
            ELSE                      '5) 180+ days' END    AS gap_bucket,
       COUNT(*)                                              AS gaps,
       ROUND(COUNT(*) / SUM(COUNT(*)) OVER () * 100, 1)      AS pct_of_gaps,
       ROUND(SUM(COUNT(*)) OVER (ORDER BY MIN(gap_days)) / SUM(COUNT(*)) OVER () * 100, 1) AS cumulative_pct
FROM gaps
WHERE gap_days IS NOT NULL                                   -- first order of each customer has no previous order -> NULL, skip
GROUP BY gap_bucket
ORDER BY gap_bucket;
-- LEARNED: ~81% of re-orders happen within 90 days (49% within 30 days). So "no purchase for 90 days"
--          is a reasonable first churn definition: most active customers come back before then.
--          Limitation: ~19% of gaps are longer (seasonal buyers), so some 'churned' customers will return later.


/* ---------------------------------------------------------------------
   Q9. Monthly return rate (is quality / satisfaction a problem?)
   Idea: conditional aggregation - compare returned value with sales
         value in the same month.
   --------------------------------------------------------------------- */
SELECT s.ym,
       ROUND(s.sales, 0)                      AS sales,
       ROUND(-COALESCE(c.returned, 0), 0)     AS returned,
       ROUND(-COALESCE(c.returned, 0) / s.sales * 100, 1) AS return_rate_pct
FROM (SELECT DATE_FORMAT(invoice_date, '%Y-%m') AS ym, SUM(revenue) AS sales
      FROM transactions GROUP BY ym) AS s
LEFT JOIN (SELECT DATE_FORMAT(invoice_date, '%Y-%m') AS ym, SUM(revenue) AS returned
           FROM cancellations GROUP BY ym) AS c ON c.ym = s.ym
ORDER BY s.ym;
-- LEARNED: in most months the return rate is only 1-4%. The big spikes are Jan 2011 (16%) and Dec 2011 (34%) -
--          these are the two giant cancelled orders (£77k and £168k) I found in notebook 01, not a quality crisis.
--          Note: a cancellation is dated when it is cancelled, so it can fall in a different month than the original sale.
