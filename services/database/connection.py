"""
Database Connection Module

Provides:

- SQLAlchemy Engine
- SessionLocal
- Declarative Base
- Database session generator
- Database connection testing

Compatible with:

- PostgreSQL
- FastAPI
- ETL Jobs
- Lambda
- Standalone Python Scripts
"""

import logging

from sqlalchemy import create_engine
from sqlalchemy import text
from sqlalchemy.orm import declarative_base
from sqlalchemy.orm import sessionmaker
from sqlalchemy.exc import SQLAlchemyError

from configs.config import settings

logging.basicConfig(level=logging.INFO)

logger = logging.getLogger(__name__)

DATABASE_URL = (
    f"postgresql+psycopg2://"
    f"{settings.DB_USER}:"
    f"{settings.DB_PASSWORD}@"
    f"{settings.DB_HOST}:"
    f"{settings.DB_PORT}/"
    f"{settings.DB_NAME}"
)

engine = create_engine(
    DATABASE_URL,

    pool_pre_ping=True,
    pool_size=5,
    max_overflow=10,
    pool_recycle=1800,

    future=True,
)

SessionLocal = sessionmaker(

    bind=engine,

    autoflush=False,

    autocommit=False,

    future=True,
)

Base = declarative_base()


def get_db():
    """
    Creates a new database session.

    Automatically closes the session.
    """

    db = SessionLocal()

    try:
        yield db

    finally:
        db.close()


def test_connection():
    """
    Test database connectivity.
    """

    try:

        with engine.connect() as connection:

            connection.execute(text("SELECT 1"))

            logger.info("Database connection successful.")

    except SQLAlchemyError as e:

        logger.exception("Database connection failed.")

        raise e


if __name__ == "__main__":

    test_connection()