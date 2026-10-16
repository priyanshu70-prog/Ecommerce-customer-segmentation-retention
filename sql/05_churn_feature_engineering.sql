/* =====================================================================
   05_churn_feature_engineering.sql
   PURPOSE : Build the training data for the churn model USING SQL.
   IDEA    : Pick a CUTOFF date. Pretend today is the cutoff.
             - FEATURES  = what we know about each customer BEFORE the cutoff
             - LABEL     = did the customer buy again in the next 90 days AFTER the cutoff?
                           (no purchase = churned = 1)
   WHY A PROCEDURE? I want to build the dataset for SEVERAL cutoff dates
             (to test the model on a later period). A stored procedure with an
             IN parameter lets me re-use the same logic - I practised this skill earlier.
   LEAKAGE RULE: features only use rows with invoice_date < cutoff.
             The label only uses rows from cutoff up to cutoff + 90 days.
             Mixing these up would make the model "cheat" by seeing the future.
   ===================================================================== */
USE ecom_retention;

/* ---------------------------------------------------------------------
   The table that stores the features: one row per customer per cutoff date.
   --------------------------------------------------------------------- */
DROP TABLE IF EXISTS churn_features;
CREATE TABLE churn_features (
    cutoff_date             DATE          NOT NULL,   -- the pretend "today"
    customer_id             INT           NOT NULL,
    recency_days            INT           NOT NULL,   -- days between last order and cutoff
    frequency               INT           NOT NULL,   -- number of orders before cutoff
    monetary                DECIMAL(12,2) NOT NULL,   -- gross sales before cutoff
    avg_order_value         DECIMAL(12,2) NOT NULL,   -- monetary / frequency
    tenure_days             INT           NOT NULL,   -- days between FIRST order and cutoff
    unique_products         INT           NOT NULL,   -- how many different products they bought
    total_items             INT           NOT NULL,   -- total units bought
    orders_last_90d         INT           NOT NULL,   -- recent activity: orders in the 90 days before cutoff
    orders_prev_90d         INT           NOT NULL,   -- orders in the 90 days BEFORE that (to see a trend)
    spend_last_90d          DECIMAL(12,2) NOT NULL,   -- spend in the last 90 days
    avg_days_between_orders DECIMAL(10,2) NULL,       -- NULL for customers with only 1 order (no gap exists)
    return_orders           INT           NOT NULL,   -- number of cancellation invoices before cutoff
    return_rate             DECIMAL(8,4)  NOT NULL,   -- returned value / sales value
    is_uk                   TINYINT       NOT NULL,   -- 1 if the customer is in the UK
    churned                 TINYINT       NULL,       -- LABEL: 1 = no purchase in next window, NULL = future unknown
    PRIMARY KEY (cutoff_date, customer_id)
);

/* ---------------------------------------------------------------------
   The stored procedure
   p_cutoff       : the pretend "today"
   p_window_days  : how long we wait for a re-purchase (90 days in this project)
   DELIMITER $$ lets me use ';' inside the procedure body without ending the CREATE statement early.
   --------------------------------------------------------------------- */
DROP PROCEDURE IF EXISTS sp_build_churn_features;

