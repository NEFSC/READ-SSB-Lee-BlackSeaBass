# This script has two goals
# 1. Make sure that the refactoring of the LAA calculation works
# 2. show how to uget NAA.


# =============================================================================
# Section 0: Load libraries, setup directories, source scripts
# Parse the predictions folder to get the out_of_sample_predictions
# =============================================================================


library("here")
library("glue")
library("conflicted")
conflicts_prefer(dplyr::filter())


here::i_am("R_code/LAA_calculation/revised_LAA_test_script.R")
source(here("R_code/LAA_calculation/get_stockeff.R"))
source(here("R_code/LAA_calculation/reallocate_market_categories.R"))
source(here("R_code/LAA_calculation/get_ages.R"))



predictions_vintage<-list.files(here("data_folder","predictions"), pattern=glob2rx("out_of_sample_predictions_YRS_nocluster*.Rds"))
predictions_vintage<-gsub("out_of_sample_predictions_YRS_nocluster","",predictions_vintage)
predictions_vintage<-gsub(".Rds","",predictions_vintage)
predictions_vintage<-max(predictions_vintage)

predictions_full_location1<-here("data_folder","predictions", glue("out_of_sample_predictions_YRS_nocluster{predictions_vintage}.Rds"))
predictions_full_location2<-here("data_folder","predictions", glue("ambitious_out_of_sample_predictions_YRS_nocluster{predictions_vintage}.Rds"))

# out_of_sample_predictions1 contains some Unclassifieds
# out_of_sample_predictions2 does not.
out_of_sample_predictions1<-readRDS(predictions_full_location1)
out_of_sample_predictions2<-readRDS(predictions_full_location2)

original_dataset_vintage <-"2026-03-16"


lbs_to_kg<-2.20462

# =============================================================================
# Section 1: Pull BSB data from stockeff
# =============================================================================
drv<-dbDriver("Oracle")
connection <- eval(nefscdb_con)

bsb_stockeff<-get_stockeff(species_itis = 167687,
                           fyr = 2013, #Just 2013
                           lyr = 2024,
                           connection = connection)

dbDisconnect(connection)



# =============================================================================
# Section 2: READ in original combined dataset
# I need to bring in my own own 2013-2024 "cams land" data to make things internally consistent
# the out_of_sample_predictions1 dataset does a prediction of market category for the unclassified market category
# For pre 2013 data, we just use landings
# For 2013-2024 data, we replace the original unclassified with the New unclassified in the prediction dataset
# For 2013-2024 data, we add the newlly  clasiifes to the original values when there are predictions
# If the data are internally consistent, this rebalancing has no change to total weights. However it is not, so it might be

# Importing my original combined dataset is a stopgap that allows for testing

# =============================================================================


# Read in the BSB_original_combined_dataset
input_file <- glue("BSB_original_combined_dataset{original_dataset_vintage}.Rds")
input_folder_path  <- here("data_folder", "main", "commercial")
input_file<- file.path(input_folder_path, input_file)

original_combined_dataset <-readRDS(file = input_file)
##########################################################
##########################################################
# Facilitate merge to Stockeff data
##########################################################
##########################################################
# do a little column renaming. Change types. 
landings_prepped<-original_combined_dataset %>%
  mutate(YEAR = as.numeric(as.character(year)),
         STOCK_ABBREV= as.character(toupper(stockarea)),
         BLOCK_ID= as.integer(semester), #create block_id (for stockeff) that is the semester.
         MARKET_DESC = toupper(as.character(market_desc)),
         MARKET_DESC = case_when (MARKET_DESC == 'MEDIUM' ~ "MEDIUM OR SELECT",
                                  MARKET_DESC != 'MEDIUM' ~ MARKET_DESC)
  )         

aggregated_landings<-landings_prepped %>%
  group_by(YEAR,STOCK_ABBREV, BLOCK_ID, MARKET_DESC) %>%
  summarise(LANDINGS_CAMS_KG=sum(livlb, na.rm=TRUE)/lbs_to_kg,.groups="drop_last")

##########################################################
# make some columns for the merge
##########################################################
aggregated_landings <-aggregated_landings %>%
  mutate(SPECIES_ITIS="167687",
         SEX_TYPE="NONE",
         REGION_ID=1
  ) 

