"""
churn_utils.py - feature preparation shared by notebooks 03 and 04.

I moved this into a file because the SAME preparation must be applied to the training data,
the test data and the final customers I score. Copy-pasting it three times is how mistakes happen.
"""
import numpy as np
import pandas as pd

# the columns the model is allowed to use (all computed ONLY from data before the cutoff date)
FEATURES = [
    "recency_days", "frequency", "monetary", "avg_order_value", "tenure_days",
    "unique_products", "total_items", "orders_last_90d", "orders_prev_90d",
    "spend_last_90d", "avg_days_between_orders", "return_orders", "return_rate", "is_uk",
]

# columns with a few huge values (right-skewed, see notebook 01/02) -> I compress them with log(1 + x)
LOG_COLUMNS = ["frequency", "monetary", "avg_order_value", "unique_products", "total_items", "spend_last_90d"]


def prepare_features(df):
    """Return a model-ready feature table (log-transformed skewed columns). Missing values are handled later by the pipeline."""
    X = df[FEATURES].copy().astype(float)          # copy so the original DataFrame is not changed
    for col in LOG_COLUMNS:
        X[col] = np.log1p(X[col])                  # log1p(x) = log(1 + x), safe for zeros
    return X
