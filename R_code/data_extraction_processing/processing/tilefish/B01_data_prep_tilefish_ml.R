###############################################################################
# Purpose: 	Final Data preparation for Machine Learning Models
# Inputs:
#   - landings_cleaned_$date.dta (from wrappers)
#   - camsid_specific_cleaned_
#   - daily_ma
#   - state_ma


# Outputs:
#   - estimation_dataset.Rds Ready for estimation
#   - unclassified_dataset.Rds Unclassified Transactions. Use these to predict after estimating.

###############################################################################
# Packages 
###############################################################################


my_images<-here("images")
descriptive_images<-here("images","descriptive")
exploratory_images<-here("images","exploratory")
vintage_string<-list.files(here("data_folder","main","tilefish"), pattern=glob2rx("tilefish_landings_cleaned_*.Rds"))
vintage_string<-gsub("tilefish_landings_cleaned_","",vintage_string)
vintage_string<-gsub(".Rds","",vintage_string)
vintage_string<-max(vintage_string)

lbs_per_mt<-2204.62

out_data_string<-Sys.Date()



###############################################################################
# Read in Data
###############################################################################
#Read in the cleaned data, and the mini-aggregates that contain

cleaned_landings<-readRDS(here("data_folder","main","tilefish", glue("tilefish_landings_cleaned_{vintage_string}.Rds"))) 


#cams_gears<-haven::read_dta(here("data_folder","main","commercial", glue("cams_gears_{vintage_string}.dta")))

camsid_specific_stats<-readRDS(here("data_folder","main","tilefish", glue("camsid_tilefish_specific_cleaned_{vintage_string}.Rds")))
camsid_specific_stats<-camsid_specific_stats%>%
  mutate(.in_camsid = 1L)

daily_ma<-readRDS(here("data_folder","main","tilefish", glue("daily_tilefish_ma_{vintage_string}.Rds")))
daily_ma<-daily_ma%>%
  mutate(.in_dailyma = 1L)

state_ma<-readRDS(here("data_folder","main","tilefish", glue("state_tilefish_ma_{vintage_string}.Rds")))
state_ma<-state_ma%>%
  mutate(.in_state_ma = 1L)

gear_ma<-readRDS(here("data_folder","main","tilefish", glue("gear_tilefish_ma_{vintage_string}.Rds")))
gear_ma<-gear_ma%>%
  mutate(.in_gear_ma = 1L)


dlrid_lag<-readRDS(here("data_folder","main","tilefish", glue("dlrid_tile_lag_stats_{vintage_string}.Rds")))
dlrid_lag<-dlrid_lag%>%
  mutate(.in_dlrid_lag = 1L)

#grand_moving_average_prices<-readRDS(here("data_folder","main","tilefish", glue("grand_moving_average_prices_{vintage_string}.Rds")))
#grand_moving_average_prices<-grand_moving_average_prices%>%
#  mutate(.in_gma = 1L)

###############################################################################
# mimics the stata data cleaning that I did for the multinomial logit.
###############################################################################

cleaned_landings<-cleaned_landings %>%
  mutate(flag_in=!is.na(valueR_CPI))


# this is the "collapse" statement in stata. Not sure but I think some of the things in the group_by() might need to be a "first" in the summarise
cleaned_landings<-cleaned_landings %>%
  ungroup() %>%
  group_by(camsid,hullid, permit, mygear, record_sail, record_land, dlr_date, dlrid, state, grade_desc, market_desc, dateq, year, month, status, flag_in) %>%
  summarise(value=sum(value),
           valueR_CPI=sum(valueR_CPI),
           lndlb=sum(lndlb),
           livlb=sum(livlb),
           weighting=sum(weighting),
           .groups="drop"
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
# cleaned_landings<-cleaned_landings %>%
#   left_join(grand_moving_average_prices, by=join_by(state==state, dlr_date==dlr_date), relationship="many-to-one")%>%
#   mutate(
#     .merge = case_when(
#       .in_original == 1L & is.na(.in_gma) ~ 1L,
#       is.na(.in_original) & .in_gma == 1L ~ 2L,
#       .in_original == 1L & .in_gma == 1L ~ 3L,
#     )
#   )
# there's a handful of 1996 records hanging around here.  
cleaned_landings<-cleaned_landings %>%
  filter(year>1997)


#verify merge worked, stop if it didnt. Cleanup if it did
# stopifnot(all(cleaned_landings$.merge == 3L))
# cleaned_landings<-cleaned_landings %>%
#   select(-c(.in_gma,.merge))


cleaned_landings<-cleaned_landings %>%
  select(-c(.in_dlrid_lag, .merge_dlr_lags, .in_original))


# compute prices and real prices
cleaned_landings<-cleaned_landings %>%
  mutate(price=value/lndlb,
         priceR_CPI=valueR_CPI/lndlb,
         month=lubridate::month(dlr_date))

# trip level tilefish landings
cleaned_landings<-cleaned_landings %>%
  group_by(camsid, flag_in) %>%
  mutate(trip_level_tile=sum(lndlb)) %>%
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
         grade_desc=fct_drop(grade_desc)
         )

#Factor the cams status column
cleaned_landings<-cleaned_landings %>%
  mutate(status=factor(status,levels=c("MATCH","DLR_ORPHAN_SPECIES","DLR_ORPHAN_TRIP","PZERO"))
  )

# Construct nofederal
cleaned_landings<-cleaned_landings %>%
  mutate(nofederal=as.integer(str_detect(camsid, "^000000*"))
)

# convert landed pounds and trip_level_tile to integer
cleaned_landings<-cleaned_landings %>%
  mutate(lndlb=as.integer(lndlb),
         trip_level_tile=as.integer(trip_level_tile))

cleaned_landings<-cleaned_landings %>%
  mutate(across(starts_with("StateOtherQ"), as.integer)
      )

# 

###############################################################################
# Final Tidyup
###############################################################################


# generate a compact group id variable to take the place of camsid, market_desc, dlrid
combined_dataset<-cleaned_landings %>%
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
              price>30 ~ FALSE,
              is.na(price) ~ FALSE,
              state =="CN"  ~ FALSE,
              state =="FL"  ~ FALSE, 
              state =="PA"  ~ FALSE,
              state =="SC"  ~ FALSE,
              flag_in ==FALSE  ~ FALSE,
              .default=mark_in)
)



# Create an indicator if it is the first year that we see a dealer

combined_dataset <- combined_dataset %>%
  mutate(first_dlr_year = if_all(starts_with("LagSharePounds"), is.na))

write_rds(combined_dataset, file=here("data_folder","main","tilefish",glue("tilefish_original_combined_dataset{out_data_string}.Rds")))

  
# put the unclassifieds into a dataset
# KEEP all of the observations of unclassifieds, but we are only comfortable predicting for mark_in==1  
# We still will need to do something with these transactions, even if it's to keep them as unclassified
unclassified_dataset<-combined_dataset %>%
  filter(market_desc=="Unclassified") 

write_rds(unclassified_dataset, file=here("data_folder","main","tilefish",glue("tilefish_unclassified_dataset{out_data_string}.Rds")))

# put everything else in a dataset
# discard the observations with mark_in=0 ( dealers with minimal variance, low prices
estimation_dataset<-combined_dataset %>%
  filter(market_desc!="Unclassified") %>%
  filter(mark_in==1) %>%
  select(-c("mark_in", "flag_in"))

write_rds(estimation_dataset, file=here("data_folder","main","tilefish",glue("tilefish_estimation_dataset{out_data_string}.Rds")))


