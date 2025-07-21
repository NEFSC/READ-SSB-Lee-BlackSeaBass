###############################################################################
# Purpose: 	Code to construct an "aggregation key table" for the market categories 

# if a market_cat_aggregations datafile does not exist, this will read in "all_marketcategory_landings_", keep the unique
# itis, market category, and market category description, and create a "category_combined" column that indicates which orginal market categories should be aggregated together. 
# if a market_cat_aggregations datafile exists, this will modify the "category_combined" column


# Inputs:
#  - market_cat_aggregations OR all_marketcategory_landings_
# Outputs:
#  - market_cat_aggregations

###############################################################################  
# 
# The stock assessments aggregate certain species together. 

library("glue")
library("tidyverse")
library("forcats")
library("here")
library("ROracle")

#directories
here::i_am("R_code/analysis/market_category_aggregations.R")

#traverse over to the DataPull repository
mega_dir<-dirname(here::here())
data_pull_dir<-file.path(mega_dir,"READ-SSB-Lee-BSB-DataPull")


##which data to read in
#today
#vintage_string<-format(Sys.Date())
#specific vintage
vintage_string<-"2025-07-10"

# most recent 
# (not coded)

# There is no point in looking at scallop, surfclam, or ocean quahog.



# This takes a long time to read in, so if you already have a market_cat_aggregations, it's better to work on that 
agg_exists<-file.exists(here("data_folder","main","commercial",glue("market_cat_aggregations_{vintage_string}.Rds")))

if(agg_exists==FALSE){

landings<-readRDS(file=file.path(data_pull_dir,"data_folder","raw","commercial",glue("all_marketcategory_landings_{vintage_string}.Rds")))

market_cat_aggregations<-landings %>%
    filter(!itis_tsn %in% c("079718", "080944","081343")) %>%
  group_by(itis_tsn, dlr_mkt, market_desc) %>%
  slice(1) %>%
  ungroup()%>%
  select(c(itis_tsn, itis_sci_name, dlr_mkt, market_desc))%>%
  arrange(itis_tsn,dlr_mkt,market_desc)
           
} else if(agg_exists==TRUE){
  market_cat_aggregations<- readRDS(file=here("data_folder","main","commercial",glue("market_cat_aggregations_{vintage_string}.Rds")))
}

market_cat_aggregations<-market_cat_aggregations %>%
  mutate(category_combined=case_when(
    itis_tsn==164712 & dlr_mkt %in% c("LG","ST","WH") ~ "LG", #COD large: Large, whale, steaker
    itis_tsn==164712 & (dlr_mkt %in% c("UN","MX")| is.na(dlr_mkt)) ~ "UN", #COD Unclassifed includes Mixed, and NA
    itis_tsn==164712 & dlr_mkt %in% c("SK","X1","X2","X3","SR") ~ "SK", #COD Scrod includes terminals and snappers
    itis_tsn==167687 & dlr_mkt %in% c("JB","XG") ~ "JB",  # BSB Jumbo includes Extra Large 
    itis_tsn==167687 & (dlr_mkt %in% c("UN","MX")| is.na(dlr_mkt)) ~ "UN", # BSB Unclassified includes Mixed and NA
    itis_tsn==167687 & dlr_mkt %in% c("PW","SQ","ES") ~ "SQ", # BSB Small includes PeeWee and Extra Small
    .default=dlr_mkt)
  ) %>%
  group_by(itis_tsn, category_combined) %>%
  arrange(itis_tsn,category_combined,market_desc)


saveRDS(market_cat_aggregations, file=here("data_folder","main","commercial",glue("market_cat_aggregations_{vintage_string}.Rds")))
