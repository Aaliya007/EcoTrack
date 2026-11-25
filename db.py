import os

import mysql.connector
from dotenv import load_dotenv
from mysql.connector import Error

load_dotenv()


def get_db_connection():
    """Create and return a MySQL connection using values from .env."""
    try:
        connection = mysql.connector.connect(
            host=os.getenv("DB_HOST"),
            user=os.getenv("DB_USER"),
            password=os.getenv("DB_PASSWORD"),
            database=os.getenv("DB_NAME"),
        )
        connection.autocommit = True
        return connection
    except Error as err:
        print("Could not connect to MySQL:", err)
        return None
