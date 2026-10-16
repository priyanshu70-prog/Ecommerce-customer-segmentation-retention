# Data Dictionary

## Source data: `data/raw/online_retail_II.csv.gz`
UCI "Online Retail II" dataset: transactions of a UK-based online gift/homeware retailer (mostly wholesale customers), 1 Dec 2009 - 9 Dec 2011. 1,067,371 rows.

| Column | Type | Meaning |
|---|---|---|
| Invoice | text | Order number. Starts with **C** = cancellation/return |
| StockCode | text | Product code |
| Description | text | Product name |
| Quantity | int | Units on the line (negative for returns) |
| InvoiceDate | datetime | Date and time of the order |
| Price | float | Unit price in GBP |
| Customer ID (-> CustomerID) | float -> int | Customer identifier (missing on ~22.8% of rows) |
| Country | text | Customer country |

## Cleaned tables (`data/processed/`)
| File | Rows | Description |
|---|---|---|
| `transactions_clean.csv` | 776,579 | Clean sales lines + `Revenue = Quantity x Price` (gitignored, regenerate with notebook 01) |
| `returns_clean.csv` | 17,586 | Cancellation lines (negative quantity/revenue) |
| `cleaning_log.csv` | 7 | Rows remaining after each cleaning step |
| `customer_rfm.csv` | 5,832 | Output of `sql/03_rfm_segmentation.sql` (one row per customer) |
| `churn_features.csv` | ~16k | Output of `sql/05_churn_feature_engineering.sql` (customer x cutoff date) |
| `customer_segments.csv` | 5,832 | SQL segment + K-Means cluster per customer |
| `churn_scores.csv` | 3,471 | Churn risk for active customers as of 2011-12-10 |

## `customer_rfm` columns
| Column | Meaning |
|---|---|
| recency_days | Days between last order and snapshot date (2011-12-10) |
| frequency | Number of distinct orders |
| monetary | **Net** spend = sales + returns |
| r_score / f_score / m_score | 1 (worst) to 5 (best), computed with `PERCENT_RANK()` |
| rfm_code | The three scores joined, e.g. `555` |
| segment | Rule-based label (Champions, Loyal Customers, Cant Lose Them, ...) |
| avg_order_value, tenure_days, is_uk | Extra descriptors |

## `churn_features` columns (all computed ONLY from data before `cutoff_date`)
| Column | Meaning |
|---|---|
| recency_days, frequency, monetary, avg_order_value, tenure_days | Classic behaviour measures |
| unique_products, total_items | Basket variety and volume |
| orders_last_90d, orders_prev_90d, spend_last_90d | Recent activity and its trend |
| avg_days_between_orders | Average gap between orders (NULL if only one order) |
| return_orders, return_rate | Return behaviour |
| is_uk | 1 if UK customer |
| **churned** | **Label:** 1 = no purchase in the 90 days after cutoff; NULL if the future is not yet known |
