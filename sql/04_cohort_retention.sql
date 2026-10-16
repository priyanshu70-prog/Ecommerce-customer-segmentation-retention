/* =====================================================================
   04_cohort_retention.sql
   PURPOSE : Cohort retention analysis - of the customers who first
             bought in month X, what % came back 1, 2, 3 ... 12 months later?
   WHY     : It shows the real "shape" of customer loyalty over time and
             tells me when customers are most likely to drift away.
   SKILLS  : CTEs, TIMESTAMPDIFF, conditional aggregation (pivot with CASE)
   ===================================================================== */
USE ecom_retention;

/* ---------------------------------------------------------------------
   STEP 1. For every customer: which month did they FIRST buy? (their cohort)
   --------------------------------------------------------------------- */
-- (written as CTEs inside the final query below so I do not leave helper tables behind)

/* ---------------------------------------------------------------------
   STEP 2. Retention table  (rows = cohort month, columns = months since first purchase)
   month_0 is always 100% (everyone bought in their first month by definition).
   I only keep cohorts from 2010-01 to 2010-11 so every cohort can be observed for a full 12 months
   (the data runs to 9 Dec 2011). I first included 2010-12 too, but its month 12 is Dec 2011, which is
   incomplete, so that cohort looked unfairly bad - I removed it.
   NOTE: "retention" here means ACTIVE IN THAT MONTH (bought at least once), not "ever came back".
   I leave out the 2009-12 cohort: it contains customers who were already buying before
   the data starts, so it is not a true "first purchase" cohort.
   --------------------------------------------------------------------- */
WITH first_purchase AS (
    SELECT customer_id,
           DATE_FORMAT(MIN(invoice_date), '%Y-%m-01') AS cohort_month   -- first day of the first-purchase month
    FROM transactions
    GROUP BY customer_id
),
activity AS (                                                -- one row per customer per active month
    SELECT DISTINCT customer_id,
           DATE_FORMAT(invoice_date, '%Y-%m-01') AS active_month
    FROM transactions
),
cohort_activity AS (                                         -- combine: how many months after their cohort month was each activity?
    SELECT f.cohort_month,
           f.customer_id,
           TIMESTAMPDIFF(MONTH, f.cohort_month, a.active_month) AS months_since_first   -- 0, 1, 2, ...
    FROM first_purchase f
    JOIN activity a ON a.customer_id = f.customer_id
)
SELECT DATE_FORMAT(cohort_month, '%Y-%m')                       AS cohort,
       COUNT(DISTINCT CASE WHEN months_since_first = 0 THEN customer_id END)  AS cohort_size,
       -- each column below = % of the cohort that was active exactly N months later
       ROUND(100 * COUNT(DISTINCT CASE WHEN months_since_first = 1  THEN customer_id END) / COUNT(DISTINCT CASE WHEN months_since_first = 0 THEN customer_id END), 1) AS m1,
       ROUND(100 * COUNT(DISTINCT CASE WHEN months_since_first = 2  THEN customer_id END) / COUNT(DISTINCT CASE WHEN months_since_first = 0 THEN customer_id END), 1) AS m2,
       ROUND(100 * COUNT(DISTINCT CASE WHEN months_since_first = 3  THEN customer_id END) / COUNT(DISTINCT CASE WHEN months_since_first = 0 THEN customer_id END), 1) AS m3,
       ROUND(100 * COUNT(DISTINCT CASE WHEN months_since_first = 4  THEN customer_id END) / COUNT(DISTINCT CASE WHEN months_since_first = 0 THEN customer_id END), 1) AS m4,
       ROUND(100 * COUNT(DISTINCT CASE WHEN months_since_first = 5  THEN customer_id END) / COUNT(DISTINCT CASE WHEN months_since_first = 0 THEN customer_id END), 1) AS m5,
       ROUND(100 * COUNT(DISTINCT CASE WHEN months_since_first = 6  THEN customer_id END) / COUNT(DISTINCT CASE WHEN months_since_first = 0 THEN customer_id END), 1) AS m6,
       ROUND(100 * COUNT(DISTINCT CASE WHEN months_since_first = 9  THEN customer_id END) / COUNT(DISTINCT CASE WHEN months_since_first = 0 THEN customer_id END), 1) AS m9,
       ROUND(100 * COUNT(DISTINCT CASE WHEN months_since_first = 12 THEN customer_id END) / COUNT(DISTINCT CASE WHEN months_since_first = 0 THEN customer_id END), 1) AS m12
FROM cohort_activity
WHERE cohort_month >= '2010-01-01' AND cohort_month <= '2010-11-01'   -- true cohorts with a full 12 months of follow-up
GROUP BY cohort_month
ORDER BY cohort_month;
-- LEARNED: cohorts differ a lot because of seasonality. Customers acquired in Sept-Nov (autumn peak) are
--          only ~8-13% active in the quiet months after, but come back to ~19-25% at month 12 (next autumn).
--          Customers acquired in Jan-Feb are more evenly active (20-30% in many months).

/* ---------------------------------------------------------------------
   STEP 3. Average retention curve across the 2010 cohorts (one line summary)
   Idea: weight by cohort size - add up all customers active at month N and divide by all starting customers.
   --------------------------------------------------------------------- */
WITH first_purchase AS (
    SELECT customer_id, DATE_FORMAT(MIN(invoice_date), '%Y-%m-01') AS cohort_month
    FROM transactions GROUP BY customer_id
),
activity AS (
    SELECT DISTINCT customer_id, DATE_FORMAT(invoice_date, '%Y-%m-01') AS active_month
    FROM transactions
),
cohort_activity AS (
    SELECT f.cohort_month, f.customer_id,
           TIMESTAMPDIFF(MONTH, f.cohort_month, a.active_month) AS months_since_first
    FROM first_purchase f JOIN activity a ON a.customer_id = f.customer_id
    WHERE f.cohort_month BETWEEN '2010-01-01' AND '2010-11-01'
)
SELECT months_since_first                                         AS month_number,
       COUNT(DISTINCT customer_id)                                AS active_customers,
       ROUND(100 * COUNT(DISTINCT customer_id) /
             (SELECT COUNT(DISTINCT customer_id) FROM cohort_activity WHERE months_since_first = 0), 1) AS retention_pct
FROM cohort_activity
WHERE months_since_first BETWEEN 0 AND 12
GROUP BY months_since_first
ORDER BY months_since_first;
-- LEARNED: the big drop is right after the first purchase: only ~1 in 5 new customers buys again in any
--          following month. After that the curve is fairly flat for ~7 months, falls to its lowest around
--          months 10-11, then rebounds at month 12 (the next autumn peak). So (1) most new customers are
--          'one-and-done' unless nudged early, and (2) lapsed customers can come back in peak season -
--          which is also a warning that a quiet spell does not always mean churn.
