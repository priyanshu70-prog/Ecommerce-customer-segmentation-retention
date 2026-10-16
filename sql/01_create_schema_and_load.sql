/* =====================================================================
   01_create_schema_and_load.sql
   PROJECT : E-Commerce Customer Segmentation & Retention
   PURPOSE : Create the database + tables and load the CLEAN data that
             notebook 01 saved in data/processed/.
   TESTED  : MySQL-style SQL (run on MariaDB 10.11; syntax is the same as MySQL 8)
   RUN     : from the sql/ folder, or edit the file paths below.
   ===================================================================== */

-- I always DROP IF EXISTS first so that I can re-run this file as many times as I want
DROP DATABASE IF EXISTS ecom_retention;

-- one database for the whole project
CREATE DATABASE ecom_retention;
USE ecom_retention;

/* ---------------------------------------------------------------------
   TABLE 1: transactions  (clean SALES lines - one row per product line)
   Why these data types?
     VARCHAR  -> text IDs (invoice and stock codes contain letters)
     DECIMAL  -> money. I avoid FLOAT for money because of rounding errors
     DATETIME -> keeps date AND time of the order
   Why indexes? Most queries filter/group by customer_id or invoice_date,
   so indexes on these make the queries much faster on 776k rows.
   --------------------------------------------------------------------- */
CREATE TABLE transactions (
    invoice       VARCHAR(20)   NOT NULL,   -- order number
    stock_code    VARCHAR(20)   NOT NULL,   -- product code
    description   VARCHAR(255),             -- product name (a few are missing, so NULL is allowed)
    quantity      INT           NOT NULL,   -- units bought (always > 0 in this table)
    invoice_date  DATETIME      NOT NULL,   -- when the order happened
    price         DECIMAL(10,2) NOT NULL,   -- unit price in GBP
    customer_id   INT           NOT NULL,   -- customer (no missing IDs after cleaning)
    country       VARCHAR(60)   NOT NULL,   -- customer's country
    revenue       DECIMAL(12,2) NOT NULL,   -- quantity * price (calculated in Python)
    INDEX idx_tx_customer (customer_id),    -- speeds up GROUP BY / JOIN on customer
    INDEX idx_tx_date     (invoice_date),   -- speeds up date filters
    INDEX idx_tx_invoice  (invoice)         -- speeds up COUNT(DISTINCT invoice)
);

/* ---------------------------------------------------------------------
   TABLE 2: cancellations  (returns - invoices starting with 'C')
   Same structure, but quantity and revenue are NEGATIVE here.
   I named it "cancellations" instead of "returns" because RETURNS is a
   keyword in MySQL (used in stored functions) and I do not want name clashes.
   --------------------------------------------------------------------- */
CREATE TABLE cancellations LIKE transactions;   -- copy the structure (columns + indexes)

/* ---------------------------------------------------------------------
   LOAD THE CSV FILES
   LOAD DATA LOCAL INFILE is much faster than 776k INSERT statements.
   - FIELDS TERMINATED BY ','            : columns are separated by commas
   - OPTIONALLY ENCLOSED BY '"'          : descriptions that contain commas are wrapped in quotes
   - IGNORE 1 LINES                      : skip the header row
   - (@desc) + SET description = NULLIF  : turn empty text '' into a real NULL
   NOTE for MySQL Workbench: enable "OPT_LOCAL_INFILE=1" in
   Connection > Advanced > Others, and run:  SET GLOBAL local_infile = 1;
   (Alternative: right-click the table > Table Data Import Wizard - slower but no settings needed.)
   --------------------------------------------------------------------- */
LOAD DATA LOCAL INFILE '../data/processed/transactions_clean.csv'
INTO TABLE transactions
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(invoice, stock_code, @desc, quantity, invoice_date, price, customer_id, country, revenue)
SET description = NULLIF(@desc, '');

LOAD DATA LOCAL INFILE '../data/processed/returns_clean.csv'
INTO TABLE cancellations
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(invoice, stock_code, @desc, quantity, invoice_date, price, customer_id, country, revenue)
SET description = NULLIF(@desc, '');

/* ---------------------------------------------------------------------
   SANITY CHECKS - did the load work?  Always verify after loading data.
   Expected (from notebook 01): 776,579 sales rows | 17,586 cancellation rows
   --------------------------------------------------------------------- */

-- check 1: row counts must match the Python numbers
SELECT 'transactions' AS table_name, COUNT(*) AS row_count FROM transactions
UNION ALL
SELECT 'cancellations', COUNT(*) FROM cancellations;

-- check 2: date range, number of customers and total revenue must match notebook 01
SELECT MIN(invoice_date)           AS first_order,
       MAX(invoice_date)           AS last_order,
       COUNT(DISTINCT customer_id) AS customers,
       ROUND(SUM(revenue), 2)      AS gross_sales        -- expect 17,068,582.72
FROM transactions;

-- check 3: no NULL customers or non-positive revenue (should return 0)
SELECT SUM(customer_id IS NULL) AS null_customers,
       SUM(revenue <= 0)        AS bad_revenue_rows
FROM transactions;
