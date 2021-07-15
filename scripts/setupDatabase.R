
# Following these steps will take about an hour, most of it processing
# time, and you will considerable disk space available. 50GB should be
# enough as of this writing.  The final result will be much smaller.

# install or load required packages using pacman
if (!require("pacman")) install.packages("pacman")
pacman::p_load(pacman, RSQLite, DBI, R.utils)

# create a directory C:/dev/sensorbot/ where the file sensorbot.db will live
devname  <- "C:/dev/"
dirname  <- paste0(devname, "sensorbot/",      showWarnings = FALSE) # parent directory
filename <- paste0(dirname, "sensorbot.db.gz", showWarnings = FALSE) # the g-zip compressed file that will be downloaded
dbname   <- paste0(dirname, "sensorbot.db",    showWarnings = FALSE) # the uncompressed file
url      <- "https://sensorbot.org/sensordata/latest.db.gz" # download the database from here
# create the directory
dir.create(devname)
dir.create(dirname)

# download the database, then unzip it. Removes the uncompressed file when done
options(timeout = 7200) # set the timeout to two hours (default 60s)
download.file(url, filename, "libcurl") # takes ~15 mins
gunzip(filename, dbname, remove = TRUE) # takes ~10 mins

# run a whole bunch of SQL commands. This query will generate hourly 
# summaries of the primary air quality data. 
# This query may take up to an hour to run.
conn <- dbConnect(drv = RSQLite::SQLite(), dbname = dbname)
dbExecute(conn, "DROP TABLE IF EXISTS ts_kv_hourly")
dbExecute(conn, "CREATE TABLE ts_kv_hourly (
                    entity_id STRING NOT NULL,
                    key INT NOT NULL,
                    ts INT NOT NULL,
                    val FLOAT NOT NULL
                 )")
dbExecute(conn, "INSERT INTO ts_kv_hourly
                    SELECT entity_id, key, CAST (ts / (1000 * 60 * 60) AS INT) * (1000 * 60 * 60) AS ts_hourly, AVG(dbl_v) as val
                    FROM ts_kv AS tskv
                    WHERE tskv.key IN (
                        SELECT key_id FROM ts_kv_dictionary WHERE key IN ('plantowerPM1concRaw', 'plantowerPM25concRaw', 'plantowerPM10concRaw', 'pm1', 'pm25', 'pm10', 'blackCarbon')
                    )
                    GROUP BY ts_hourly, entity_id, key")
dbExecute(conn, "ALTER TABLE ts_kv_hourly RENAME COLUMN ts_hourly TO ts")
# The timestamps of sensorbot data are offset by 1 hour from DEQ (DEQ records 
# at the end of the hour and sensorbot rounds down to the start of the hour)
# The next line brings the timestamps into alignment.
dbExecute(conn, "UPDATE ts_kv_hourly SET ts = ts + 60 * 60 * 1000
                    WHERE entity_id in (SELECT id FROM device WHERE type != 'DEQ')")
# Dropping the 30-second data and vacuuming frees up most of the disk space.
dbExecute(conn, "DROP table ts_kv")
dbExecute(conn, "VACUUM")
# Create indexes to make queries go much faster.
dbExecute(conn, "CREATE INDEX ts_kv_hourly_id_key ON ts_kv_hourly(entity_id, key)")
dbExecute(conn, "CREATE INDEX ts_kv_hourly_data_ts ON ts_kv_hourly(ts)")
dbExecute(conn, "CREATE INDEX ts_kv_hourly_data_key ON ts_kv_hourly(key)")
dbExecute(conn, "CREATE INDEX ts_kv_id_key ON ts_kv_hourly(entity_id, key)")
dbExecute(conn, "CREATE INDEX ts_kv_ts ON ts_kv_hourly(ts)")
dbExecute(conn, "DROP VIEW IF EXISTS TSKV")
# Create a view for querying the most essential data
dbExecute(conn, "CREATE VIEW tskv AS
                    SELECT device.name, device.type, ts, dict.key, val FROM ts_kv_hourly AS tskv 
                    INNER JOIN ts_kv_dictionary AS dict ON tskv.key = dict.key_id
                    INNER JOIN device ON device.id = tskv.entity_id")
# Now read the view into a dataframe
df <- dbGetQuery(conn, "select * from tskv")
dbDisconnect(conn)

# save the workspace variable df
save(df, file = paste0(dirname, "sensorbot.RData"))

