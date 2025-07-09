# Code to construct an "aggregation key table" for the market categories
# The stock assessments aggregate certain species together. 

library("glue")
library("tidyverse")
library("forcats")
library("here")
library("ROracle")

here::i_am("R_code/analysis/market_category_aggregations.R")

#vintage_string<-format(Sys.Date())
vintage_string<-"2025-06-18"

#There is no point in looking at scallop, surfclam, or ocean quahog.

market_cat_aggregations<-landings %>%
    filter(!itis_tsn %in% c("079718", "080944","081343")) %>%
  group_by(itis_tsn, dlr_mkt, market_desc) %>%
  slice(1) %>%
  ungroup()%>%
  select(c(itis_tsn, itis_sci_name, dlr_mkt, market_desc))%>%
  arrange(itis_tsn,dlr_mkt,market_desc)
           
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




saveRDS(market_cat_aggregations, file=here("data_folder","main",glue("market_cat_aggregations_{vintage_string}.Rds")))


