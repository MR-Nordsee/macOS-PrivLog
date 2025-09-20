import logging
from logging.handlers import TimedRotatingFileHandler
import os
import shutil
import json
from datetime import datetime
from fastapi import FastAPI, Request, Response, Depends, HTTPException, Security, Path, Query
from fastapi.security.api_key import APIKeyHeader
from starlette.status import HTTP_403_FORBIDDEN
from contextlib import asynccontextmanager
import aiosqlite
from pydantic import BaseModel
from typing import Callable, Awaitable, Any

# Create Logs directory if it doesn't exist
log_dir = "Logs"

# Generate log filename with current date
log_filename = os.path.join(log_dir, datetime.now().strftime("%Y-%m-%d") + ".log")

# Set up TimedRotatingFileHandler to rotate daily at midnight
backup_count = int(os.getenv("LOGFILE_RETENTION_DAYS", "7"))  # Default to 7 if not set
handler = TimedRotatingFileHandler(
    filename=log_filename,
    when="midnight",
    interval=1,
    backupCount=backup_count,  # Optional: keep 7 days of logs
    encoding="utf-8",
)
handler.suffix = "%Y-%m-%d"  # Optional: suffix for rotated files

# Logging format
formatter = logging.Formatter("%(asctime)s - %(levelname)s - %(message)s")
handler.setFormatter(formatter)

# Set logging level and add handler
logger = logging.getLogger()

log_level = os.getenv("LOG_LEVEL", "INFO")
level_map = {
    "DEBUG": logging.DEBUG,
    "WARNING": logging.WARNING,
    "INFO": logging.INFO
}
logger.setLevel(level_map.get(log_level, logging.INFO))  # Default to INFO
logger.addHandler(handler)

# Path for the sqlite db that stores the data
db_path = "Data/data.db"


# Data model configured in the client profile
class CustomData(BaseModel):
    serial: str


# Basic data that is send by the client
# When more data is send it is ignored
# When less or wrong formats are send it fails
class PrivData(BaseModel):
    admin: bool
    custom_data: CustomData # if you dont use custom data this must be removed
    delayed: bool
    event: str
    expires: str
    machine: str
    reason: str
    timestamp: str
    user: str


def load_api_keys():
    raw = os.getenv("API_KEYS", "")
    pairs = [line.strip() for line in raw.splitlines() if line.strip()]
    return {key: name for key, name in (pair.split(":") for pair in pairs)}

API_KEYS = load_api_keys()

# Header-based API key
api_key_header = APIKeyHeader(name="X-API-Key", auto_error=False)

def get_api_key(api_key: str = Security(api_key_header)):
    if api_key in API_KEYS:
        return API_KEYS[api_key]  # Return user identity or role
    raise HTTPException(
        status_code=HTTP_403_FORBIDDEN,
        detail="Could not validate Request"
    )

# Datenbank initialisieren
@asynccontextmanager
async def lifespan(app: FastAPI):
    async with aiosqlite.connect(db_path) as db:
        await db.execute(
            """
            CREATE TABLE IF NOT EXISTS priv_data (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                admin BOOLEAN,
                custom_serial TEXT,
                delayed BOOLEAN,
                event TEXT,
                expires TEXT,
                machine TEXT,
                reason TEXT,
                timestamp TEXT,
                user TEXT
            )
        """
        )
        await db.commit()
    yield  # App is running...


app = FastAPI(lifespan=lifespan)


# Middleware for request logging
@app.middleware("http")
async def log_requests_and_errors(
    request: Request, call_next: Callable[[Request], Awaitable[Response]]
):
    # Try to get real IP from X-Forwarded-For header
    x_forwarded_for = request.headers.get("X-Forwarded-For")
    if x_forwarded_for:
        # May contain multiple IPs, take the first one
        client_ip = x_forwarded_for.split(",")[0].strip()
    else:
        # Fallback to request.client ip
        client_ip = getattr(request.client, "host", "unknown")

    method = request.method
    url = request.url.path
    logging.info(f"{method} {url} from {client_ip}")

    try:
        response = await call_next(request)
        return response
    except Exception as e:
        logging.error(
            f"Internal Server Error at {method} {url} from {client_ip}: {repr(e)}"
        )
        raise e  # Trigger the error again so that the client can see it.


