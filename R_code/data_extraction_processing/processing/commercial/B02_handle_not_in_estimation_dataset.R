###############################################################################
# Purpose: 	Handle bsb that is not in the estimation dataset
# Inputs:
#   - BSB_original_combined_dataset$date.Rds (from data_prep_ml.R)
#   - questionable_status_ (from "A01_make_landings_cleaned.R")


# During the data prep stages, there is a bit of data that is removed from the training data (estimation
# sample) fpr various reasons. This is mostly because of null values, but also because of prices that are too low
# or too high, landings 'out of sample' or some sketchy stuff from DE/VA, and rows that 
# were landed but not sold.
 
# We put them in a dataset in the predictions folder.

# Outputs: /data_folder/predictions/excluded_from_estimation_dataset  

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
here::i_am("R_code/data_extraction_processing/processing/commercial/B02_handle_not_in_estimation_dataset.R")

#############################################################################
my_images<-here("images")
descriptive_images<-here("images","descriptive")
exploratory_images<-here("images","exploratory")

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
          BLOCK_ID= as.integer(semester), #create block_id (for stockeff) that is the semester.
          MARKET_DESC = toupper(as.character(market_desc)),
          MARKET_DESC = case_when (MARKET_DESC == 'MEDIUM' ~ "MEDIUM OR SELECT",
                                   MARKET_DESC != 'MEDIUM' ~ MARKET_DESC)
   )
  
excluded_from_estimation_dataset<-excluded_from_estimation_dataset %>%
  group_by(YEAR,STOCK_ABBREV, BLOCK_ID, MARKET_DESC, status) %>%
  summarise(LANDINGS_CAMS_KG=sum(livlb, na.rm=TRUE)/lbs_to_kg,.groups="drop_last")



# Load questionable status dataset
# these are true data errors.
qs <- readr::read_rds(file=here("data_folder","main","commercial",glue("questionable_status_{vintage_string}.Rds")))

qs<-qs %>%
   mutate(YEAR = as.numeric(as.character(year)),
          STOCK_ABBREV= as.character(toupper(stockarea)),
          BLOCK_ID= as.integer(semester), #create block_id (for stockeff) that is the semester.
          MARKET_DESC = toupper(as.character(market_desc)),
          MARKET_DESC = case_when (MARKET_DESC == 'MEDIUM' ~ "MEDIUM OR SELECT",
                                 MARKET_DESC != 'MEDIUM' ~ MARKET_DESC)
   )


qs<-qs %>%
  group_by(YEAR,STOCK_ABBREV, BLOCK_ID, MARKET_DESC, status) %>%
  summarise(LANDINGS_CAMS_KG=sum(livlb, na.rm=TRUE)/lbs_to_kg,.groups="drop_last")


excluded_from_estimation_dataset<-rbind(excluded_from_estimation_dataset,qs) %>%
  group_by(YEAR,STOCK_ABBREV, BLOCK_ID, MARKET_DESC, status) %>%
  summarise(LANDINGS_CAMS_KG=sum(LANDINGS_CAMS_KG, na.rm=TRUE),.groups="drop_last")
write_rds(excluded_from_estimation_dataset, file=here("data_folder","predictions",glue("excluded_from_estimation_dataset_{vintage_string}.Rds")))


# summarise the estimation dataset
classed_dataset<-combined_dataset %>%
  filter(market_desc!="Unclassified")

table(classed_dataset$mark_in)

#total pounds
totals<-classed_dataset %>%
  group_by(mark_in) %>%
  summarise(total_liv_mt=sum(livlb, na.rm=TRUE)/(1000*lbs_to_kg),
            valueR_CPI_M=sum(valueR_CPI, na.rm=TRUE)/1000000)

#total by market_desc
by_market_desc<-classed_dataset %>%
  group_by(market_desc, mark_in) %>%
  summarise(total_liv_mt=sum(livlb, na.rm=TRUE)/(1000*lbs_to_kg),
            valueR_CPI_M=sum(valueR_CPI, na.rm=TRUE)/1000000) %>%
  ungroup() %>%
  group_by(market_desc)%>%
  mutate(liv_mt=sum(total_liv_mt),
         val=sum(valueR_CPI_M)) %>%
  mutate(total_frac=total_liv_mt/liv_mt,
         val_frac=valueR_CPI_M/val) %>%
  select(-liv_mt, -val) %>%
  filter(mark_in==FALSE)


#total by year

by_year<-classed_dataset %>%
  group_by(year, mark_in) %>%
  summarise(total_liv_mt=sum(livlb, na.rm=TRUE)/(1000*lbs_to_kg),
            valueR_CPI_M=sum(valueR_CPI, na.rm=TRUE)/1000000) %>%
ungroup() %>%
  group_by(year)%>%
  mutate(liv_mt=sum(total_liv_mt),
         val=sum(valueR_CPI_M)) %>%
  mutate(total_frac=total_liv_mt/liv_mt,
         val_frac=valueR_CPI_M/val) %>%
  ungroup() %>%
  select(-liv_mt, -val) %>%
  filter(mark_in==FALSE)






# summarise the Unclassified dataset
unclassed_dataset<-combined_dataset %>%
  filter(market_desc=="Unclassified")

table(unclassed_dataset$mark_in)

#total pounds
totals_unc<-unclassed_dataset %>%
  group_by(mark_in) %>%
  summarise(total_liv_mt=sum(livlb, na.rm=TRUE)/(1000*lbs_to_kg),
            valueR_CPI_M=sum(valueR_CPI, na.rm=TRUE)/1000000)



#total by year

by_year<-unclassed_dataset %>%
  group_by(year, mark_in) %>%
  summarise(total_liv_mt=sum(livlb, na.rm=TRUE)/(1000*lbs_to_kg),
            valueR_CPI_M=sum(valueR_CPI, na.rm=TRUE)/1000000) %>%
  ungroup() %>%
  group_by(year)%>%
  mutate(liv_mt=sum(total_liv_mt),
         val=sum(valueR_CPI_M)) %>%
  mutate(total_frac=total_liv_mt/liv_mt,
         val_frac=valueR_CPI_M/val) %>%
  ungroup() %>%
  select(-liv_mt, -val) %>%
  filter(mark_in==FALSE)

# are there any "only UNC dealers
# there are, but they're only a "problem" for prediction if they respond to market forces.

only_unc<-combined_dataset %>%
  count(dlrid, market_desc) %>%
  ungroup() %>%
  group_by(dlrid) %>%
  mutate(total=sum(n)) %>%
  filter(market_desc=="Unclassified", total==n)


only_unc_dlr<-only_unc %>%
  select(dlrid) %>%
  mutate(tagged_dlr=1)

only_u<-combined_dataset %>%
  mutate(tagged_dlr=0) %>%
  filter(market_desc=="Unclassified") %>%
  left_join(only_unc_dlr, by=join_by(dlrid))  %>%
  mutate(tagged_dlr = coalesce(tagged_dlr.y,tagged_dlr.x)) %>%
  select(-tagged_dlr.x,-tagged_dlr.y)

#7274 obs only sold by dealers that ever sell unclassifieds compared to 25,333
# that sell a mix of unclassifieds and classifieds.
  
  
table(only_u$tagged_dlr)
