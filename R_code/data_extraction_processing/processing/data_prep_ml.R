###############################################################################
# Purpose: 	Final Data preparation for Machine Learning Models
# Inputs:
#   - landings_cleaned_$date.dta (from wrappers)
#   - camsid_specific_cleaned_
#   - daily_ma
#   - state_ma
#   - stockarea_ma
#   - dlrid_historical_stats_


# Outputs:
#   - estimation_dataset.Rds Ready for estimation
#   - unclassified_dataset.Rds Unclassified Transactions. Use these to predict after estimating.

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
here::i_am("R_code/data_extraction_processing/processing/data_prep_ml.R")

#traverse over to the DataPull repository
mega_dir<-dirname(here::here())
data_pull_dir<-file.path(mega_dir,"READ-SSB-Lee-BSB-DataPull")


my_images<-here("images")
descriptive_images<-here("images","descriptive")
exploratory_images<-here("images","exploratory")
vintage_string<-list.files(here("data_folder","main","commercial"), pattern=glob2rx("landings_cleaned_*.Rds"))
vintage_string<-gsub("landings_cleaned_","",vintage_string)
vintage_string<-gsub(".Rds","",vintage_string)
vintage_string<-max(vintage_string)

lbs_per_mt<-2204.62

out_data_string<-Sys.Date()



###############################################################################
# Read in Data
###############################################################################
#Read in the cleaned data, and the mini-aggregates that contain
#1. Daily landings at the market category level
#2. Daily landings at the state and market category level
#3. Daily landings at the stockarea and market category level 
#4.  Historical "target encoding" based on 2010-2014 purchases for the dealers AND 1 year lags of dealer purchases.

cleaned_landings<-readRDS(here("data_folder","main","commercial", glue("landings_cleaned_{vintage_string}.Rds")))
#cams_gears<-haven::read_dta(here("data_folder","main","commercial", glue("cams_gears_{vintage_string}.dta")))

camsid_specific_stats<-readRDS(here("data_folder","main","commercial", glue("camsid_specific_cleaned_{vintage_string}.Rds")))

daily_ma<-readRDS(here("data_folder","main","commercial", glue("daily_ma_{vintage_string}.Rds")))

state_ma<-readRDS(here("data_folder","main","commercial", glue("state_ma_{vintage_string}.Rds")))

gear_ma<-readRDS(here("data_folder","main","commercial", glue("gear_ma_{vintage_string}.Rds")))


stockarea_ma<-readRDS(here("data_folder","main","commercial", glue("stockarea_ma_{vintage_string}.Rds")))

dlrid_historical<-readRDS(here("data_folder","main","commercial", glue("dlrid_historical_stats_{vintage_string}.Rds")))
dlrid_lag<-readRDS(here("data_folder","main","commercial", glue("dlrid_lag_stats_{vintage_string}.Rds")))

grand_moving_average_prices<-readRDS(here("data_folder","main","commercial", glue("grand_moving_average_prices_{vintage_string}.Rds")))


###############################################################################
# mimics the stata data cleaning that I did for the multinomial logit.
###############################################################################

# this is the "collapse" statement in stata. Not sure but I think some of the things in the group_by() might need to be a "first" in the summarise
cleaned_landings<-cleaned_landings %>%
  group_by(camsid,hullid, permit, mygear, record_sail, record_land, dlr_date, dlrid, state, grade_desc, market_desc, dateq, year, month, stockarea, status) %>%
  summarise(value=sum(value),
            valueR_CPI=sum(valueR_CPI),
           lndlb=sum(lndlb),
           livlb=sum(livlb),
           weighting=sum(weighting)
  ) %>%
  ungroup()

# South - Delaware, Florida*, Maryland, North Carolina, South Carolina*, Virginia
# North - Connecticut, Maine*, Massachusetts, New Hampshire*, New Jersey, New York, Pennsylvania*, Rhode Island, Vermont*, Canada*
# * have no landings or limited landings are are dropped later.

cleaned_landings<-cleaned_landings %>% 
  mutate(region=case_when(
    state %in% c("CT","ME", "MA", "NH", "NJ", "NY", "PA", "RI", "VT", "CN") ~ "North",
    state %in% c("DE", "FL", "MD", "NC", "SC", "VA")  ~ "South",
    .default = "Unknown"  )
  )
  



# merge in camsid (trip) level statistics
cleaned_landings<-cleaned_landings %>%
  left_join(camsid_specific_stats, by=join_by(camsid==camsid, dlr_date==dlr_date), relationship="many-to-one")

# merge in daily level statistics
cleaned_landings<-cleaned_landings %>%
  left_join(daily_ma, by=join_by(dlr_date==dlr_date), relationship="many-to-one")

# merge in state-day statistics
cleaned_landings<-cleaned_landings %>%
  left_join(state_ma, by=join_by(state==state, dlr_date==dlr_date), relationship="many-to-one")