##########################################################
# pull NEPP4 from bsb_stockeff$mkt.res
##########################################################
aggregated_landings2<-aggregated_landings %>%
  left_join(bsb_stockeff$mkt.res, by=join_by(MARKET_DESC)) %>%
  relocate(YEAR, SPECIES_ITIS, STOCK_ABBREV, SEX_TYPE, NESPP4, REGION_ID, BLOCK_ID)


#Construct a dataframe based on CAMS with no unclassifed landings. 
# cut out the unclassifieds and pass them in
aggregated_landings_nounc<-aggregated_landings2 %>%
  filter(MARKET_DESC != "UNCLASSIFIED") 


# Construct a dataframe based on CAMS with ONLY unclassifed landings. 
# cut out the unclassifieds and pass them in
aggregated_landings_only_unc<-aggregated_landings2 %>%
  filter(MARKET_DESC == "UNCLASSIFIED") 



##########################################################
# Facilitate merge to Stockeff data for 
#out_of_sample_predictions1 and out_of_sample_predictions2 
##########################################################

out_of_sample_predictions1<-out_of_sample_predictions1 %>%
  mutate(SPECIES_ITIS="167687",
         SEX_TYPE="NONE",
         REGION_ID=1,
         BLOCK_ID=as.integer(SEMESTER)
  )

out_of_sample_predictions1<-out_of_sample_predictions1 %>%
  left_join(bsb_stockeff$mkt.res, by=join_by(MARKET_DESC)) %>%
  relocate(YEAR, SPECIES_ITIS, STOCK_ABBREV, SEX_TYPE, NESPP4, REGION_ID, BLOCK_ID)

out_of_sample_predictions2<-out_of_sample_predictions2 %>%
  mutate(SPECIES_ITIS="167687",
         SEX_TYPE="NONE",
         REGION_ID=1,
         BLOCK_ID=as.integer(SEMESTER)
  ) 

out_of_sample_predictions2<-out_of_sample_predictions2 %>%
  left_join(bsb_stockeff$mkt.res, by=join_by(MARKET_DESC)) %>%
  relocate(YEAR, SPECIES_ITIS, STOCK_ABBREV, SEX_TYPE, NESPP4, REGION_ID, BLOCK_ID)



# =============================================================================
# Section 3: Use get_ages() to compute length ages_CAMS, 

# =============================================================================



ages_stockeff<-get_ages(
  species_itis             = "167687",
  landings.kg.name         ="LANDINGS_KG",
  comm.land.res            = bsb_stockeff$comm.land.res,
  comm.land.length.age.res = bsb_stockeff$comm.land.length.age.res,
  caa.new.name = "CAA_OLD"
)


# Pass in aggregated_landings2

ages_CAMS<-get_ages(
  species_itis             = "167687",
  landings.kg.name         ="LANDINGS_CAMS_KG",
  comm.land.res            = aggregated_landings2,
  comm.land.length.age.res = bsb_stockeff$comm.land.length.age.res,
  caa.new.name = "CAA_CAMS"
)


ages_CAMS_no_unclass<-get_ages(
  species_itis             = "167687",
  landings.kg.name         ="LANDINGS_CAMS_KG",
  comm.land.res            = aggregated_landings_nounc,
  comm.land.length.age.res = bsb_stockeff$comm.land.length.age.res,
  caa.new.name = "CAA_No_Unclass"
)


ages_CAMS_only_unclass<-get_ages(
  species_itis             = "167687",
  landings.kg.name         ="LANDINGS_CAMS_KG",
  comm.land.res            = aggregated_landings_only_unc,
  comm.land.length.age.res = bsb_stockeff$comm.land.length.age.res,
  caa.new.name = "CAA_Only_Unclass"
)




ages_reclass <-
  get_ages(
    species_itis             = "167687",
    landings.kg.name         ="LANDINGS_KG_CATEGORY_APPORTION",
    comm.land.res            = out_of_sample_predictions1,
    comm.land.length.age.res = bsb_stockeff$comm.land.length.age.res,
    caa.new.name = "CAA_reclass1"
  )

ages_reclass_amb <-
  get_ages(
    species_itis             = "167687",
    landings.kg.name         ="LANDINGS_KG_CATEGORY_APPORTION",
    comm.land.res            = out_of_sample_predictions2,
    comm.land.length.age.res = bsb_stockeff$comm.land.length.age.res,
    caa.new.name = "CAA_reclass_amb"
  )



