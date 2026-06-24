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
here::i_am("R_code/data_extraction_processing/processing/commercial/B01_data_prep_ml.R")

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
# 
# cleaned_landings<-read_dta(here("data_folder","main","commercial", glue("landings_cleaned_{vintage_string}.dta")))
# #cams_gears<-haven::read_dta(here("data_folder","main","commercial", glue("cams_gears_{vintage_string}.dta")))
# 
# camsid_specific_stats<-read_dta(here("data_folder","main","commercial", glue("camsid_specific_cleaned_",vintage_string,".dta")))
# 
# daily_ma<-read_dta(here("data_folder","main","commercial", glue("daily_ma_{vintage_string}.dta")))
# 
# state_ma<-read_dta(here("data_folder","main","commercial", glue("state_ma_{vintage_string}.dta")))
# 
# gear_ma<-read_dta(here("data_folder","main","commercial", glue("gear_ma_{vintage_string}.dta")))
# 
# 
# stockarea_ma<-read_dta(here("data_folder","main","commercial", glue("stockarea_ma_{vintage_string}.dta")))
# 
# dlrid_historical<-read_dta(here("data_folder","main","commercial", glue("dlrid_historical_stats_{vintage_string}.dta")))
# dlrid_lag<-read_dta(here("data_folder","main","commercial", glue("dlrid_lag_stats_{vintage_string}.dta")))
# 
# grand_moving_average_prices<-read_dta(here("data_folder","main","commercial", glue("grand_moving_average_prices_{vintage_string}.dta")))
# 


cleaned_landings<-readRDS(here("data_folder","main","commercial", glue("landings_cleaned_{vintage_string}.Rds"))) 


#cams_gears<-haven::read_dta(here("data_folder","main","commercial", glue("cams_gears_{vintage_string}.dta")))

camsid_specific_stats<-readRDS(here("data_folder","main","commercial", glue("camsid_specific_cleaned_{vintage_string}.Rds")))
camsid_specific_stats<-camsid_specific_stats%>%
  mutate(.in_camsid = 1L)

daily_ma<-readRDS(here("data_folder","main","commercial", glue("daily_ma_{vintage_string}.Rds")))
daily_ma<-daily_ma%>%
  mutate(.in_dailyma = 1L)

state_ma<-readRDS(here("data_folder","main","commercial", glue("state_ma_{vintage_string}.Rds")))
state_ma<-state_ma%>%
  mutate(.in_state_ma = 1L)

gear_ma<-readRDS(here("data_folder","main","commercial", glue("gear_ma_{vintage_string}.Rds")))
gear_ma<-gear_ma%>%
  mutate(.in_gear_ma = 1L)


stockarea_ma<-readRDS(here("data_folder","main","commercial", glue("stockarea_ma_{vintage_string}.Rds")))
stockarea_ma<-stockarea_ma%>%
  mutate(.in_stockarea_ma = 1L)

dlrid_historical<-readRDS(here("data_folder","main","commercial", glue("dlrid_historical_stats_{vintage_string}.Rds")))
dlrid_historical<-dlrid_historical%>%
  mutate(.in_dlrid_historical = 1L)


dlrid_lag<-readRDS(here("data_folder","main","commercial", glue("dlrid_lag_stats_{vintage_string}.Rds")))
dlrid_lag<-dlrid_lag%>%
  mutate(.in_dlrid_lag = 1L)

grand_moving_average_prices<-readRDS(here("data_folder","main","commercial", glue("grand_moving_average_prices_{vintage_string}.Rds")))
grand_moving_average_prices<-grand_moving_average_prices%>%
  mutate(.in_gma = 1L)

###############################################################################
# mimics the stata data cleaning that I did for the multinomial logit.
###############################################################################

cleaned_landings<-cleaned_landings %>%
  mutate(flag_in=!is.na(valueR_CPI))


# this is the "collapse" statement in stata. Not sure but I think some of the things in the group_by() might need to be a "first" in the summarise
cleaned_landings<-cleaned_landings %>%
  ungroup() %>%
  group_by(camsid,hullid, permit, mygear, record_sail, record_land, dlr_date, dlrid, state, grade_desc, market_desc, dateq, year, month, stockarea, stock_abbrev, status, flag_in) %>%
  summarise(value=sum(value),
           valueR_CPI=sum(valueR_CPI),
           lndlb=sum(lndlb),
           livlb=sum(livlb),
           weighting=sum(weighting),
           .groups="drop"
  )

