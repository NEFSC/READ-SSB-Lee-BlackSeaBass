###############################################################################
# Purpose: 	Final Data preparation for stock assessment

# The original data prep included some landings that are not in the North or South stock
# They are in from the South Atlantic stock. It is appropriate to include them in the 
# training model (they are landed at similar dealers and are part of the 'market')
# However, we need to exclude them from the model-to-assessment pipeline. 

# This code does that by recoding the stockarea/stock_abbrev column


# Inputs:
#   - landings_cleaned_$date.dta (from wrappers)
#   - camsid_specific_cleaned_
#   - daily_ma
#   - state_ma
#   - stockarea_ma
#   - dlrid_historical_stats_


# Outputs:
#   - PRED_BSB_original_combined_dataset.Rds Classified transactions.  
#   - PRED_BSB_unclassified_dataset.Rds Unclassified Transactions. Use these to predict after estimating.

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
here::i_am("R_code/data_extraction_processing/processing/predictions_data_prep_for_stock_assessment.R")

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


cleaned_landings <- cleaned_landings %>%
  mutate(
    stock_abbrev = case_when(
      area >= 621 & area<=639 ~ "SOUTH",
      area %in% c(614, 615)   ~ "SOUTH",
      area %in% c(464,465,467,468,510,511,512,513,514,515) ~ "NORTH",
      area %in% c(520,521,522,523,524,525,526,530,533,534,537,538,539,541,542) ~ "NORTH",
      area %in% c(543,551,552,560,561,562,611,612,613,616)~ "NORTH",
      area==0 ~ "UNK",
      .default = "UNK"
    )
  )

cleaned_landings<-cleaned_landings %>%
  filter(stock_abbrev %in% c("NORTH","SOUTH"))

grand_moving_average_prices<-readRDS(here("data_folder","main","commercial", glue("grand_moving_average_prices_{vintage_string}.Rds")))
grand_moving_average_prices<-grand_moving_average_prices%>%
  mutate(.in_gma = 1L)
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

cleaned_landings <- cleaned_landings %>% 
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
# merge in dlrid historical statistics
cleaned_landings<-cleaned_landings %>%
  left_join(dlrid_historical, by=join_by(dlrid==dlrid), relationship="many-to-one")%>%
  mutate(
    .merge_dlrid = case_when(
      .in_original == 1L & is.na(.in_dlrid_historical) ~ 1L,
      is.na(.in_original) & .in_dlrid_historical == 1L ~ 2L,
      .in_original == 1L & .in_dlrid_historical == 1L ~ 3L,
    )
  )

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

# Keep  2013 to 2025 data
# deal with factors -- 
combined_dataset<-cleaned_landings %>%
    filter(year>=2013 & year<=2025) %>%
    mutate(market_desc=forcats::fct_relevel(market_desc,c("Jumbo","Large","Medium","Small","Unclassified")) ) %>%
    mutate(year=factor(year, levels=2013:2025, ordered=TRUE),
           month=factor(month, levels=1:12, ordered=FALSE), 
           semester=factor(semester, levels=1:2, ordered=FALSE), 
           dlrid=factor(dlrid, ordered=FALSE), 
           region=factor(region, ordered=FALSE), 
          market_desc=fct_drop(market_desc),
        year=fct_drop(year)
    ) 

# order the states.  I chose not to order the month and semester, because month12 of one year is next to month 1 of the following
# There's only 2 regions and 2 semesters, so no reason to order them.  
combined_dataset<-combined_dataset %>%
  mutate(state=forcats::fct_relevel(state,c("CN","ME","NH", "MA","RI","CT","NY","NJ","PA","DE","MD","VA","NC","SC")) ) %>%
							
								
									
  mutate(state=ordered(state)
  )

# Encode catch share
combined_dataset<-combined_dataset %>%
  mutate(catch_share=case_when(
    state %in% c("MD","VA","DE") ~ "CatchShare",
    .default="Non CatchShare")
  ) %>%
  mutate(catch_share=as.factor(catch_share))

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
         # Create an indicator if it is the first year that we see a dealer (and )

combined_dataset <- combined_dataset %>%
  mutate(first_dlr_year = if_all(c(LagSharePoundsJumbo, LagSharePoundsLarge,
                                   LagSharePoundsMedium,LagSharePoundsSmall), is.na))

write_rds(combined_dataset, file=here("data_folder","main","commercial",glue("PRED_BSB_original_combined_dataset{out_data_string}.Rds")))

  
# put the unclassifieds into a dataset
# KEEP all of the observations of unclassifieds, but we are only comfortable predicting for mark_in==1  
# We still will need to do something with these transactions, even if it's to keep them as unclassified
unclassified_dataset<-combined_dataset %>%
  filter(market_desc=="Unclassified") 

write_rds(unclassified_dataset, file=here("data_folder","main","commercial",glue("PRED_BSB_unclassified_dataset{out_data_string}.Rds")))


