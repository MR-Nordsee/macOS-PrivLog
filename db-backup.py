#!/usr/bin/env python3

import os
import subprocess
import logging
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Dict

SCRIPT_DIR = Path(__file__).resolve().parent
BACKUP_DIR = SCRIPT_DIR / "backup"
LOG_FILE = SCRIPT_DIR / "Logs" / "backup.log"
TIMESTAMP_FORMAT = "%Y%m%d_%H%M%S"
BACKUP_RETENTION_DAYS = int(os.getenv("BACKUP_RETENTION_DAYS", "30"))


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
    LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s - %(levelname)s - %(message)s",
        handlers=[logging.FileHandler(LOG_FILE, encoding="utf-8")],
    )


def log(message: str) -> None:
    logging.info(message)
    print(message)


def build_pg_dump_command(backup_file: Path, config: dict[str, str | int | bool]) -> list[str]:
    return [
        "pg_dump",
        "--host",
        str(config["host"]),
        "--port",
        str(config["port"]),
        "--username",
        str(config["user"]),
        "--dbname",
        str(config["dbname"]),
        "--format",
        "custom",
        "--file",
        str(backup_file),
    ]


def prepare_env(config: dict[str, str | int | bool]) -> dict[str, str]:
    env = os.environ.copy()
    env["PGSSLMODE"] = str(config.get("sslmode", "disable"))
    password = config.get("password")
    if password:
        env["PGPASSWORD"] = str(password)
    return env


def create_backup_file() -> Path:
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now(timezone.utc).strftime(TIMESTAMP_FORMAT)
    return BACKUP_DIR / f"data_{timestamp}.dump"


def run_pg_dump(backup_file: Path, config: dict[str, str | int | bool]) -> None:
    command = build_pg_dump_command(backup_file, config)
    env = prepare_env(config)

    result = subprocess.run(
        command,
        env=env,
        capture_output=True,
        text=True,
    )

    if result.returncode != 0:
        logging.error("pg_dump failed: %s", result.stderr.strip() or result.stdout.strip())
        raise RuntimeError("pg_dump failed")


def cleanup_old_backups(retention_days: int) -> int:
    cutoff = datetime.now(timezone.utc) - timedelta(days=retention_days)
    deleted_count = 0

    if not BACKUP_DIR.exists():
        return deleted_count

    for backup_file in BACKUP_DIR.glob("data_*.dump"):
        try:
            timestamp_str = backup_file.stem.split("_")[1]
            file_time = datetime.strptime(timestamp_str, TIMESTAMP_FORMAT).replace(tzinfo=timezone.utc)
        except (IndexError, ValueError):
            continue

        if file_time < cutoff:
            backup_file.unlink()
            deleted_count += 1
            logging.info("Deleted backup file %s", backup_file.name)

    return deleted_count


def main() -> int:
    setup_logging()
    log("Starting backup process...")

    DB_CONFIG = load_db_config()
    backup_file = create_backup_file()

    try:
        run_pg_dump(backup_file, DB_CONFIG)
        log(f"Backed up database to '{backup_file}'.")
    except Exception as exc:
        logging.error("Backup failed: %s", exc, exc_info=True)
        print("Backup aborted.")
        return 1

    log("Backup complete.")
    log(f"Starting cleanup of backups older than {BACKUP_RETENTION_DAYS} days...")

    deleted_count = cleanup_old_backups(BACKUP_RETENTION_DAYS)
    if deleted_count == 0:
        log(f"No backup files older than {BACKUP_RETENTION_DAYS} days found.")
    else:
        log(f"Deleted {deleted_count} backup file(s) older than {BACKUP_RETENTION_DAYS} days.")

    log("Cleanup finished.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
