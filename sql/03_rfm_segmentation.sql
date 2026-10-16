/* =====================================================================
   03_rfm_segmentation.sql
   PURPOSE : Build RFM (Recency, Frequency, Monetary) scores for every
             customer and turn them into business-friendly segments.
   IDEA    : R = how recently did the customer buy?   (lower days = better)
             F = how often did they buy?              (more orders = better)
             M = how much money did they spend (net)? (more = better)
   OUTPUT  : table `customer_rfm` (one row per customer) -> used by Python notebook 02
   SKILLS  : CTEs, window functions (NTILE, PERCENT_RANK), CASE, LEFT JOIN
   ===================================================================== */
USE ecom_retention;

/* The "snapshot date" = the day I pretend "today" is.
   The data ends on 2011-12-09, so I use the next day. Recency is measured from this date.
   Using a fixed date (not NOW()) makes the results reproducible. */
SET @snapshot_date = '2011-12-10';

/* ---------------------------------------------------------------------
   STEP 1. One row per customer with the raw R, F and M numbers
   Monetary is NET (sales + returns) because notebook 01 showed that
   some giant orders were cancelled.
   --------------------------------------------------------------------- */
DROP TABLE IF EXISTS customer_base;                          -- re-runnable

CREATE TABLE customer_base AS
WITH returns_per_customer AS (                               -- total returned value per customer (negative number)
    SELECT customer_id, SUM(revenue) AS returned_value
    FROM cancellations
    GROUP BY customer_id
)
SELECT t.customer_id,
       DATEDIFF(@snapshot_date, MAX(DATE(t.invoice_date)))   AS recency_days,     -- days since last order
       COUNT(DISTINCT t.invoice)                             AS frequency,        -- number of orders
       ROUND(SUM(t.revenue) + COALESCE(r.returned_value, 0), 2) AS monetary,      -- NET spend (COALESCE: no returns -> 0)
       ROUND(SUM(t.revenue), 2)                              AS gross_sales,
       ROUND(COALESCE(r.returned_value, 0), 2)               AS returned_value,
       MIN(DATE(t.invoice_date))                             AS first_order_date, -- needed for tenure
       MAX(DATE(t.invoice_date))                             AS last_order_date,
       MAX(t.country = 'United Kingdom')                     AS is_uk              -- 1 if the customer is UK based
FROM transactions t
LEFT JOIN returns_per_customer r ON r.customer_id = t.customer_id   -- LEFT JOIN: keep customers who never returned anything
GROUP BY t.customer_id, r.returned_value
HAVING monetary > 0;                                         -- drop customers who returned everything they bought

-- quick check: how many customers made it into the base table?
SELECT COUNT(*) AS customers_in_base,
       (SELECT COUNT(DISTINCT customer_id) FROM transactions) AS customers_with_sales
FROM customer_base;
-- LEARNED: 20 customers (5,852 -> 5,832) are excluded because their net revenue is <= 0 - they returned
--          everything they bought, so they cannot be "valuable" customers.


/* ---------------------------------------------------------------------
   STEP 2. EVALUATION: is NTILE() a fair way to score?  (my first attempt)
   NTILE(5) splits rows into 5 equal-sized groups. But what if many
   customers have the SAME frequency (e.g. everyone with 1 order)?
   NTILE still has to cut the list into equal groups, so it may put
   customers with IDENTICAL frequency into DIFFERENT scores.
   Let me test that.
   --------------------------------------------------------------------- */
WITH ntile_test AS (
    SELECT customer_id, frequency,
           NTILE(5) OVER (ORDER BY frequency) AS f_score_ntile      -- my first idea
    FROM customer_base
)
SELECT frequency,
       COUNT(*)                         AS customers,
       COUNT(DISTINCT f_score_ntile)    AS different_scores_given   -- should be 1 if scoring is fair!
FROM ntile_test
GROUP BY frequency
HAVING COUNT(DISTINCT f_score_ntile) > 1                            -- show only the unfair cases
ORDER BY frequency
LIMIT 5;
-- LEARNED (a real problem): e.g. 1,599 customers with exactly 1 order were split across 2 different F scores,
--          just because NTILE has to make equal-sized buckets. Two customers with identical behaviour should
--          never get different scores - that would send them different marketing messages for no reason.


/* ---------------------------------------------------------------------
   STEP 3. OPTIMIZATION: score with PERCENT_RANK() instead
   PERCENT_RANK gives the SAME value to ties (rank-based), from 0 to 1.
   score = FLOOR(percent_rank * 5) + 1  -> 1..5. LEAST(5, ...) protects the single case percent_rank = 1.
   For Recency a SMALLER number of days is better, so I order DESC
   (the most recent customers get the highest percent_rank -> score 5).
   --------------------------------------------------------------------- */
DROP TABLE IF EXISTS customer_rfm;