# South - Delaware, Florida*, Maryland, North Carolina, South Carolina*, Virginia
# North - Connecticut, Maine*, Massachusetts, New Hampshire*, New Jersey, New York, Pennsylvania*, Rhode Island, Vermont*, Canada*
# * have no landings or limited landings are are dropped later.
# this is like a north-south market category region. Similar to the STOCK_ABBREV, although that is based on stat area
cleaned_landings<-cleaned_landings %>% 
  mutate(region=case_when(
    state %in% c("CT","ME", "MA", "NH", "NJ", "NY", "PA", "RI", "VT", "CN") ~ "North",
    state %in% c("DE", "FL", "MD", "NC", "SC", "VA")  ~ "South",
    .default = "Unknown"  )
  )
# create an indicator variable
cleaned_landings  <- cleaned_landings  %>%
   mutate(.in_original  = 1L)


# merge in camsid (trip) level statistics
cleaned_landings<-cleaned_landings %>%
  left_join(camsid_specific_stats, by=join_by(camsid==camsid, dlr_date==dlr_date), relationship="many-to-one") %>%
  mutate(
    .merge = case_when(
      .in_original == 1L & is.na(.in_camsid) ~ 1L,
      is.na(.in_original) & .in_camsid == 1L ~ 2L,
      .in_original == 1L & .in_camsid == 1L ~ 3L,
    )
)
#verify merge worked, stop if it didnt. Cleanup if it did
stopifnot(all(cleaned_landings$.merge == 3L))
cleaned_landings<-cleaned_landings %>%
  select(-c(.in_camsid,.merge))


# merge in daily level statistics
cleaned_landings<-cleaned_landings %>%
  left_join(daily_ma, by=join_by(dlr_date==dlr_date), relationship="many-to-one")%>%
  mutate(
    .merge = case_when(
      .in_original == 1L & is.na(.in_dailyma) ~ 1L,
      is.na(.in_original) & .in_dailyma == 1L ~ 2L,
      .in_original == 1L & .in_dailyma == 1L ~ 3L,
    )
  )
#verify merge worked, stop if it didnt. Cleanup if it did
stopifnot(all(cleaned_landings$.merge == 3L))
cleaned_landings<-cleaned_landings %>%
  select(-c(.in_dailyma,.merge))


# merge in state-day statistics
cleaned_landings<-cleaned_landings %>%
  left_join(state_ma, by=join_by(state==state, dlr_date==dlr_date), relationship="many-to-one")%>%
  mutate(
    .merge = case_when(
      .in_original == 1L & is.na(.in_state_ma) ~ 1L,
      is.na(.in_original) & .in_state_ma == 1L ~ 2L,
      .in_original == 1L & .in_state_ma == 1L ~ 3L,
    )
  )
#verify merge worked, stop if it didnt. Cleanup if it did
stopifnot(all(cleaned_landings$.merge == 3L))
cleaned_landings<-cleaned_landings %>%
  select(-c(.in_state_ma,.merge))


# merge in stockarea-day statistics
cleaned_landings<-cleaned_landings %>%
  left_join(stockarea_ma, by=join_by(stockarea==stockarea, dlr_date==dlr_date), relationship="many-to-one")%>%
  mutate(
    .merge = case_when(
      .in_original == 1L & is.na(.in_stockarea_ma) ~ 1L,
      is.na(.in_original) & .in_stockarea_ma == 1L ~ 2L,
      .in_original == 1L & .in_stockarea_ma == 1L ~ 3L,
    )
  )
#verify merge worked, stop if it didnt. Cleanup if it did
stopifnot(all(cleaned_landings$.merge == 3L))
cleaned_landings<-cleaned_landings %>%
  select(-c(.in_stockarea_ma,.merge))


# merge in gear-day statistics
cleaned_landings<-cleaned_landings %>%
  left_join(gear_ma, by=join_by(mygear==mygear, dlr_date==dlr_date), relationship="many-to-one")%>%
  mutate(
    .merge = case_when(
      .in_original == 1L & is.na(.in_gear_ma) ~ 1L,
      is.na(.in_original) & .in_gear_ma == 1L ~ 2L,
      .in_original == 1L & .in_gear_ma == 1L ~ 3L,
    )
  )
#verify merge worked, stop if it didnt. Cleanup if it did
stopifnot(all(cleaned_landings$.merge == 3L))
cleaned_landings<-cleaned_landings %>%
  select(-c(.in_gear_ma,.merge))

################################################################################
############# Not all dealers had "historical landings"#########################
################################################################################

################################################################################
############# Not all dealers had landings in the previous year ################
################################################################################

