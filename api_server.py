import logging
from logging.handlers import TimedRotatingFileHandler
import os
import shutil
import json
import asyncpg
from datetime import datetime
from fastapi import FastAPI, Request, Response, Depends, HTTPException, Security, Path, Query
from fastapi.security.api_key import APIKeyHeader
from starlette.status import HTTP_403_FORBIDDEN
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.middleware import Middleware
from uvicorn.middleware.proxy_headers import ProxyHeadersMiddleware
from contextlib import asynccontextmanager
from pydantic import BaseModel
from typing import Callable, Awaitable, Any, Dict, List

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

# PostgreSQL database configuration from environment variables
def load_db_config() -> Dict[str, Any]:
    """Load PostgreSQL configuration from environment variables and password file."""
    db_config: dict[str, str | int] = {
        "host": os.getenv("DB_HOST", "localhost"),
        "port": int(os.getenv("DB_PORT", "5432")),
        "database": os.getenv("DB_NAME", "postgres"),
        "user": os.getenv("DB_USER", "postgres"),
        "ssl": os.getenv("DB_SSL", False),
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


DB_CONFIG = load_db_config()


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


def load_api_keys() -> Dict[str, str]:
    path = os.getenv("API_KEYS", "")
    logging.debug(f"Loading API keys from {path}")
    if not path:
        return {}
    try:
        with open(path, "r") as f:
            pairs: List[str] = []
            # Read lines and filter out empty or malformed ones
            for line in f:
                line = line.strip()
                if not line or ":" not in line:
                    continue
                pairs.append(line)
        return {key: name for key, name in (p.split(":", 1) for p in pairs)}

    except FileNotFoundError:
        return {}


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
    """Initialize database connection and create tables if needed."""
    try:
        conn = await asyncpg.connect(**DB_CONFIG)
        logging.info(f"Connected to PostgreSQL database at {DB_CONFIG['host']}:{DB_CONFIG['port']}/{DB_CONFIG['database']}")
        
        # Create table if it doesn't exist
        await conn.execute(
            """
            CREATE TABLE IF NOT EXISTS priv_data (
                id SERIAL PRIMARY KEY,
                admin BOOLEAN,
                custom_serial TEXT,
                delayed BOOLEAN,
                event TEXT,
                expires TEXT,
                machine TEXT,
                reason TEXT,
                timestamp TEXT,
                username TEXT
            )
        """
        )
        logging.debug("Ensured priv_data table exists")
        
        await conn.close()
    except Exception as e:
        logging.error(f"Failed to initialize database: {repr(e)}")
        raise
    
    yield  # App is running...

class LoggingMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next: Callable[[Request], Awaitable[Response]]):
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

middleware = [
    Middleware(ProxyHeadersMiddleware, trusted_hosts="*"), # Trust Nginx as a proxy and rewrite client ip
    Middleware(LoggingMiddleware), # Middleware for request logging
]

app = FastAPI(lifespan=lifespan, middleware=middleware)


# POST-Endpoint that needs to be set in configuration profile
@app.post("/privileges")
async def receive_data(data: PrivData) -> dict[str, Any]:
    logging.debug(f"Validated JSON: {data.model_dump()}")
    logging.debug(f"Received JSON: {repr(data)}")

    conn = await asyncpg.connect(**DB_CONFIG)
    try:
        await conn.execute(
            """
            INSERT INTO priv_data (
                admin, custom_serial, delayed, event, expires,
                machine, reason, timestamp, username
            ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
        """,
            data.admin,
            data.custom_data.serial,
            data.delayed,
            data.event,
            data.expires,
            data.machine,
            data.reason,
            data.timestamp,
            data.user,
        )
        logging.debug("Data inserted successfully")
    finally:
        await conn.close()

    return {"status": "success", "received": data}


@app.get("/health")
async def health_check() -> dict[str, str]:
    status = {"status": "ok"}

    # 1. Check database existence and query
    try:
        conn = await asyncpg.connect(**DB_CONFIG)
        try:
            row = await conn.fetchrow("SELECT * FROM priv_data LIMIT 1")
            status["database"] = "reachable"
            if row:
                status["database_sample"] = "found"
            else:
                status["database_sample"] = "empty"
                status["status"] = "warning"
        finally:
            await conn.close()
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
        output_diskspace = str(os.getenv("HEALTH_OUTPUT_DISKSPACE", "False"))  # Default to False if not set
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
    conn = await asyncpg.connect(**DB_CONFIG)
    try:
        rows = await conn.fetch("SELECT * FROM priv_data WHERE custom_serial = $1", serialnumber)
        row_dicts = [dict(row) for row in rows]
        logging.debug(f"Entries from DB {json.dumps(row_dicts, indent=2, default=str)}")
        return row_dicts
    finally:
        await conn.close()
        
# Authenticated endpoint with username in URL
@app.get("/get-event-by-user/{username}")
async def get_user(username: str = Path(..., pattern="^[a-zA-Z0-9-]+$"), user: str = Depends(get_api_key)):
    logging.info(f"Request Data from {user} for user {username}")
    conn = await asyncpg.connect(**DB_CONFIG)
    try:
        rows = await conn.fetch("SELECT * FROM priv_data WHERE username = $1", username)
        row_dicts = [dict(row) for row in rows]
        logging.debug(f"Entries from DB {json.dumps(row_dicts, indent=2, default=str)}")
        return row_dicts
    finally:
        await conn.close()
        
# Authenticated endpoint with timeframe
@app.get("/get-event-by-time")
async def get_entires(start: datetime = Query(..., description="Start timestamp in ISO format"), end: datetime = Query(..., description="End timestamp in ISO format"), user: str = Depends(get_api_key)):
    logging.info(f"Request Data from {user} between {start} and {end}")
    conn = await asyncpg.connect(**DB_CONFIG)
    try:
        rows = await conn.fetch(
            "SELECT * FROM priv_data WHERE timestamp >= $1 AND timestamp <= $2",
            start.isoformat(),
            end.isoformat()
        )
        row_dicts = [dict(row) for row in rows]
        logging.debug(f"Entries from DB {json.dumps(row_dicts, indent=2, default=str)}")
        return row_dicts
    finally:
        await conn.close()