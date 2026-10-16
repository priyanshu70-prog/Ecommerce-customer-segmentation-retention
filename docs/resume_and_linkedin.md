# Resume & LinkedIn Text

## Resume — project entry (pick 3-4 bullets, keep numbers you can explain)

**E-Commerce Customer Segmentation & Retention | Python, SQL (MySQL), scikit-learn**  [GitHub link]
- Cleaned and audited **1.07M transactions** (pandas, MySQL); discovered that **4 of the 5 largest orders were later cancelled** and rebuilt revenue and customer-value metrics on a **net-of-returns** basis.
- Built **RFM segmentation in SQL** (CTEs, window functions); replaced `NTILE` with `PERCENT_RANK` after a fairness test showed identical customers received different scores. Top segment = **24% of customers / 69% of revenue**.
- Applied **K-Means (k=4)** on log-scaled features, validated with silhouette and seed stability (ARI ≥ 0.996); identified a VIP cluster of **20% of customers generating ~74% of net revenue**.
- Developed a **churn prediction model** (Logistic Regression, **ROC-AUC 0.76 vs 0.50 baseline**) with leakage-free features from a **SQL stored procedure** and time-based validation; top 30% of customers by risk contain **~50% of churners**.
- Prioritised retention by **expected revenue loss**: top 20% of active customers hold **~45% of expected loss**; produced a ranked action list and a 737-customer win-back list.

*Short version (one line):* Customer segmentation & churn project on 1M+ e-commerce transactions: SQL RFM, K-Means (k=4), churn model (AUC 0.76), and a value-weighted retention plan.

## LinkedIn post (draft)
**I just finished my biggest data project so far: E-Commerce Customer Segmentation & Retention 📊**

I took 1.07 million real transactions from a UK online retailer and tried to answer one question: *who should the retention team call first?*

What I did:
🔹 Cleaned the data in Python (and kept a log of every row removed)
🔹 Used MySQL for business analysis, RFM scoring and cohort retention
🔹 Grouped customers with K-Means and predicted churn with scikit-learn
🔹 Ranked customers by expected revenue loss

The parts that taught me the most were my mistakes:
❌ My biggest "top customers" had actually cancelled their orders
❌ SQL's NTILE gave different scores to identical customers
❌ My first retention grid selected only 13 customers (value and risk were negatively correlated)

Fixing those taught me more than any tutorial. 

Full code, SQL and notebooks: [GitHub link]
Feedback is very welcome! 🙏

#DataAnalytics #SQL #Python #MachineLearning #CustomerRetention #Portfolio

## GitHub repo description (one line)
End-to-end customer segmentation & churn project: Python, MySQL, K-Means, churn model, retention action list.

## Suggested GitHub topics
`data-analysis` `sql` `python` `customer-segmentation` `rfm-analysis` `churn-prediction` `kmeans` `scikit-learn` `mysql` `portfolio-project`