# merge in dlrid lag statistics
cleaned_landings<-cleaned_landings %>%
  left_join(dlrid_lag, by=join_by(dlrid==dlrid,year==year), relationship="many-to-one")%>%
  mutate(
    .merge_dlr_lags = case_when(
      .in_original == 1L & is.na(.in_dlrid_lag) ~ 1L,
      is.na(.in_original) & .in_dlrid_lag == 1L ~ 2L,
      .in_original == 1L & .in_dlrid_lag == 1L ~ 3L,
    )
  )




# merge in moving_average_prices  statistics
cleaned_landings<-cleaned_landings %>%
  left_join(grand_moving_average_prices, by=join_by(state==state, dlr_date==dlr_date), relationship="many-to-one")%>%
  mutate(
    .merge = case_when(
      .in_original == 1L & is.na(.in_gma) ~ 1L,
      is.na(.in_original) & .in_gma == 1L ~ 2L,
      .in_original == 1L & .in_gma == 1L ~ 3L,
    )
  )
# there's a handful of 1996 records hanging around here.  
cleaned_landings<-cleaned_landings %>%
  filter(year>1997)


#verify merge worked, stop if it didnt. Cleanup if it did
stopifnot(all(cleaned_landings$.merge == 3L))
cleaned_landings<-cleaned_landings %>%
  select(-c(.in_gma,.merge))


cleaned_landings<-cleaned_landings %>%
  select(-c(.in_dlrid_historical, .merge_dlrid, .in_dlrid_lag, .merge_dlr_lags, .in_original))



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
  group_by(camsid, flag_in) %>%
  mutate(trip_level_BSB=sum(lndlb)) %>%
    ungroup()

# Encode semester
cleaned_landings<-cleaned_landings %>%
  mutate(semester=case_when(
      month<=6  ~ 1,
      month>=7  ~ 2,
      .default=0)
      ) 




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


# generate a compact group id variable to take the place of camsid, market_desc, dlrid
combined_dataset<-combined_dataset %>%
  arrange(camsid,dlrid, market_desc, flag_in)%>%
  group_by(camsid,dlrid, market_desc, flag_in)%>%
  mutate(myl_id=cur_group_id()) %>%
  ungroup()

combined_dataset<-combined_dataset %>%
  mutate(myl_id=as.integer(myl_id))


# Flag dlrid's that have suspiciously little variance in prices.
dlr_variability <- combined_dataset %>%
  filter(flag_in==TRUE)%>%
  mutate(price=value/lndlb) %>%
  group_by(dlrid, year, market_desc ) %>%
  summarise(transactions=n(),
            value=sum(value, na.rm=TRUE),
            lndlb=sum(lndlb),
            mean_price=mean(price, na.rm=TRUE),
            sd_price=sd(price, na.rm=TRUE),
            mad_price=mad(price, na.rm=TRUE),
            .groups="drop"
  )%>%
  mutate(cv=sd_price/mean_price) %>%
  arrange(sd_price)

mark_in<-dlr_variability %>%
  mutate(mark_in=case_when(
    sd_price>=0.1 ~ TRUE,
    .default = FALSE
  )
  ) %>%
  select(dlrid,year,market_desc, mark_in)


combined_dataset<-combined_dataset %>%
  left_join(mark_in, by=join_by(dlrid==dlrid, year==year, market_desc==market_desc)) %>%
  ungroup()


# Flag observaions with bad prices, bad pricing data, or from weird states.
# this dataframe has "everything" EXCEPT records that were flagged as "questionable status" in the "A01_landings_cleaned.R"
# To predict
combined_dataset<-combined_dataset %>%
  mutate(mark_in=case_when(
              price<0.15 ~ FALSE,
              price>12 ~ FALSE,
              is.na(price) ~ FALSE,
              state =="CN"  ~ FALSE,
              state =="FL"  ~ FALSE, 
              state =="PA"  ~ FALSE,
              state =="SC"  ~ FALSE,
              flag_in ==FALSE  ~ FALSE,
              .default=mark_in)
)

combined_dataset<-combined_dataset %>%
  rename(STOCK_ABBREV=stock_abbrev)


# Create an indicator if it is the first year that we see a dealer (and )

combined_dataset <- combined_dataset %>%
  mutate(first_dlr_year = if_all(c(LagSharePoundsJumbo, LagSharePoundsLarge,
                                   LagSharePoundsMedium,LagSharePoundsSmall), is.na))

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
  select(-c("mark_in", "flag_in"))

write_rds(estimation_dataset, file=here("data_folder","main","commercial",glue("BSB_estimation_dataset{out_data_string}.Rds")))
haven::write_dta(estimation_dataset, path=here("data_folder","main","commercial",glue("BSB_estimation_dataset{out_data_string}.dta")))