# merge in stockarea-day statistics
cleaned_landings<-cleaned_landings %>%
  left_join(stockarea_ma, by=join_by(stockarea==stockarea, dlr_date==dlr_date), relationship="many-to-one")

# merge in gear-day statistics
cleaned_landings<-cleaned_landings %>%
  left_join(gear_ma, by=join_by(mygear==mygear, dlr_date==dlr_date), relationship="many-to-one")


# merge in dlrid historical statistics
cleaned_landings<-cleaned_landings %>%
  left_join(dlrid_historical, by=join_by(dlrid==dlrid), relationship="many-to-one")


# merge in dlrid lag statistics
cleaned_landings<-cleaned_landings %>%
  left_join(dlrid_lag, by=join_by(dlrid==dlrid,year==year), relationship="many-to-one")



# merge in moving_average_prices  statistics
cleaned_landings<-cleaned_landings %>%
  left_join(grand_moving_average_prices, by=join_by(state==state, dlr_date==dlr_date), relationship="many-to-one")





# NAs for Transaction count and lndlb can be replaced by zero.
# cleaned_landings<-cleaned_landings %>%
#   mutate(TransactionCountJumbo=replace_na(TransactionCountJumbo),
#          TransactionCountLarge=replace_na(TransactionCountLarge),
#          TransactionCountMedium=replace_na(TransactionCountMedium),
#          TransactionCountSmall=replace_na(TransactionCountSmall),
#          TransactionCountUnclassified=replace_na(TransactionCountUnclassified)
#   )
# 
# cleaned_landings<-cleaned_landings %>%
#   mutate(DealerHLbsPurchasedJumbo=replace_na(DealerHLbsPurchasedJumbo),
#          DealerHLbsPurchasedLarge=replace_na(DealerHLbsPurchasedLarge),
#          DealerHLbsPurchasedMedium=replace_na(DealerHLbsPurchasedMedium),
#          DealerHLbsPurchasedSmall=replace_na(DealerHLbsPurchasedSmall),
#          DealerHLbsPurchasedUnclassified=replace_na(DealerHLbsPurchasedUnclassified)
#   )

# compute prices and real prices
cleaned_landings<-cleaned_landings %>%
  mutate(price=value/lndlb,
         priceR_CPI=valueR_CPI/lndlb,
         month=lubridate::month(dlr_date))

# trip level BSB landings
cleaned_landings<-cleaned_landings %>%
  group_by(camsid) %>%
  mutate(trip_level_BSB=sum(lndlb)) %>%
    ungroup()

# Encode semester
cleaned_landings<-cleaned_landings %>%
  mutate(semester=case_when(
      month<=6  ~ 1,
      month>=7  ~ 2,
      .default=0)
      ) 


cleaned_landings<-cleaned_landings %>%
  mutate(Price_Diff_J=priceR_CPI-JumboMA14price,
         Price_Diff_L=priceR_CPI-LargeMA14price,
         Price_Diff_M=priceR_CPI-MediumMA14price,
         Price_Diff_S=priceR_CPI-SmallMA14price)



#Use the variable labels to convert to factors 

cleaned_landings<-cleaned_landings %>%
  mutate(market_desc=fct_drop(market_desc),
         mygear=fct_drop(mygear),
         state=fct_drop(state),
         grade_desc=fct_drop(grade_desc),
         stockarea=fct_drop(stockarea)
         )

#Factor the cams status column
cleaned_landings<-cleaned_landings %>%
  mutate(status=factor(status,levels=c("MATCH","DLR_ORPHAN_SPECIES","DLR_ORPHAN_TRIP","PZERO"))
  )

# Construct shore and nofederal
cleaned_landings<-cleaned_landings %>%
  mutate(shore=as.integer(hullid=="FROM_SHORE"),
         nofederal=as.integer(str_detect(camsid, "^000000*"))
)

# convert landed pounds and trip_level_BSB to integer
cleaned_landings<-cleaned_landings %>%
  mutate(lndlb=as.integer(lndlb),
         trip_level_BSB=as.integer(trip_level_BSB))

cleaned_landings<-cleaned_landings %>%
  mutate(StockareaOtherQJumbo=as.integer(StockareaOtherQJumbo),
         StockareaOtherQLarge=as.integer(StockareaOtherQLarge),
         StockareaOtherQMedium=as.integer(StockareaOtherQMedium),
         StockareaOtherQSmall=as.integer(StockareaOtherQSmall)
  )
cleaned_landings<-cleaned_landings %>%
  mutate(StateOtherQJumbo=as.integer(StateOtherQJumbo),
         StateOtherQLarge=as.integer(StateOtherQLarge),
         StateOtherQMedium=as.integer(StateOtherQMedium),
         StateOtherQSmall=as.integer(StateOtherQSmall)
  )


