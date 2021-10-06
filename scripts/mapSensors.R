# Creates a map of the Portland area with the locations of sensorbot sensors, 
# colored by the latest PM2.5 readings in the database.

# install or load required packages using pacman
if (!require("pacman")) install.packages("pacman")
pacman::p_load(pacman, RSQLite, DBI, ggmap, tidyverse, RColorBrewer)

dbname <- "C:/dev/sensorbot/sensorbot.db"

conn <- dbConnect(drv = RSQLite::SQLite(), dbname = dbname)
sensorLocs <- dbGetQuery(conn, 
 "SELECT name, attribute_key, attribute_kv.long_v, attribute_kv.dbl_v,
  attribute_kv.str_v, ts_kv_latest.dbl_v AS 'latest_pm25'
  FROM attribute_kv 
  JOIN device 
    ON attribute_kv.entity_id = device.id 
  JOIN ts_kv_latest 
    ON attribute_kv.entity_id = ts_kv_latest.entity_id 
  WHERE (attribute_key = 'longitude' OR attribute_key = 'latitude')
  AND (key = 9 OR key = 13) 
  ORDER BY name, attribute_key"
)
dbDisconnect(conn)

lats <- sensorLocs %>%
  filter(attribute_key == "latitude") %>%
  select(lats = dbl_v)
longs <- sensorLocs %>%
  filter(attribute_key == "longitude") %>%
  select(
    longs = dbl_v,
    pm25 = latest_pm25)
latLongs = data.frame(lats, longs)

# get_map() retrieves the map image to use as the background, from one of three
# sources: Google Maps, OpenStreetMap, or Stamen Maps. Of these, only Stamen
# Maps works out of the box; for Google Maps you must configure an API key,
# which requires some a credit card number (though it shouldn't cost much if 
# anything to use). https://www.youtube.com/watch?v=OGTG1l7yin4

# Using the following format for mapBounds makes get_map() default to Stamen
# Maps. For some reason, setting source = "stamen" doesn't always work.
mapBounds = c(
  left =   -122.85,
  bottom = 45.40,
  right =  -122.30,
  top =    45.65
)

map <- get_map(mapBounds)
ggmap(map, 
  base_layer = ggplot(
    data = latLongs, 
    mapping = aes(x = longs, y = lats, color = pm25)
  )
) + 
  geom_point() + 
  scale_color_distiller(palette = "YlOrRd", direction = 1, trans = "log")

# scale_color_distiller uses RColorBrewer palettes.
# https://www.r-graph-gallery.com/38-rcolorbrewers-palettes.html