# POST-Endpoint that needs to be set in configuration profile
@app.post("/privileges")
async def receive_data(data: PrivData) -> dict[str, Any]:
    logging.debug(f"Validated JSON: {data.model_dump()}")
    logging.debug(f"Received JSON: {repr(data)}")

    async with aiosqlite.connect(db_path) as db:
        await db.execute(
            """
            INSERT INTO priv_data (
                admin, custom_serial, delayed, event, expires,
                machine, reason, timestamp, user
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
            (
                data.admin,
                data.custom_data.serial,
                data.delayed,
                data.event,
                data.expires,
                data.machine,
                data.reason,
                data.timestamp,
                data.user,
            ),
        )
        await db.commit()

    return {"status": "success", "received": data}


@app.get("/health")
async def health_check() -> dict[str, str]:
    status = {"status": "ok"}

    # 1. Check database existence and query
    try:
        async with aiosqlite.connect(db_path) as db:
            async with db.execute("SELECT * FROM priv_data LIMIT 1") as cursor:
                row = await cursor.fetchone()
        status["database"] = "reachable"
        if row:
            status["database_sample"] = "found"
        else:
            status["database_sample"] = "empty"
            status["status"] = "warning"
    except Exception as e:
        logging.error(f"Health check DB query error: {repr(e)}")
        status["database"] = "unreachable"
        status["status"] = "error"

    # 2. Check log file writability
    try:
        test_log_path = os.path.join(log_dir, "health_check.log")
        with open(test_log_path, "a", encoding="utf-8") as f:
            f.write(f"Health check log test at {datetime.now()}\n")
        status["log_write"] = "ok"
    except Exception as e:
        logging.error(f"Health check log write error: {repr(e)}")
        status["log_write"] = "failed"
        status["status"] = "error"

    # 3. Check disk space
    try:
        output_diskspace = str(os.getenv("HEALTH_OUTPUT_DISKSPACE", "False"))  # Default to 7 if not set
        _, _, free = shutil.disk_usage(log_dir)
        free_gb = free / (1024**3)
        if output_diskspace == "True":
            status["disk_free_gb"] = f"{free_gb:.2f}" #Enable this if you want to expose this information
        if free_gb < 1:  # Threshold: less than 1GB free
            status["disk_space"] = "low"
            status["status"] = "warning"
        else:
            status["disk_space"] = "sufficient"
    except Exception as e:
        logging.error(f"Health check disk error: {repr(e)}")
        status["disk_space"] = "unknown"
        status["status"] = "error"

    return status

# Authenticated endpoint with serialnumber in URL
@app.get("/get-event-by-serial/{serialnumber}")
async def get_device(serialnumber: str = Path(..., pattern="^[a-zA-Z0-9-]+$"), user: str = Depends(get_api_key)):
    logging.info(f"Request Data from {user} for Serial {serialnumber}")
    async with aiosqlite.connect(db_path) as db:
        db.row_factory = aiosqlite.Row
        query = "SELECT * FROM priv_data WHERE custom_serial = ?"
        async with db.execute(query, (serialnumber,)) as cursor:
            rows = await cursor.fetchall()
            row_dicts = [dict(row) for row in rows]
            logging.debug(f"Entries from DB {json.dumps(row_dicts, indent=2)}")
            return row_dicts
        
# Authenticated endpoint with username in URL
@app.get("/get-event-by-user/{username}")
async def get_user(username: str = Path(..., pattern="^[a-zA-Z0-9-]+$"), user: str = Depends(get_api_key)):
    logging.info(f"Request Data from {user} for user {username}")
    async with aiosqlite.connect(db_path) as db:
        db.row_factory = aiosqlite.Row
        query = "SELECT * FROM priv_data WHERE user = ?"
        async with db.execute(query, (username,)) as cursor:
            rows = await cursor.fetchall()
            row_dicts = [dict(row) for row in rows]
            logging.debug(f"Entries from DB {json.dumps(row_dicts, indent=2)}")
            return row_dicts
        
# Authenticated endpoint with timeframe
@app.get("/get-event-by-time")
async def get_entires(start: datetime = Query(..., description="Start timestamp in ISO format"), end: datetime = Query(..., description="End timestamp in ISO format"), user: str = Depends(get_api_key)):
    logging.info(f"Request Data from {user} between {start} and {end}")
    async with aiosqlite.connect(db_path) as db:
        db.row_factory = aiosqlite.Row
        query = "SELECT * FROM priv_data WHERE timestamp >= ? AND timestamp <= ?"
        async with db.execute(query, (start.isoformat(), end.isoformat())) as cursor:
            rows = await cursor.fetchall()
            row_dicts = [dict(row) for row in rows]
            logging.debug(f"Entries from DB {json.dumps(row_dicts, indent=2)}")
            return row_dicts