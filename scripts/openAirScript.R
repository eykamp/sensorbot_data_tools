# Re-formats the dataframe loaded from the setupDatabase.R script for use
# with the OpenAir package. https://bookdown.org/david_carslaw/openair/
# Turns the tall and skinny dataframe into a wide dataframe with the 
# timestamp and device name as the identification variables and the 
# different measurements in separate columns.
# Also converts the timestamps to datetime objects. Run the OpenAir 
# functions at the end of the script to create various visualizations.

# install or load required packages using pacman
if (!require("pacman")) install.packages("pacman")
pacman::p_load(pacman, openair, tidyverse, magrittr, hash)

# load the dataframe saved from the setupDatabase.R script
load("C:/dev/sensorbot/sensorbot.RData")

# create a dictionary for renaming the columns
# new_names[[oldName]] <- newName
new_names <- hash()
new_names[["plantowerPM1concRaw"]]  <- "pm1"
new_names[["plantowerPM25concRaw"]] <- "pm25"
new_names[["plantowerPM10concRaw"]] <- "pm10"
new_names[["humidity"]]             <- "humidity"
new_names[["pressure"]]             <- "pressure"
new_names[["temperature"]]          <- "temperature"
new_names[["pm1"]]                  <- "pm1_deq"
new_names[["pm25"]]                 <- "pm25_deq"
new_names[["pm10"]]                 <- "pm10_deq"

unique_cols = c("name", "ts")
df_processed <- unique(df[unique_cols])
for (new_key in unique(df$key)) {
  new_column <- data.frame(filter(df, key == new_key)) %>%
    select(all_of(unique_cols), val)
  df_processed <- left_join(df_processed, new_column, by = unique_cols)
  colnames(df_processed)[colnames(df_processed) == "val"] <- new_names[[new_key]]
}

df_processed <- 
  df_processed %>%
  mutate(
    date = ts %>%
      divide_by(1000) %>%
      round() %>%
      as.POSIXct(origin = "1970-01-01"),
    .keep = "unused",
    .after = name
  )

# The following are functions from the OpenAir library. Run them one
# at a time to generate nice-looking visualizations.

trendLevel(filter(df_processed, !is.na(pm25)), poll = "pm25")

# myOutput <- timeVariation(df_processed, poll = "pm25")

# myOutput <- timeVariation(df_processed, poll = c("pm1", "pm25", "pm10"))

# plot(myOutput, subset = "hour")

# calendarPlot(df_processed, poll = "pm25")