#Then you have to merge together in a reasonable way. 
ages_combined <-ages_stockeff %>%
  left_join(ages_CAMS, by=join_by(SPECIES_ITIS, STOCK_ABBREV, YEAR, AGE)) %>%
  left_join(ages_CAMS_no_unclass, by=join_by(SPECIES_ITIS, STOCK_ABBREV, YEAR, AGE)) %>%
  left_join(ages_CAMS_only_unclass, by=join_by(SPECIES_ITIS, STOCK_ABBREV, YEAR, AGE)) %>%
  left_join(ages_reclass, by=join_by(SPECIES_ITIS, STOCK_ABBREV, YEAR, AGE)) %>%
  left_join(ages_reclass_amb, by=join_by(SPECIES_ITIS, STOCK_ABBREV, YEAR, AGE))

# Is is reasonable to split apart the CAA calculation?
# Do the "classifieds" separately from the "unclassifieds" and then add them together
ages_combined<-ages_combined%>%
  mutate(across(starts_with("CAA_"), ~replace_na(.x, 0)))

check<-ages_combined %>%
  mutate(caa_re_combine=CAA_No_Unclass + CAA_Only_Unclass) %>%
  select(SPECIES_ITIS, STOCK_ABBREV, YEAR, AGE, CAA_CAMS, caa_re_combine) %>%
  mutate(diff=CAA_CAMS-caa_re_combine,
         diff_flag = as.integer(abs(diff) >1e-8)
  ) %>%
  arrange(-diff)

# yes, when I split apart I get the same answers
table(check$diff_flag)




