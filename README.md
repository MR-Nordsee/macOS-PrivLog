# Privileges-Server
This is a simple standalone server for handling [https://github.com/SAP/macOS-enterprise-privileges](https://github.com/SAP/macOS-enterprise-privileges/blob) webhooks.  
The goal is to provide a lightweight server that can support moderately large environments.

# Setup
## Requirements
- Linux server with Docker + Docker Compose
  - [https://docs.docker.com/compose/install/linux/](https://docs.docker.com/compose/install/linux/)
  - [https://docs.docker.com/engine/install/ubuntu/](https://docs.docker.com/engine/install/ubuntu/)
- Server accessible from the internet on ports 80 and 443 (for Let's Encrypt certificates)
- DNS entry pointing to the server
- Internet access (to download the SWAG container)

## Quick Start
1. Adjust the docker compose.yaml
   - Set the SWAG URL to your DNS Name
   - Adjust the image name for macOS-PrivLog/webhook to arm64 or amd64
   - **Remove or provide new API values in API_KEYS**
2. Create the container  
   `docker compose up -d`
3. Adjust SWAG config
   - Set the `server_name` in the nginx-default.conf from this repo (line 14) to your DNS Name
   - Replace the SWAG config at */config/nginx/site-confs/default* with the one from this repo
4. Test and Final Steps
   - Restart containers if needed to reload configs
   - Check logs and errors using `docker logs CONTAINER`
   - **By default, staging SSL certificates are used.** To obtain real certificates, set the `Staging` variable to false in the compose.yaml for SWAG
   - The server should now respond to POST requests at https://SERVER/privileges
   - Example data is available in `exampledata.txt`, or use the `Test-api.ps1` script
   - If you need to look inside the Container use `docker exec -it webhook /bin/bash`
   - Set the Log Level to INFO for later use

## Update
To update, follow these steps:
1. Import the latest version of the container  
   `docker compose pull`
2. Restart the service  
   `docker compose up -d`

## Customization
For internal setups or custom SSL certificates, refer to the SWAG documentation: [https://docs.linuxserver.io/general/swag/](https://docs.linuxserver.io/general/swag/)

## Docker Compose Variables
Several options can be configured via environment variables in the compose.yaml.  
These values are optional. If not set, defaults will be used.

| Variable                | Type                    | Description                                                                                                                                     | Default                                                              |
| ----------------------- | ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------- |
| BACKUP_RETENTION_DAYS   | int                    | Defines how many days backups of `data.db` are retained before deletion.                                                                        | 30 days                                                               |
| DATABASE_RETENTION_DAYS | int                    | Defines how many days old entries in `data.db` are retained. The `db-cleanup.sh` script runs daily at 00:10.                                    | 90 days                                                               |
| LOG_LEVEL               | String (DEBUG, INFO, WARNING) | Sets the log level for the FASTAPI script.                                                                                                      | INFO                                                                  |
| LOGFILE_RETENTION_DAYS  | int                    | Defines how many days FASTAPI log files are retained before being overwritten. Backup and cleanup logs are not deleted!                         | 7 days                                                                |
| DB_BACKUP_CRONJOB       | String (Cronjob)         | Allows custom scheduling for database backups.                                                                                                  | Daily at 00:05 (5 minutes before database cleanup)                   |
| HEALTH_OUTPUT_DISKSPACE | Bool                    | Enables the `disk_free_gb` value in the Health API. See Monitoring.                                                                             | False                                                                 |
| API_KEYS                | String (Multi)          | Defines API keys and their labels for accessing data via the API. Format: `KEY:NAME`                                                            | None                                                                  |

# Configuration Profile
Here is an example configuration for remote logging.  
I use the device's serial number as CustomData. Adjustments can be made as described in the CustomData section.

```xml
<key>RemoteLogging</key>
<dict>
    <key>ServerAddress</key>
    <string>https://serverURL/privileges</string>
    <key>ServerType</key>
    <string>webhook</string>
    <key>QueueUnsentEvents</key>
    <true />
    <key>QueuedEventsMax</key>
    <integer>200</integer>
    <key>WebhookCustomData</key>
    <dict>
        <key>serial</key>
        <string>$SERIALNUMBER</string>
    </dict>
</dict>
```

# Data Retrieval
There are API endpoints available to retrieve data from the database.
Requests are authenticated using an API key in the `X-API-Key` header.
The API key is defined in the compose file. A name is assigned to the key, which is logged to track who accessed the data.

- For all entries with a specific serial number:  
  `/get-event-by-serial/{serialnumber}`
- For all entries with a specific username:  
  `/get-event-by-user/{username}`
- For all entries within a specified time range:  
  `/get-event-by-time?start=2025-09-01T00:00:00&end=2025-09-20T23:59:59`

# Information and Sources
For the Python code, I used Pylance in strict mode to avoid missing anything.<br>
**See NOTICE file for information on Licences.** <br>

Here are the links to the projects, modules, and resources used:

| Object                                        | Source                                                                                                  |
| --------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| Webhook code from macOS-enterprise-privileges | https://github.com/SAP/macOS-enterprise-privileges/blob/main/source/PrivilegesAgent/Classes/MTWebhook.h |
| API based on FastAPI                          | https://github.com/fastapi/fastapi                                                                      |
| Web server used: uvicorn                      | https://github.com/encode/uvicorn                                                                       |
| Field validation with Pydantic                | https://github.com/pydantic/pydantic                                                                    |
| SQLite DB handled via aiosqlite               | https://github.com/omnilib/aiosqlite                                                                    |
| Docker-compatible cronjob scheduler           | https://github.com/aptible/supercronic                                                                  |
| Task execution as non-root user: Supervisor   | https://github.com/Supervisor/supervisor                                                                |

This project uses [uvicorn](https://github.com/Kludex/uvicorn), licensed under a BSD 3-Clause license.
See Licences/NOTICE-uvicorn file for details.

This project uses [starlette](https://github.com/Kludex/starlette), licensed under a BSD 3-Clause license.
See Licences/NOTICE-uvicorn file for details.

This project uses [supervisor](https://github.com/Supervisor/supervisor), which is licensed under a BSD-style license.
See Licences/NOTICE-supervisor for details.


# Database
The SQLite database `data.db` contains a table named `priv_data` where the fields from the webhook are stored.

| Field         | Format             | Description                                                                 |
|---------------|--------------------|------------------------------------------------------------------------------|
| id            | int AUTOINCREMENT  | Unique ID of the database entry.                                            |
| admin         | BOOL               | Indicates whether the user has admin rights.                                |
| custom_serial | TEXT               | Custom webhook field. Stores the device serial number as a text field.      |
| delayed       | BOOL               | Indicates whether the event was delayed before being sent to the webhook.   |
| event         | TEXT               | Type of Privileges event.                                                   |
| expires       | TEXT               | Timestamp when admin rights will automatically expire.                      |
| machine       | TEXT               | Unique machine ID in GUID format.                                           |
| reason        | TEXT               | Reason entered by the user to request admin rights.                         |
| timestamp     | TEXT               | Timestamp when the event occurred.                                          |
| user          | TEXT               | Username of the affected user.                                              |

# Logging
If an `X-Forwarded-For` header is present, it will be logged as the client IP.

- `Logs/YYYY-MM-DD.log`  
  Request and debug logs from the API server. Includes IP addresses in INFO mode. In DEBUG mode, also includes the payload.

- `Logs/backup.log`  
  The backup and cleanup scripts log their activities here. Includes timestamps, filenames, and backup paths. When deleting, it logs the selected retention period, number of deleted files, and filenames.

- `Logs/database-cleanup.log`  
  Logs when entries are removed from the database due to age. Includes timestamp, count, retention period, and the cutoff date.

- `logfile-cleanup.log`  
  Logs when log files are removed from the Logs folder due to age. Includes timestamp, count, retention period, and the cutoff date.

# Monitoring
A GET request to `/health` returns a JSON object. This endpoint can be integrated into external monitoring systems.

```json
{
  "status":"ok",
  "database":"reachable",
  "database_sample":"found",
  "log_write":"ok",
  "disk_space":"sufficient"
}
```

- `status` = General status of the server  
  - ok  
  - warning = Functionality may be impaired  
  - error = Functionality is impaired  

- `database` = Checks the availability of the database  
  - reachable  
  - unreachable = If there are errors accessing or querying the database. Sets status to error.

- `database_sample` = Attempts to query data from the database  
  - found  
  - empty = No entries in the database. Should only occur on new servers, which triggers a warning status. This may also indicate that the old database is missing. The health check will create an empty database.

- `log_write` = Writes to the log folder to check for potential logging issues  
  - ok  
  - failed = Sets status to error.

- `disk_space` = Checks whether the configured amount of disk space (default 1GB) is still available  
  - sufficient = Threshold is met  
  - low = Threshold is undercut. Sets status to warning.  
  - unknown = Error during check. Sets status to error.

- Optional: `disk_free_gb` = Indicates how much disk space is still free. Must be enabled in the script.

# CustomData
This setup uses a field containing the device serial number as custom data for the webhooks (`custom_serial`).  
If you want to modify, extend, or remove this field, you’ll find the relevant information here.

## Data Definition
Adjust/add the definition in the `CustomData` class.  
Remove the definition from the `PrivData` class.

```python
class CustomData(BaseModel):
    serial: str

class PrivData(BaseModel):
    admin: bool
    custom_data: CustomData
    delayed: bool
    event: str
    expires: str
    machine: str
    reason: str
    timestamp: str
    user: str
```

## Adjusting `data.db` Structure
To create the table, modify/add/remove the fields as needed:

```sql
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
```

## Adjust SQL Prepared Statement
Update/add/remove fields in the SQL statement.  
Then update/add/remove the corresponding values used in the query.

```python
async with aiosqlite.connect("data.db") as db:
        await db.execute("""
            INSERT INTO priv_data (
                admin, custom_serial, delayed, event, expires,
                machine, reason, timestamp, user
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            data.admin,
            data.custom_data.serial,
            data.delayed,
            data.event,
            data.expires,
            data.machine,
            data.reason,
            data.timestamp,
            data.user
        ))
        await db.commit()
```


## Build New Container
After modifying the scripts, the container must be rebuilt if you want to use them locally.
The `build.sh` script in the `helper-scripts` folder builds and exports the containers.
Feel free to make a pull requst for integration.

# File Description
To avoid forgetting what each file is for—and to help everyone quickly understand what belongs where—here are a few notes on what’s included:

- `api_server.py`  
  Single server file. Handles logging, request processing, and data storage.

- `backup-cleanup.sh`  
  Deletes backups older than X days. The number of days can be passed as an argument.

- `db-backup.sh`  
  Creates a backup in the `Backup` subfolder. The filename includes the creation timestamp.

- `db-cleanup.sh`  
  Deletes data from the current database that is older than X days. Uses the `timestamp` field. The number of days can be passed as an argument.

- `export-serial.sh`  
  Exports all entries with a specific serial number from the DB using the custom field `custom_serial`, and writes them to a CSV file.

- `export-data.sh`  
  Exports all entries from the database and writes them to a CSV file.

- `log-cleanup.sh`  
  Deletes log files from the `Logs` subfolder that are older than X days. The number of days can be passed as an argument.

- `setup.sh`  
  Initial setup for the server. Creates a Python environment and installs required modules from `requirements.txt` (tested with Python 3.12).

- `update.sh`  
  Helper script to update Python modules.

- `build.sh`  
  Helper script to build the containers.

- `init.sh`  
  Used as the entry point in the container. Fixes folder permissions and then starts `supervisord`.

- `supervisord.conf`  
  Defines startup for the FastAPI server using Python and Supercronic with the service user.

- `Dockerfile`  
  Build instructions for the container image.

- `nginx-default.conf`  
  Nginx configuration for SWAG as a reverse proxy for the API container.

- `cronjobs`  
  Cronjob definitions inside the container, read by Supercronic.

- `Test-api.sh`  
  A PowerShell script to test API calls. Performs various valid and invalid requests.

- `requirements.txt`  
  Contains required versions and dependencies for the script. Used to set up the correct Python environment.

- `data.db`  
  SQLite database for storing all information.

- `exampledata.txt`  
  A few example requests in JSON format, as sent by the client.

# Ideas & ToDos:
- Setup for SWAG (replace default nginx config)
- Define custom data via config file (may require table versioning)
- Implement API tests using Bruno