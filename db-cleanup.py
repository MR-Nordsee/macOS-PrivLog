import asyncio
import logging
import os
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Dict

import asyncpg

SCRIPT_DIR = Path(__file__).resolve().parent
LOG_FILE = SCRIPT_DIR / "Logs" / "database-cleanup.log"
TABLE_NAME = "priv_data"
FIELD_NAME = "timestamp"


def parse_bool(value: str | None, default: bool = False) -> bool:
    if value is None:
        return default
    normalized = value.strip().lower()
    if normalized in {"1", "true", "yes", "on"}:
        return True
    if normalized in {"0", "false", "no", "off"}:
        return False
    return default


# PostgreSQL database configuration from environment variables
def load_db_config() -> Dict[str, Any]:
    """Load PostgreSQL configuration from environment variables and password file."""
    db_config: dict[str, str | int] = {
        "host": os.getenv("DB_HOST", "localhost"),
        "port": int(os.getenv("DB_PORT", "5432")),
        "database": os.getenv("DB_NAME", "postgres"),
        "user": os.getenv("DB_USER", "postgres"),
        "ssl": parse_bool(os.getenv("DB_SSL", "false"), default=False),
    }
    
    # Load password from file
    password_file = os.getenv("DB_PASSWORD_FILE")
    if password_file and os.path.exists(password_file):
        try:
            with open(password_file, "r") as f:
                db_config["password"] = f.read().strip()
            logging.debug(f"Loaded database password from {password_file}")
        except Exception as e:
            logging.error(f"Failed to load password from {password_file}: {repr(e)}")
            raise
    else:
        logging.warning("DB_PASSWORD_FILE not set or file does not exist, using empty password")
        db_config["password"] = ""
    
    return db_config


def setup_logging() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s - %(levelname)s - %(message)s",
        handlers=[logging.FileHandler(LOG_FILE, encoding="utf-8")],
    )


def get_cutoff_timestamp(days: int) -> str:
    cutoff = datetime.now(timezone.utc) - timedelta(days=days)
    return cutoff.replace(microsecond=0).isoformat().replace("+00:00", "Z")


async def cleanup_old_rows(days: int) -> int:
    DB_CONFIG = load_db_config()
    cutoff = get_cutoff_timestamp(days)
    query_count = f"SELECT COUNT(*) FROM {TABLE_NAME} WHERE {FIELD_NAME} < $1"
    query_delete = f"DELETE FROM {TABLE_NAME} WHERE {FIELD_NAME} < $1"

    conn = await asyncpg.connect(**DB_CONFIG)
    try:
        num_deleted = await conn.fetchval(query_count, cutoff)
        await conn.execute(query_delete, cutoff)
        return int(num_deleted or 0)
    finally:
        await conn.close()


async def main() -> int:
    setup_logging()
    days = int(os.getenv("DATABASE_RETENTION_DAYS", "90"))
    current_date = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    try:
        deleted = await cleanup_old_rows(days)
        logging.info("Deleted %d entries older than %d days", deleted, days)
        print(f"[{current_date}] Deleted {deleted} entries older than {days} days")
        return 0
    except Exception as exc:
        logging.error("Database cleanup failed: %s", exc, exc_info=True)
        print(f"[{current_date}] ERROR: Database cleanup failed")
        return 1


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