# 
# OBSOLETE now
# # Stick LANDINGS_KG_CAMS into bsb_stockeff$comm.land.res's LANDINGS_KG
# 
# comm.land.res_updated<-bsb_stockeff$comm.land.res %>%
#   left_join(aggregated_landings, by=join_by(YEAR, SPECIES_ITIS, STOCK_ABBREV, SEX_TYPE, NESPP4, REGION_ID, BLOCK_ID==SEMESTER))
# 
# comm.land.res_updated <- comm.land.res_updated %>%
#   mutate(LANDINGS_KG = case_when(
#     is.na(LANDINGS_KG_CAMS) ~ LANDINGS_KG,
#     .default=LANDINGS_KG_CAMS)
#   ) %>%
#   select(-c(MARKET_DESC,LANDINGS_KG_CAMS))
# 
# # NEITHER LANDINGS_KG_NOADJ NOR EXP_RATIO are used downstream
# 
# 
# 
# 
# 
# 
# 
# 
# 
# 
# 
# 
# ########################## OLD SECTION
# 
# 
# 
# # =============================================================================
# # Section 3A: Allocate and compute new Catch at Age. 
# # Substitute in CAMS land for stockeff landings where available (2013-2024)
# # Run the conversion to Catch at age
# land.CAA <- reallocate_market_categories(
#   species_itis             = "167687",
#   mkt.res                  = bsb_stockeff$mkt.res,
#   comm.land.res            = comm.land.res_updated,
#   comm.land.length.age.res = bsb_stockeff$comm.land.length.age.res,
#   out_of_sample_predictions = out_of_sample_predictions1
# )
# output_path  <- here("data_folder","predictions")
# output_file <- glue("cams_adusted_landings_at_age{original_dataset_vintage}.Rds")
# output_file <- file.path(output_path, output_file)
# write_rds(land.CAA,file = output_file)
# 
# 
# # TEST.  If i've done the allocation correctly, the total of CAA_OLD and CAA New are the same.
# # Note, this is not actually a good test, because a kg of Large is not the same number of idinviduals as a kg of Smalls.
# test1<-land.CAA %>%
#   filter(YEAR>=2013) %>%
#   summarise(CAA_OLD=sum(CAA_OLD),
#             CAA_NEW=sum(CAA_NEW)
#   )
# 
# test1<-land.CAA %>%
#   filter(YEAR>=2013) %>%
#   group_by(YEAR, STOCK_ABBREV) %>%
#   summarise(CAA_OLD=sum(CAA_OLD),
#             CAA_NEW=sum(CAA_NEW)
#   )
# 
# #format, so the thing left behind is easy on the eyes
# land.CAA<-land.CAA %>%
#   mutate(CAA_NEW = scales::number(CAA_NEW, accuracy = 1, big.mark = ","),
#          CAA_OLD = scales::number(CAA_OLD, accuracy = 1, big.mark = ",")
#   )
# 
# 
# # Run the conversion to Catch at age on the stockeff data
# OG.land.CAA <- reallocate_market_categories(
#   species_itis             = "167687",
#   mkt.res                  = bsb_stockeff$mkt.res,
#   comm.land.res            = bsb_stockeff$comm.land.res,
#   comm.land.length.age.res = bsb_stockeff$comm.land.length.age.res,
#   out_of_sample_predictions = out_of_sample_predictions1
# )
# output_file <- glue("stockeff_adusted_landings_at_age{original_dataset_vintage}.Rds")
# output_file <- file.path(output_path, output_file)
# write_rds(OG.land.CAA,file = output_file)
# 
# 
# #format, so the thing left behind is easy on the eyes
# OG.land.CAA<-OG.land.CAA %>%
#   mutate(CAA_NEW = scales::number(CAA_NEW, accuracy = 1, big.mark = ","),
#          CAA_OLD = scales::number(CAA_OLD, accuracy = 1, big.mark = ",")
#   )
# 
# # =============================================================================
# # Section 3B: Allocate and compute new Catch at Age. 
# # use the ambitious predictions that force all unclassifieds to be allocated to something
# # note that I'm passing in "out_of_sample_predictions2" here
# 
# 
# # Substitute in CAMS land for stockeff landings where available (2013-2024)
# # Run the conversion to Catch at age
# # use the ambitious predictions that force all unclassifieds to be allocated to something
# land.CAA.ambitious <- reallocate_market_categories(
#   species_itis             = "167687",
#   mkt.res                  = bsb_stockeff$mkt.res,
#   comm.land.res            = comm.land.res_updated,
#   comm.land.length.age.res = bsb_stockeff$comm.land.length.age.res,
#   out_of_sample_predictions = out_of_sample_predictions2
# )
# output_file <- glue("cams_ambitious_landings_at_age{original_dataset_vintage}.Rds")
# output_file <- file.path(output_path, output_file)
# write_rds(land.CAA.ambitious,file = output_file)
# 
# 
# #format, so the thing left behind is easy on the eyes
# land.CAA.ambitious<-land.CAA.ambitious %>%
#   mutate(CAA_NEW = scales::number(CAA_NEW, accuracy = 1, big.mark = ","),
#          CAA_OLD = scales::number(CAA_OLD, accuracy = 1, big.mark = ",")
#   )
# 
# 
# # Run the conversion to Catch at age on the stockeff data
# # use the ambitious predictions that force all unclassifieds to be allocated to something
# OG.land.CAA.ambitious <- reallocate_market_categories(
#   species_itis             = "167687",
#   mkt.res                  = bsb_stockeff$mkt.res,
#   comm.land.res            = bsb_stockeff$comm.land.res,
#   comm.land.length.age.res = bsb_stockeff$comm.land.length.age.res,
#   out_of_sample_predictions = out_of_sample_predictions2
# )
# 
# output_file <- glue("stockeff_ambitious_landings_at_age{original_dataset_vintage}.Rds")
# output_file <- file.path(output_path, output_file)
# write_rds(OG.land.CAA.ambitious,file = output_file)
# 
# #format, so the thing left behind is easy on the eyes
# OG.land.CAA.ambitious<-OG.land.CAA.ambitious %>%
#   mutate(CAA_NEW = scales::number(CAA_NEW, accuracy = 1, big.mark = ","),
#          CAA_OLD = scales::number(CAA_OLD, accuracy = 1, big.mark = ",")
#   )
# # =============================================================================
# # You can probably stop here. One of these 4 objects is what you want for the next step.
# # =============================================================================
# 
# 
# 
# 
# 
# 
# 
# 
# 
# 
# 
# 
# 
# 
# 
# # =============================================================================
# # Section 4A: Some testing
# # The CAA numbers didn't match and shouldn't. I realized that late, so I re-engineered the merges 
# # to ensure that weights matched.
# 
# # The first thing i did was check the order of the merges.
# 
# 
# # make a flag column
# out_of_sample_predictions1 <- out_of_sample_predictions1 %>%
#   mutate(has_rf_pred = 1)
# 
# # --- Join StockEff tables and reapportionment predictions -------------
# # Join order:
# #   1. comm.land.res (aggregate landings) is the spine.
# #   2. comm.land.length.age.res adds length/age proportions.
# #   3. mkt.res adds MARKET_DESC via NESPP4.
# #   4. out_of_sample_predictions adds reapportioned landings and MARKET_DESC_ORIG.
# #      BLOCK_ID (StockEff) maps to SEMESTER (predictions).
# comm.land.length.age_DEFAULT <- comm.land.res_updated %>%
#   left_join(bsb_stockeff$comm.land.length.age.res,
#             by = join_by(SPECIES_ITIS, NESPP4, YEAR, SEX_TYPE,
#                          STOCK_ABBREV, REGION_ID, BLOCK_ID)) %>%
#   left_join(bsb_stockeff$mkt.res,
#             by = join_by(NESPP4)) %>%
#   left_join(out_of_sample_predictions1,
#             by = join_by(SPECIES_ITIS, YEAR, STOCK_ABBREV,
#                          MARKET_DESC, BLOCK_ID == SEMESTER))
# 
# 
# 
# 
# # Reorder, the joins.  1 to 3, to 4 then 2.
# 
# comm.land.length.age_REVISED <- comm.land.res_updated %>%
#   left_join(bsb_stockeff$mkt.res,
#             by = join_by(NESPP4)) %>%
#   left_join(out_of_sample_predictions1,
#             by = join_by(SPECIES_ITIS, YEAR, STOCK_ABBREV,
#                          MARKET_DESC, BLOCK_ID == SEMESTER)) %>%
#   left_join(bsb_stockeff$comm.land.length.age.res,
#             by = join_by(SPECIES_ITIS, NESPP4, YEAR, SEX_TYPE,
#                          STOCK_ABBREV, REGION_ID, BLOCK_ID)) 
# 
# # identical datasets come out, so we're good
# test<-rbind(comm.land.length.age_REVISED, comm.land.length.age_DEFAULT)
# z<-duplicated(test)
# table(z)
# 
# # =============================================================================
# # Section 4B: Some testing
# 
# #SHort circuit the age key and pull out just weights
# 
# #join to market category names
# comm.land.length.age_SS <- comm.land.res_updated %>%
#   left_join(bsb_stockeff$mkt.res,
#             by = join_by(NESPP4)) 
# 
# # create some flag variables for the merge to make sure I don't gain or lose rows.
# comm.land.length.age_SS  <- comm.land.length.age_SS  %>%
#   mutate(.in_left  = TRUE)
# out_of_sample_predictions1 <- out_of_sample_predictions1 %>%
#   mutate(.in_right = TRUE)
# 
# #join to the out of sample predictions
# comm.land.length.age_SS<-comm.land.length.age_SS %>%
#   full_join(out_of_sample_predictions1,
#             by = join_by(SPECIES_ITIS, YEAR, STOCK_ABBREV,
#                          MARKET_DESC, BLOCK_ID == SEMESTER)) %>%
#   mutate(
#     across(c(.in_left, .in_right), \(x) replace_na(x, FALSE))  # coerce NAs first
#   ) %>%
#   mutate(
#     .merge = case_when(
#       .in_left & !.in_right ~ 1L, # in left dataset
#       !.in_left &  .in_right ~ 2L, # in right dataset 
#       .in_left &  .in_right ~ 3L # in both
#     )
#   )
# # looks good, I expect this because I don't have predictions pre 2013
# table(comm.land.length.age_SS$YEAR, comm.land.length.age_SS$.merge)
# 
# 
# #Update with the apportionment
# comm.land.length.age_SS <- comm.land.length.age_SS %>%
#   filter(YEAR>=2013) %>%
#   mutate(LANDINGS_KG_ADJUSTED = case_when(
#     is.na(has_rf_pred)         ~ LANDINGS_KG,
#     !is.na(has_rf_pred)  & MARKET_DESC == "UNCLASSIFIED" ~ LANDINGS_KG_CATEGORY_APPORTION,
#     !is.na(has_rf_pred)  & MARKET_DESC != "UNCLASSIFIED" ~ LANDINGS_KG + LANDINGS_KG_CATEGORY_APPORTION,
#     .default = NA_real_
#   ))
# 
# 
# 
# # TEST.  If i've done the allocation correctly, the total of LANDINGS_KG and LANDINGS_KG_ADJUSTED are the same.
# test1<-comm.land.length.age_SS %>%
#   group_by(YEAR, STOCK_ABBREV, BLOCK_ID) %>%
#   summarise(LANDINGS_KG=sum(LANDINGS_KG),
#             LANDINGS_KG_ADJUSTED=sum(LANDINGS_KG_ADJUSTED)
#   ) %>%
#   mutate(LANDINGS_KG = scales::number(LANDINGS_KG, accuracy = 1, big.mark = ","),
#          LANDINGS_KG_ADJUSTED = scales::number(LANDINGS_KG_ADJUSTED, accuracy = 1, big.mark = ",")
#          )
# 
# 
# #It's not perfect, it's within 10kg and I don't know why.
# View(test1)
# 
# 
# 
# # Go back to the regular way in the code:
# 
# 
# 
# comm.land.length.age_SS <- comm.land.length.age_SS %>%
#   filter(YEAR>=2013) %>%
#   mutate(LANDINGS_KG_ADJUSTED = case_when(
#     is.na(has_rf_pred)         ~ LANDINGS_KG,
#     !is.na(has_rf_pred)  & MARKET_DESC == "UNCLASSIFIED" ~ LANDINGS_KG_CATEGORY_APPORTION,
#     !is.na(has_rf_pred)  & MARKET_DESC != "UNCLASSIFIED" ~ LANDINGS_KG + LANDINGS_KG_CATEGORY_APPORTION,
#     .default = NA_real_
#   ))
# 
# 
# 
# 
# comm.land.length.age_DEFAULT <- comm.land.length.age_DEFAULT %>%
#   mutate(LANDINGS_KG_ADJUSTED = case_when(
#     is.na(has_rf_pred)         ~ LANDINGS_KG,
#     !is.na(has_rf_pred)  & MARKET_DESC == "UNCLASSIFIED" ~ LANDINGS_KG_CATEGORY_APPORTION,
#     !is.na(has_rf_pred)  & MARKET_DESC != "UNCLASSIFIED" ~ LANDINGS_KG + LANDINGS_KG_CATEGORY_APPORTION,
#     .default = NA_real_
#   ))
# 
# # --- Scaling chain ----------------------------------------------------
# # Disaggregate adjusted landings into numbers at age via the proportions
# # stored in the length-age view.
# #
# # SCALING_FACTOR_NEW:    total number of fish implied by adjusted landings
# #                        (LANDINGS_KG_ADJUSTED / AVG_FISH_WT)
# # WT_AT_LENGTH_NEW:      weight allocated to each length bin
# #                        (PROP_WT_LENGTH * SCALING_FACTOR_NEW)
# # WT_AT_AGE_LENGTH_NEW:  weight allocated to each age within each length bin
# #                        (WT_AT_LENGTH_NEW * PROP_AT_AGE)
# # NO_AT_AGE_LENGTH_NEW:  numbers at age within each length bin
# #                        (WT_AT_AGE_LENGTH_NEW / IND_AVG_WT_KG)
# comm.land.length.age_DEFAULT <- comm.land.length.age_DEFAULT %>%
#   mutate(
#     SCALING_FACTOR_NEW    = LANDINGS_KG_ADJUSTED / AVG_FISH_WT,
#     WT_AT_LENGTH_NEW      = PROP_WT_LENGTH * SCALING_FACTOR_NEW,
#     WT_AT_AGE_LENGTH_NEW  = WT_AT_LENGTH_NEW * PROP_AT_AGE,
#     NO_AT_AGE_LENGTH_NEW  = WT_AT_AGE_LENGTH_NEW / IND_AVG_WT_KG
#   )
# 
# # --- Summarize to catch-at-age ----------------------------------------
# # CAA_OLD: original StockEff numbers at age (NO_AT_AGE_LENGTH), summed
# #          across all length bins within stock/year/age.
# # CAA_NEW: reapportioned numbers at age (NO_AT_AGE_LENGTH_NEW), same grouping.
# land.CAA_test <- comm.land.length.age_DEFAULT %>%
#   group_by(SPECIES_ITIS,STOCK_ABBREV, YEAR, AGE) %>%
#   summarize(CAA_OLD = sum(NO_AT_AGE_LENGTH, na.rm=TRUE),
#             CAA_NEW = sum(NO_AT_AGE_LENGTH_NEW, na.rm=TRUE), .groups = "drop")
# 
# # Full join preserves any stock/year/age combinations present in one
# # summary but not the other (e.g., years with no RF predictions).
# 
# land.CAA_test<-land.CAA_test %>%
#   mutate(CAA_NEW = scales::number(CAA_NEW, accuracy = 1, big.mark = ","),
#        CAA_OLD = scales::number(CAA_OLD, accuracy = 1, big.mark = ",")
# )
# 