DELIMITER $$
CREATE PROCEDURE sp_build_churn_features(IN p_cutoff DATE, IN p_window_days INT)
BEGIN
    DECLARE v_window_end DATE;       -- first day AFTER the label window
    DECLARE v_last_data_day DATE;    -- last day that exists in the data

    SET v_window_end = DATE_ADD(p_cutoff, INTERVAL p_window_days DAY);
    SELECT DATE(MAX(invoice_date)) INTO v_last_data_day FROM transactions;

    -- remove old rows for this cutoff so the procedure can be re-run safely
    DELETE FROM churn_features WHERE cutoff_date = p_cutoff;

    INSERT INTO churn_features
    SELECT p_cutoff                                                   AS cutoff_date,
           h.customer_id,
           DATEDIFF(p_cutoff, h.last_order_day)                       AS recency_days,
           h.frequency,
           h.monetary,
           ROUND(h.monetary / h.frequency, 2)                         AS avg_order_value,
           DATEDIFF(p_cutoff, h.first_order_day)                      AS tenure_days,
           h.unique_products,
           h.total_items,
           h.orders_last_90d,
           h.orders_prev_90d,
           h.spend_last_90d,
           -- average gap = (days between first and last order) / (orders - 1); NULLIF avoids dividing by 0
           ROUND(DATEDIFF(h.last_order_day, h.first_order_day) / NULLIF(h.frequency - 1, 0), 2) AS avg_days_between_orders,
           COALESCE(r.return_orders, 0)                               AS return_orders,
           ROUND(COALESCE(-r.return_value, 0) / h.monetary, 4)        AS return_rate,
           h.is_uk,
           -- LABEL: only defined if the whole window lies inside the data; otherwise NULL (unknown future)
           CASE WHEN v_window_end <= DATE_ADD(v_last_data_day, INTERVAL 1 DAY)
                THEN (f.customer_id IS NULL)                          -- no purchase found in window -> churned = 1
                ELSE NULL END                                         AS churned
    FROM (
        -- HISTORY: everything the customer did BEFORE the cutoff
        SELECT customer_id,
               MAX(DATE(invoice_date))                                AS last_order_day,
               MIN(DATE(invoice_date))                                AS first_order_day,
               COUNT(DISTINCT invoice)                                AS frequency,
               SUM(revenue)                                           AS monetary,
               COUNT(DISTINCT stock_code)                             AS unique_products,
               SUM(quantity)                                          AS total_items,
               COUNT(DISTINCT CASE WHEN invoice_date >= DATE_SUB(p_cutoff, INTERVAL 90 DAY)
                                   THEN invoice END)                  AS orders_last_90d,
               COUNT(DISTINCT CASE WHEN invoice_date <  DATE_SUB(p_cutoff, INTERVAL 90 DAY)
                                    AND invoice_date >= DATE_SUB(p_cutoff, INTERVAL 180 DAY)
                                   THEN invoice END)                  AS orders_prev_90d,
               COALESCE(SUM(CASE WHEN invoice_date >= DATE_SUB(p_cutoff, INTERVAL 90 DAY)
                                 THEN revenue END), 0)                AS spend_last_90d,
               MAX(country = 'United Kingdom')                         AS is_uk
        FROM transactions
        WHERE invoice_date < p_cutoff                                 -- <-- the anti-leakage filter
        GROUP BY customer_id
    ) AS h
    LEFT JOIN (
        -- RETURNS before the cutoff
        SELECT customer_id, COUNT(DISTINCT invoice) AS return_orders, SUM(revenue) AS return_value
        FROM cancellations
        WHERE invoice_date < p_cutoff
        GROUP BY customer_id
    ) AS r ON r.customer_id = h.customer_id
    LEFT JOIN (
        -- FUTURE: customers who DID buy during the label window
        SELECT DISTINCT customer_id
        FROM transactions
        WHERE invoice_date >= p_cutoff AND invoice_date < v_window_end
    ) AS f ON f.customer_id = h.customer_id;
END$$
DELIMITER ;

/* ---------------------------------------------------------------------
   Build the datasets for 3 cutoff dates (90-day window each)
   1) 2011-06-11 -> label window 2011-06-11 .. 2011-09-09   (TRAINING period)
   2) 2011-09-10 -> label window 2011-09-10 .. 2011-12-08   (TEST period, a later time)
   3) 2011-12-10 -> the "today" of the dataset. The label is NULL because the future is unknown;
                    this set is used for REAL predictions in notebooks 03 and 04.
   --------------------------------------------------------------------- */
CALL sp_build_churn_features('2011-06-11', 90);
CALL sp_build_churn_features('2011-09-10', 90);
CALL sp_build_churn_features('2011-12-10', 90);

/* ---------------------------------------------------------------------
   EVALUATION CHECKS
   --------------------------------------------------------------------- */
-- check 1: rows per cutoff, churn rate, and how many labels are missing (the last cutoff should be all NULL)
SELECT cutoff_date,
       COUNT(*)                                   AS customers,
       SUM(churned IS NOT NULL)                   AS with_label,
       ROUND(AVG(churned) * 100, 1)               AS churn_rate_pct   -- AVG ignores NULLs
FROM churn_features
GROUP BY cutoff_date
ORDER BY cutoff_date;

-- check 2: anti-leakage test. recency must be >= 1 for everybody (last order is strictly BEFORE the cutoff).
--          If any customer had recency 0 or less, a purchase on/after the cutoff would have leaked in.
SELECT cutoff_date, MIN(recency_days) AS min_recency_days
FROM churn_features
GROUP BY cutoff_date;

-- check 3: sanity - churn rate by recent activity. Customers who bought in the last 90 days should churn LESS.
SELECT CASE WHEN orders_last_90d = 0 THEN '0 orders in last 90d'
            WHEN orders_last_90d <= 2 THEN '1-2 orders in last 90d'
            ELSE '3+ orders in last 90d' END       AS recent_activity,
       COUNT(*)                                    AS customers,
       ROUND(AVG(churned) * 100, 1)                AS churn_rate_pct
FROM churn_features
WHERE cutoff_date = '2011-09-10'
GROUP BY recent_activity
ORDER BY churn_rate_pct DESC;
