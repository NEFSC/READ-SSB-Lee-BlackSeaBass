###############################################################################
# Purpose: 	Handle tilefish that is not in the estimation dataset
# Inputs:
#   - tilefish_original_combined_dataset$date.Rds (from B01_data_prep_tilefish_ml.R)
#   - questionable_tilefish_status_ (from "A01_make_tilefish_landings_cleaned.R")


# During the data prep stages, there is a bit of data that is removed from the training data (estimation
# sample) fpr various reasons. This is mostly because of null values, but also because of prices that are too low
# or too high, landings 'out of sample' or some sketchy stuff from DE/VA, and rows that 
# were landed but not sold.
 
# We put them in a dataset in the predictions folder.

# Outputs: /data_folder/predictions/excluded_from_tilefish_estimation_dataset  

###############################################################################
# Packages 
###############################################################################
#############################################################################
my_images<-here("images")
descriptive_images<-here("images","descriptive")
exploratory_images<-here("images","exploratory")
vintage_string<-list.files(here("data_folder","main","tilefish"), pattern=glob2rx("tilefish_original_combined_dataset*Rds"))
vintage_string<-gsub("tilefish_original_combined_dataset","",vintage_string)
vintage_string<-gsub(".Rds","",vintage_string)
vintage_string<-max(vintage_string)
estimation_vintage<-as.character(Sys.Date())



# Load combined_dataset
combined_dataset<-readr::read_rds(file=here("data_folder","main","tilefish",glue("tilefish_original_combined_dataset{vintage_string}.Rds")))
# Keep rows that did not going into the estimation dataset
excluded_from_estimation_dataset<-combined_dataset %>%
  filter(market_desc!="Unclassified") %>%
  filter(mark_in==0) %>%
  select(-c("mark_in", "flag_in"))


excluded_from_estimation_dataset <-excluded_from_estimation_dataset %>%
   mutate(YEAR = as.numeric(as.character(year)),
          BLOCK_ID= as.integer(semester), #create block_id (for stockeff) that is the semester.
          MARKET_DESC = toupper(as.character(market_desc))#, this market desc renaming will be wrong
#          MARKET_DESC = case_when (MARKET_DESC == 'MEDIUM' ~ "MEDIUM OR SELECT",
#                                  MARKET_DESC != 'MEDIUM' ~ MARKET_DESC)
   )
  
excluded_from_estimation_dataset<-excluded_from_estimation_dataset %>%
  group_by(YEAR, BLOCK_ID, MARKET_DESC, status) %>%
  summarise(LANDINGS_CAMS_KG=sum(livlb, na.rm=TRUE)/lbs_to_kg,.groups="drop_last")



# Load questionable status dataset

qs <- readr::read_rds(file=here("data_folder","main","tilefish",glue("questionable_tilefish_status_{vintage_string}.Rds")))

qs<-qs %>%
   mutate(YEAR = as.numeric(as.character(year)),
          BLOCK_ID= as.integer(semester), #create block_id (for stockeff) that is the semester.
          MARKET_DESC = toupper(as.character(market_desc))#, this market desc renaming will be wrong
#          MARKET_DESC = case_when (MARKET_DESC == 'MEDIUM' ~ "MEDIUM OR SELECT",
#                                 MARKET_DESC != 'MEDIUM' ~ MARKET_DESC)
   )


qs<-qs %>%
  group_by(YEAR, BLOCK_ID, MARKET_DESC, status) %>%
  summarise(LANDINGS_CAMS_KG=sum(livlb, na.rm=TRUE)/lbs_to_kg,.groups="drop_last")


excluded_from_estimation_dataset<-rbind(excluded_from_estimation_dataset,qs) %>%
  group_by(YEAR, BLOCK_ID, MARKET_DESC, status) %>%
  summarise(LANDINGS_CAMS_KG=sum(LANDINGS_CAMS_KG, na.rm=TRUE),.groups="drop_last")
write_rds(excluded_from_estimation_dataset, file=here("data_folder","predictions",glue("excluded_from_tilefish_estimation_dataset_{vintage_string}.Rds")))


