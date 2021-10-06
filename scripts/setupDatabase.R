# Downloads the latest version of the Sensorbot database, unzips it,
# and averages the data by hour. Creates a view of the hourly data
# joined with device name and measurement type. Saves this view as a
# dataframe. All files are stored in "C:/dev/sensorbot"

# This program will take about an hour to run, most of it processing
# time, and you will considerable disk space available. 50GB should be
# enough as of this writing. The final result will be much smaller.

# install or load required packages using pacman
if (!require("pacman")) install.packages("pacman")
pacman::p_load(pacman, RSQLite, DBI, R.utils)

# create a directory C:/dev/sensorbot/ where the file sensorbot.db will live
devname  <- "C:/dev/"
dirname  <- paste0(devname, "sensorbot/") # parent directory
filename <- paste0(dirname, "sensorbot.db.gz") # the g-zip compressed file that will be downloaded
dbname   <- paste0(dirname, "sensorbot.db") # the uncompressed file
savename <- paste0(dirname, "sensorbot.RData")
url      <- "https://sensorbot.org/sensordata/latest.db.gz" # download the database from here

dir.create(devname, showWarnings = FALSE)
dir.create(dirname, showWarnings = FALSE)

# close the connection from the last session, if it still exists
if (exists("conn")) {
  suppressWarnings(dbDisconnect(conn))
}

# download the latest version of the database if a copy doesn't already exist.
# If you need the very latest version, delete the file C:/dev/sensorbot/sensorbot.db.gz
# before running this script to re-download the database.
if (!file.exists(filename)) {
  noquote(paste0("downloading file ", filename))
  options(timeout = 7200) # set the timeout to two hours (default 60s)
  download.file(url, filename, "libcurl") # takes ~15 mins
}

# unzip the database if it's not already unzipped. If you need to reset 
# the database, delete the file C:/dev/sensorbot/sensorbot.db
# before running this script to re-extract it from the zipped file.
if (!file.exists(dbname)) {
  noquote(paste0("unzipping file ", dbname))
  gunzip(filename, dbname, remove = FALSE) # takes ~5 mins
  # set remove = TRUE to delete the compressed file after unzipping
}

# run a whole bunch of SQL commands. This query will generate hourly 
# summaries of the primary air quality data. This query may take up to 
# an hour to run.
noquote("creating hourly data averages")
conn <- dbConnect(drv = RSQLite::SQLite(), dbname = dbname)
dbExecute(conn, 
  "DROP TABLE IF EXISTS ts_kv_hourly")
dbExecute(conn, 
  "CREATE TABLE ts_kv_hourly (
    entity_id STRING NOT NULL,
    key INT NOT NULL,
    ts INT NOT NULL,
    val FLOAT
  )"
)
dbExecute(conn, 
  "INSERT INTO ts_kv_hourly
    SELECT entity_id, key, 
      CAST (ts / (1000 * 60 * 60) AS INT) * (1000 * 60 * 60) 
        AS ts_hourly, 
      AVG(dbl_v) 
        AS val
    FROM ts_kv AS tskv
    WHERE tskv.key IN (
      SELECT key_id FROM ts_kv_dictionary WHERE key IN (
        'plantowerPM1concRaw', 
        'plantowerPM25concRaw', 
        'plantowerPM10concRaw', 
        'pm1', 
        'pm25', 
        'pm10', 
        'blackCarbon', 
        'temperature', 
        'humidity', 
        'pressure'
      )
    )
    GROUP BY ts_hourly, entity_id, key"
)
# The timestamps of sensorbot data are offset by 1 hour from DEQ (DEQ records 
# at the end of the hour and sensorbot rounds down to the start of the hour)
# The next line brings the timestamps into alignment.
dbExecute(conn, 
 "UPDATE ts_kv_hourly SET ts = ts + 60 * 60 * 1000
  WHERE entity_id IN (
    SELECT id FROM device WHERE type != 'DEQ'
  )"
)
# Dropping the 30-second data and vacuuming frees up most of the disk space.
dbExecute(conn, "DROP table ts_kv")
dbExecute(conn, "VACUUM")
# Create indexes to make queries go much faster.
dbExecute(conn, "CREATE INDEX ts_kv_hourly_id_key ON ts_kv_hourly(entity_id, key)")
dbExecute(conn, "CREATE INDEX ts_kv_hourly_data_ts ON ts_kv_hourly(ts)")
dbExecute(conn, "CREATE INDEX ts_kv_hourly_data_key ON ts_kv_hourly(key)")
dbExecute(conn, "CREATE INDEX ts_kv_id_key ON ts_kv_hourly(entity_id, key)")
dbExecute(conn, "CREATE INDEX ts_kv_ts ON ts_kv_hourly(ts)")
# Create a view for querying the most essential data
dbExecute(conn, "DROP VIEW IF EXISTS TSKV")
dbExecute(conn, 
 "CREATE VIEW tskv AS
    SELECT device.name, device.type, ts, dict.key, val 
      FROM ts_kv_hourly AS tskv 
    INNER JOIN ts_kv_dictionary AS dict 
      ON tskv.key = dict.key_id
    INNER JOIN device 
      ON device.id = tskv.entity_id"
)
# Now read the view into a dataframe
df <- dbGetQuery(conn, "select * from tskv")
dbDisconnect(conn)

# save the workspace variable df
save(df, file = savename)

noquote(
  paste0(
    "Sensorbot data is stored in the variable 'df'. ", 
    "To load, type: load('", savename, "')"
  )
)
