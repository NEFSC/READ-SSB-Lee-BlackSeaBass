###############################################################################
# 00_commercial_processing_wrapper.R
# Purpose: R equivalent of 00_commercial_processing_wrapper.do
#          Sets vintage strings and sources A01-A04 in order.
#
# Set in_string and vintage_string by hand before running.
###############################################################################
library("here")
library("tidyverse")
library("lubridate")
library("glue")
library("slider")

library("conflicted")
conflicts_prefer(dplyr::filter)
conflicts_prefer(lubridate::year)
conflicts_prefer(lubridate::month)
conflicts_prefer(lubridate::week)
conflicts_prefer(dplyr::summarise)
conflicts_prefer(dplyr::arrange)


here::i_am("R_code/data_extraction_processing/processing/commercial/00_commercial_processing_wrapper.R")

my_datapull<-dirname(here())
my_datapull<-file.path(my_datapull,"READ-SSB-Lee-BSB-DataPull")

bsb_data_dir<-here("data_folder", "main", "commercial")     
dir.create(bsb_data_dir, showWarnings=FALSE)


in_string      <- "2026-05-01"   # matches Stata in_string / data-pull vintage
vintage_string <- Sys.Date()   # matches Stata vintage_string / output vintage
lbs_to_kg<-2.20462

source(here("R_code", "analysis","helpers",  "gear_market_helpers.R"))

source(here("R_code", "data_extraction_processing","processing","commercial",  "A01_make_landings_cleaned.R"))
source(here("R_code", "data_extraction_processing","processing","commercial",  "A02_make_daily_stats.R"))
source(here("R_code", "data_extraction_processing","processing", "commercial", "A03_make_dealer_stats.R"))
source(here("R_code", "data_extraction_processing","processing", "commercial", "A04_make_moving_average_prices.R"))

#final data prep.
# there's no great reason to have these start with B, execpt that the A files were previously made by stata.
source(here("R_code", "data_extraction_processing","processing",  "commercial", "B01_data_prep_ml.R"))
# aggreggate landings that were excluded

source(here("R_code", "data_extraction_processing","processing",  "commercial", "B02_handle_not_in_estimation_dataset.R"))
