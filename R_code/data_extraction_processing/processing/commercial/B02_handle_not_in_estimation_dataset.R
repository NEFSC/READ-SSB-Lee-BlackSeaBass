###############################################################################
# Purpose: 	Handle bsb that is not in the estimation dataset
# Inputs:
#   - BSB_original_combined_dataset$date.Rds (from data_prep_ml.R)
#   - questionable_status_ (from "A01_make_landings_cleaned.R")


# Outputs:

###############################################################################
# Packages 
###############################################################################


library("here")

# load tidyverse and related
library("tidyverse")
library("haven")
library("scales")
library("glue")
# load tidyverse and related
library("tidymodels")


# load machine learning and estimation tools
library("nnet")
library("ranger")
library("partykit")

# load utilities
library("knitr")
library("kableExtra")
library("viridis")
library("conflicted")

#deal with conflicts
conflicts_prefer(dplyr::filter())
conflicts_prefer(dplyr::lag())
conflicts_prefer(purrr::discard())
conflicts_prefer(dplyr::group_rows())
conflicts_prefer(yardstick::spec())
conflicts_prefer(recipes::fixed())
conflicts_prefer(recipes::step())
conflicts_prefer(viridis::viridis_pal())

###############################################################################
# Directories 
###############################################################################
here::i_am("R_code/data_extraction_processing/processing/handle_not_in_estimation_dataset.R")

#############################################################################
my_images<-here("images")
descriptive_images<-here("images","descriptive")
exploratory_images<-here("images","exploratory")
vintage_string<-list.files(here("data_folder","main","commercial"), pattern=glob2rx("BSB_original_combined_dataset*Rds"))
vintage_string<-gsub("BSB_original_combined_dataset","",vintage_string)
vintage_string<-gsub(".Rds","",vintage_string)
vintage_string<-max(vintage_string)
estimation_vintage<-as.character(Sys.Date())



# Load combined_dataset
combined_dataset<-readr::read_rds(file=here("data_folder","main","commercial",glue("BSB_original_combined_dataset{vintage_string}.Rds")))
# Keep rows that did not going into the estimation dataset
excluded_from_estimation_dataset<-combined_dataset %>%
  filter(market_desc!="Unclassified") %>%
  filter(mark_in==0) %>%
  select(-c("mark_in", "flag_in"))


excluded_from_estimation_dataset <-excluded_from_estimation_dataset %>%
   mutate(YEAR = as.numeric(as.character(year)),
          STOCK_ABBREV= as.character(toupper(stockarea)),
          SEMESTER= as.integer(semester),
          MARKET_DESC = toupper(as.character(market_desc)),
          MARKET_DESC = case_when (MARKET_DESC == 'MEDIUM' ~ "MEDIUM OR SELECT",
                                   MARKET_DESC != 'MEDIUM' ~ MARKET_DESC)
  


# load the 'questionable' status dataset
questionable_status<-readr::read_rds(file=here("data_folder","main","commercial",glue("questionable_status_{vintage_string}.Rds")))

# 
# 
 questionable_status<-questionable_status %>%
   mutate(YEAR = as.numeric(as.character(year)),
          STOCK_ABBREV= as.character(toupper(stockarea)),
          SEMESTER= as.integer(semester),
          MARKET_DESC = toupper(as.character(market_desc)),
          MARKET_DESC = case_when (MARKET_DESC == 'MEDIUM' ~ "MEDIUM OR SELECT",
                                 MARKET_DESC != 'MEDIUM' ~ MARKET_DESC)
 