# 

###############################################################################
# Final Tidyup
###############################################################################

# Keep  2013 to 2024 data
# deal with factors
combined_dataset<-cleaned_landings %>%
    filter(year>=2013 & year<=2024) %>%
    mutate(market_desc=forcats::fct_relevel(market_desc,c("Jumbo","Large","Medium","Small","Unclassified")) ) %>%
    mutate(year=forcats::as_factor(year)) %>%
    mutate(month=forcats::as_factor(month)) %>%
    mutate(semester=forcats::as_factor(semester)) %>%
    mutate(dlrid=forcats::as_factor(dlrid)) %>%
    mutate(region=forcats::as_factor(region)) %>%
    mutate(market_desc=fct_drop(market_desc),
        year=fct_drop(year)) 

# order the years and states. I'm also ordering the . I chose not to order the months, because month12 of one year is next to month 1 of the following
combined_dataset<-combined_dataset %>%
  mutate(state=forcats::fct_relevel(state,c("CN","ME","NH", "MA","RI","CT","NY","NJ","PA","DE","MD","VA","NC","SC")) ) %>%
  mutate(year=ordered(year),
         region=ordered(region),
         semester=ordered(semester),
         state=ordered(state)
  )

# Encode catch share
combined_dataset<-combined_dataset %>%
  mutate(catch_share=case_when(
    state %in% c("MD","VA","DE") ~ "CatchShare",
    .default="Non CatchShare")
  ) %>%
  mutate(catch_share=ordered(as.factor(catch_share)))

# generate a compact group id variable to take the place of camsid, market_desc, dlrid
combined_dataset<-combined_dataset %>%
  arrange(camsid,dlrid, market_desc)%>%
  group_by(camsid,dlrid, market_desc)%>%
  mutate(myl_id=cur_group_id()) %>%
  ungroup()

combined_dataset<-combined_dataset %>%
  mutate(myl_id=as.integer(myl_id))








# Flag dlrid's that have suspiciously little variance in prices.
dlr_variability <- combined_dataset %>%
  mutate(price=value/lndlb) %>%
  group_by(dlrid, year, market_desc ) %>%
  summarise(transactions=n(),
            value=sum(value, na.rm=TRUE),
            lndlb=sum(lndlb),
            mean_price=mean(price, na.rm=TRUE),
            sd_price=sd(price, na.rm=TRUE),
            mad_price=mad(price, na.rm=TRUE)
  )%>%
  mutate(cv=sd_price/mean_price) %>%
  arrange(sd_price)

mark_in<-dlr_variability %>%
  mutate(mark_in=case_when(
    sd_price>=0.1 ~ 1,
    .default = 0
  )
  ) %>%
  select(dlrid,year,market_desc, mark_in)


combined_dataset<-combined_dataset %>%
  left_join(mark_in, by=join_by(dlrid==dlrid, year==year, market_desc==market_desc)) %>%
  ungroup()


# Flag observaions with bad prices, bad pricing data, or from wierd states. 
combined_dataset<-combined_dataset %>%
  mutate(mark_in=case_when(
              price<0.15 ~ 0,
              price>12 ~ 0,
              is.na(price) ~ 0,
              state =="CN"  ~ 0,
              state =="FL"  ~ 0, 
              state =="PA"  ~ 0,
              state =="SC"  ~ 0,
              .default=mark_in)
)

write_rds(combined_dataset, file=here("data_folder","main","commercial",glue("BSB_original_combined_dataset{out_data_string}.Rds")))
haven::write_dta(combined_dataset, path=here("data_folder","main","commercial",glue("BSB_original_combined_dataset{out_data_string}.dta")))

  
# put the unclassifieds into a dataset
# KEEP all of the observations of unclassifieds, but we are only comfortable predicting for mark_in==1  
# We still will need to do something with these transactions, even if it's to keep them as unclassified
unclassified_dataset<-combined_dataset %>%
  filter(market_desc=="Unclassified") 

write_rds(unclassified_dataset, file=here("data_folder","main","commercial",glue("BSB_unclassified_dataset{out_data_string}.Rds")))
haven::write_dta(unclassified_dataset, path=here("data_folder","main","commercial",glue("BSB_unclassified_dataset{out_data_string}.dta")))

# put everything else in a dataset
# discard the observations with mark_in=0 ( dealers with minimal variance, low prices
estimation_dataset<-combined_dataset %>%
  filter(market_desc!="Unclassified") %>%
  filter(mark_in==1) %>%
  select(-c("mark_in"))

write_rds(estimation_dataset, file=here("data_folder","main","commercial",glue("BSB_estimation_dataset{out_data_string}.Rds")))
haven::write_dta(estimation_dataset, path=here("data_folder","main","commercial",glue("BSB_estimation_dataset{out_data_string}.dta")))


