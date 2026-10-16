"""
db_utils.py  -  small helper so every notebook connects to MySQL the same way.

Why a separate file? I was copy-pasting the connection code into every notebook.
Putting it in one place means I only fix it once if something changes.

Passwords are NOT written in the code. They are read from environment variables, so
nothing secret ends up on GitHub.  Set them in your terminal before starting Jupyter:
    Windows (PowerShell):  $env:DB_USER="root" ; $env:DB_PASSWORD="your_password"
    Mac / Linux         :  export DB_USER=root DB_PASSWORD=your_password
"""
import os                                   # to read environment variables
import pandas as pd                         # to return query results as DataFrames
from sqlalchemy import create_engine, text  # SQLAlchemy = the bridge between pandas and MySQL
from sqlalchemy.engine import URL           # builds the connection string safely (handles special characters in passwords)


def get_engine():
    """Create a connection 'engine' to the ecom_retention MySQL database."""
    url = URL.create(
        drivername="mysql+pymysql",                       # MySQL through the PyMySQL driver
        username=os.getenv("DB_USER", "root"),            # default user = root
        password=os.getenv("DB_PASSWORD", ""),            # default = empty password
        host=os.getenv("DB_HOST", "127.0.0.1"),           # default = my own computer
        database=os.getenv("DB_NAME", "ecom_retention"),  # the database created in sql/01
    )
    return create_engine(url)


def read_sql_or_csv(query, csv_fallback):
    """
    Run a SQL query and return a DataFrame.
    If MySQL is not reachable (for example someone just wants to run the notebooks), fall back
    to the CSV that was exported from the same query, so the project still runs end to end.
    """
    try:
        with get_engine().connect() as conn:              # open a connection (closed automatically afterwards)
            df = pd.read_sql(text(query), conn)           # run the query -> DataFrame
        print("Loaded from MySQL")
    except Exception as err:                              # any connection / permission problem lands here
        print(f"MySQL not available ({type(err).__name__}) -> reading the exported CSV instead: {csv_fallback}")
        df = pd.read_csv(csv_fallback)
    return df


def call_procedure(sql_text):
    """Run a statement that changes data (e.g. CALL my_procedure(...)). Returns nothing."""
    with get_engine().begin() as conn:                    # .begin() commits the change automatically
        conn.execute(text(sql_text))
