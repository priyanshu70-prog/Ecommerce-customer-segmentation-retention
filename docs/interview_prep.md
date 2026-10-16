# Interview Prep — E-Commerce Customer Segmentation & Retention

> Rule for myself: **never claim something I cannot explain.** Everything below is backed by a number in the notebooks. If I get asked about something I have not done (e.g. deployment, A/B test results), I say so and explain how I *would* do it.

## 1. The 60-second pitch
"I built an end-to-end customer analytics project on 1.07 million real e-commerce transactions. I cleaned the data in Python, used MySQL for the business analysis and RFM segmentation, then used machine learning for two things: K-Means to group customers, and a churn model to predict who might stop buying in the next 90 days. Finally I combined churn risk with customer value to create a prioritised retention list. What I'm most proud of is that I **tested my own assumptions** — for example I found that four of the five biggest orders had been cancelled, that `NTILE` scored identical customers differently, and that my first retention-tier idea selected only 13 customers — and I fixed each of those."

## 2. Questions I should expect (and my answers)

**Q1. Why did you choose this project?**
Retention is where analysts add business value: most revenue here comes from repeat customers (72% of customers ordered more than once; top 20% of customers = ~77% of net revenue). It also let me combine everything I was learning: Python, SQL and ML.

**Q2. Walk me through your data cleaning.**
Audit first, then rules with a log: remove 34k exact duplicates, 235k rows with no Customer ID (can't analyse customers without an ID), split 18k cancellation invoices into their own table, remove non-product codes (postage, bank charges, tests), and drop non-positive price/quantity. I kept 72.8% of rows. I wrote `assert` checks and kept a cleaning log so each decision is traceable.

**Q3. What was the most interesting thing you found?**
The two largest orders (£168k and £77k) were cancelled by the same customers. With gross sales they would have been my "top customers". I switched to net revenue (sales − returns) everywhere.

**Q4. What is RFM and how did you build it?**
Recency (days since last order), Frequency (number of orders), Monetary (net spend). In SQL I computed them per customer, scored each 1–5, and mapped R and F scores to 9 segments with a `CASE` statement. Champions = 24% of customers but 69% of revenue.

**Q5. You said NTILE had a problem. Explain.**
`NTILE(5)` forces equal-sized buckets, so customers with the *same* frequency (e.g. 1,599 customers with one order) got split across different scores. I tested it with a query counting distinct scores per frequency value, then switched to `PERCENT_RANK()`, which gives ties the same value, and re-ran the test: zero unfair cases.

**Q6. Why K-Means as well as RFM rules? How did you pick k?**
RFM thresholds are chosen by me; K-Means lets the data decide and works as a cross-check. I log-transformed and standardised first (frequency skew was ~12, monetary ~27). For k I used elbow + silhouette + usefulness: silhouette is actually highest at k=2 (0.44), but two groups are too coarse for marketing; k=4 (0.37) is a local peak and gives groups of 1,200–1,950 customers. Stability: ARI ≥ 0.996 across 5 seeds. I'm upfront that 0.37 means moderate structure, not clean islands.

**Q7. Why log-transform?** 
Distance-based methods are dominated by extreme values. Without it K-Means made clusters of 4 and 37 customers — and still showed a silhouette of 0.59, which is why I don't trust a single metric.

**Q8. How did you define churn, and why 90 days?**
No purchase in the 90 days after a cutoff date. SQL showed ~81% of re-orders happen within 90 days. I'm aware that ~19% of gaps are longer (seasonal buyers), so some "churners" return later — that's a limitation.

**Q9. How did you avoid data leakage?**
Features only use rows *before* the cutoff; the label only uses the 90 days *after*. A stored procedure with a cutoff parameter enforces this, and I checked that minimum recency is ≥ 1 day for every cutoff. I also validated **by time**: trained on the June cutoff, tested on the September cutoff, instead of a random split.

**Q10. Which model did you choose and why?**
Logistic Regression: test ROC-AUC 0.758 vs 0.761 for a tuned Random Forest (5-fold CV grid search). I set the rule *before* looking — pick the simpler model unless the forest wins by > 0.01 AUC. It also is easier to explain to business teams.

**Q11. 0.76 AUC — is that good?**
It's decent for a hard, realistic problem using only purchase behaviour. I restricted to active customers on purpose: on all customers AUC was ~0.80 but mostly from the easy task of recognising people who had already left. PR-AUC 0.63 vs baseline 0.38, and the top 30% of customers by risk contain ~50% of churners.

**Q12. What are the weaknesses of your model?**
(1) Probabilities are over-estimated in the test period because churn was 51% in training vs 38% in test (seasonality) — so I use it as a ranking; (2) only two labelled periods; (3) no marketing or category data; (4) 22.8% of rows without Customer ID are invisible.

**Q13. What drives churn in your model?**
Frequency by far (permutation importance AUC drop ~0.13 vs ≤0.05 for the rest). I expected recency to matter most but it didn't, probably because I restricted to the last 180 days and `orders_last_90d` overlaps with it. I also warn that single coefficients (like the positive sign for `monetary`) can flip because features are correlated.

**Q14. How did you turn predictions into business actions?**
My first grid (high value × high risk) found only 13 customers because value and risk are negatively correlated (Spearman −0.79). So I ranked by **expected loss = risk × 90-day value**. Tier 1 = 173 customers (5%) holding 19% of expected loss; Tiers 1+2 = 20% of customers, 45% of expected loss. Valuable healthy customers are a separate "protect, don't over-discount" tier.

**Q15. How would you measure whether the retention campaign worked?**
A/B test: randomly split Tier 1; contact half, keep half as control; compare re-order rate and revenue after 90 days. I did not run this — I have no campaign data — so the scenario table in notebook 04 only shows what *assumed* save rates would be worth.

**Q16. What would you do next with more time?**
Rolling-window churn datasets for more cutoffs, product-category features, probability calibration, a Power BI dashboard on top of the outputs, and the A/B test.

## 3. Things I should be ready to explain from the code
- Why `LEFT JOIN` for returns (keep customers with no returns) and `COALESCE(...,0)`.
- Why `CREATE TABLE ... AS WITH ...` and window functions with `PARTITION BY` (restart per customer for `LAG`).
- Why `StandardScaler`, `SimpleImputer(median)` live **inside** the pipeline (fit on training data only → no leakage).
- Difference between ROC-AUC, PR-AUC, precision and recall — and why accuracy is not the headline.

## 4. How to talk about what was new for me
"K-Means was new — I had studied supervised learning (regression, classification), so for this project I learned unsupervised learning and made sure to *evaluate* it (cluster sizes, silhouette, stability) rather than just run it."