CREATE TABLE customer_rfm AS
WITH ranked AS (
    SELECT b.*,
           PERCENT_RANK() OVER (ORDER BY recency_days DESC) AS r_pr,   -- big recency_days = bad = low rank
           PERCENT_RANK() OVER (ORDER BY frequency)         AS f_pr,   -- more orders = higher rank
           PERCENT_RANK() OVER (ORDER BY monetary)          AS m_pr    -- more money = higher rank
    FROM customer_base b
),
scored AS (
    SELECT customer_id, recency_days, frequency, monetary, gross_sales, returned_value,
           first_order_date, last_order_date, is_uk,
           LEAST(5, FLOOR(r_pr * 5) + 1) AS r_score,            -- 1 (worst) .. 5 (best)
           LEAST(5, FLOOR(f_pr * 5) + 1) AS f_score,
           LEAST(5, FLOOR(m_pr * 5) + 1) AS m_score
    FROM ranked
)
SELECT s.*,
       ROUND(monetary / frequency, 2)                           AS avg_order_value,   -- average spend per order
       DATEDIFF(@snapshot_date, first_order_date)               AS tenure_days,       -- how long they have been a customer
       CONCAT(r_score, f_score, m_score)                        AS rfm_code,          -- e.g. '555' = best on all three
       /* ---- segment rules: read top to bottom, the FIRST matching rule wins ----
          Only R and F are used for the label (classic RFM grid). M is kept as a separate score,
          and Monetary is used in the retention plan (value-weighted) later. */
       CASE
           WHEN r_score >= 4 AND f_score >= 4 THEN 'Champions'            -- bought recently AND often
           WHEN r_score <= 2 AND f_score >= 4 THEN 'Cant Lose Them'       -- used to buy a lot, gone quiet
           WHEN f_score >= 4                  THEN 'Loyal Customers'      -- (r_score = 3) frequent, fairly recent
           WHEN r_score >= 4 AND f_score = 3  THEN 'Potential Loyalists'  -- recent, growing frequency
           WHEN r_score >= 4                  THEN 'New / Recent Customers' -- recent but few orders (f_score <= 2)
           WHEN r_score = 3 AND f_score = 3   THEN 'Needs Attention'      -- middle of everything
           WHEN r_score = 3                   THEN 'About To Sleep'       -- (f_score <= 2) slipping away
           WHEN f_score >= 3                  THEN 'At Risk'              -- (r_score <= 2) was decent, now quiet
           ELSE                                    'Hibernating'          -- low recency AND low frequency
       END AS segment
FROM scored s;

-- index so the Python notebook can read it quickly
ALTER TABLE customer_rfm ADD PRIMARY KEY (customer_id);


/* ---------------------------------------------------------------------
   STEP 4. EVALUATION of the new scoring
   4a) Fairness test again: same frequency must now mean ONE score.
   --------------------------------------------------------------------- */
SELECT frequency,
       COUNT(*)                  AS customers,
       COUNT(DISTINCT f_score)   AS different_scores_given
FROM customer_rfm
GROUP BY frequency
HAVING COUNT(DISTINCT f_score) > 1;
-- RESULT: 0 rows -> every group of customers with the same frequency now gets exactly one score. Fixed.

/* 4b) Coverage test: every customer must have exactly one segment (no NULLs, no gaps). */
SELECT COUNT(*)                AS customers,
       SUM(segment IS NULL)    AS customers_without_segment      -- must be 0
FROM customer_rfm;

/* 4c) How are the scores distributed?  (not perfectly 20% each because of ties - that is expected and fair) */
SELECT 'R' AS score_type, r_score AS score, COUNT(*) AS customers FROM customer_rfm GROUP BY r_score
UNION ALL
SELECT 'F', f_score, COUNT(*) FROM customer_rfm GROUP BY f_score
UNION ALL
SELECT 'M', m_score, COUNT(*) FROM customer_rfm GROUP BY m_score
ORDER BY score_type, score;


/* ---------------------------------------------------------------------
   STEP 5. SEGMENT PROFILE: size, behaviour and money per segment
   This table is the main business output of the SQL part.
   --------------------------------------------------------------------- */
SELECT segment,
       COUNT(*)                                                          AS customers,
       ROUND(COUNT(*) / SUM(COUNT(*)) OVER () * 100, 1)                  AS pct_customers,
       ROUND(AVG(recency_days), 0)                                       AS avg_recency_days,
       ROUND(AVG(frequency), 1)                                          AS avg_orders,
       ROUND(AVG(monetary), 0)                                           AS avg_net_spend,
       ROUND(SUM(monetary), 0)                                           AS total_net_revenue,
       ROUND(SUM(monetary) / SUM(SUM(monetary)) OVER () * 100, 1)        AS pct_revenue
FROM customer_rfm
GROUP BY segment
ORDER BY total_net_revenue DESC;

/* ---------------------------------------------------------------------
   STEP 6. Sanity check by eye: the 2 highest-value customers in every segment
   ROW_NUMBER() OVER (PARTITION BY segment ...) numbers customers inside each segment,
   so rn <= 2 keeps the top 2 per segment.
   --------------------------------------------------------------------- */
SELECT segment, customer_id, recency_days, frequency, monetary, rfm_code
FROM (SELECT customer_id, segment, recency_days, frequency, monetary, rfm_code,
             ROW_NUMBER() OVER (PARTITION BY segment ORDER BY monetary DESC) AS rn
      FROM customer_rfm) AS ranked_customers
WHERE rn <= 2
ORDER BY segment, rn;
-- LEARNED: labels look sensible, e.g. customers with recency of 1-3 days and 100+ orders are Champions.
--          Customer 12346 (whose £77k order was cancelled) now sits in 'At Risk' with only £169 net spend -
--          the net-of-returns fix from notebook 01 worked.
