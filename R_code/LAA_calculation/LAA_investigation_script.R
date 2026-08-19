################################################################################
################################################################################
# Script:       LAA_investigation_script.R
# Purpose:      Builds six parallel landings-at-age (LAA) series for black sea
#               bass from six different landings sources and joins them side by
#               side so they can be compared. This is a verification and
#               decomposition script, not a production path: it writes nothing
#               to disk and ends with an in-memory identity check.
# Inputs:       out_of_sample_predictions_YRS_nocluster<vintage>.Rds
#               ambitious_out_of_sample_predictions_YRS_nocluster<vintage>.Rds
#               BSB_original_combined_dataset<vintage>.Rds
#               StockEff, via get_stockeff() (ITIS 167687, 2013-2024)
# Outputs:      NONE. Everything stays in memory - `ages_combined` holds the six
#               joined series, `check` holds the reconciliation.
# Dependencies: get_stockeff.R, reallocate_market_categories.R, get_ages.R,
#               sourced in that order at lines 19-21
#               Also needs `nefscdb_con` to already exist in the session through .Rprofile
# Pipeline:     Hand-run. No wrapper calls this script, and it calls no other
#               script. It sits downstream of the random forest (which produces
#               the prediction files) and parallel to LAA_test_script.R, which
#               exercises the monolithic LAA_calculation() instead.
#
# THE SIX SERIES. Each is landings-at-age computed from a different landings
# source, all joined on (SPECIES_ITIS, STOCK_ABBREV, YEAR, AGE):
#   LAA_OLD           StockEff's own LANDINGS_KG - the status quo.
#   LAA_CAMS          the same calculation driven by this project's CAMS
#                     landings instead of StockEff's.
#   LAA_No_Unclass    CAMS, unclassified market category removed.
#   LAA_Only_Unclass  CAMS, unclassified market category only.
#   LAA_reclass1      the conservative random forest apportionment.
#   LAA_reclass_amb   the ambitious random forest apportionment.
#
# THE two reclass SERIES are the LAA associated with the previously unclassified fish
# They are computed from LANDINGS_KG_CATEGORY_APPORTION, which only contains predictions for the
# Unclassifieds.  
#
# WHY THE CAMS DETOUR. The prediction files are built from CAMS transaction
# data; StockEff's landings have different data processing and initially did not agree.
# Importing this project's own combined dataset makes the comparison
# internally consistent even though it is not the production path - the
# original comment at Section 2 calls this "a stopgap that allows for testing".
#
# THE CHECK THAT RUNS AND THE ONE THAT DOESN'T. The executed check (end of file)
# is LAA_No_Unclass + LAA_Only_Unclass == LAA_CAMS to 1e-8. That tests get_ages() works properly. 
#
################################################################################
################################################################################

# This script has two goals
# 1. Make sure that the refactoring of the LAA calculation into constituent partsworks
# 2. show how to get NAA.


# =============================================================================
# Section 0: Load libraries, setup directories, source scripts
# Parse the predictions folder to get the out_of_sample_predictions
# =============================================================================


library("here")
library("glue")
library("conflicted")
library("ROracle")
conflicts_prefer(dplyr::filter())


here::i_am("R_code/LAA_calculation/LAA_calc_script.R")

source(here("R_code/LAA_calculation/get_stockeff.R"))

# reallocate_market_categories() is never called anywhere in this script.
# The reapportionment work here is
# done with get_ages() instead, one call per landings source.

source(here("R_code/LAA_calculation/reallocate_market_categories.R"))
source(here("R_code/LAA_calculation/get_ages.R"))




# Vintage-selection idiom, repeated throughout this project: glob the folder,
# strip the fixed prefix and suffix off the filenames to leave a bare ISO date,
# then take max() to get the newest. max() on ISO dates is lexicographic but
# gives the right answer because YYYY-MM-DD sorts the same either way.

predictions_vintage<-list.files(here("data_folder","predictions"), pattern=glob2rx("out_of_sample_predictions_YRS_nocluster*.Rds"))
predictions_vintage<-gsub("out_of_sample_predictions_YRS_nocluster","",predictions_vintage)
predictions_vintage<-gsub(".Rds","",predictions_vintage)
predictions_vintage<-max(predictions_vintage)

stopifnot(length(predictions_vintage)==1)

predictions_full_location1<-here("data_folder","predictions", glue("out_of_sample_predictions_YRS_nocluster{predictions_vintage}.Rds"))
predictions_full_location2<-here("data_folder","predictions", glue("ambitious_out_of_sample_predictions_YRS_nocluster{predictions_vintage}.Rds"))

# out_of_sample_predictions1 contains some Unclassifieds
# out_of_sample_predictions2 does not.
# i.e. "conservative" vs "ambitious": the ambitious model assigns every
# unclassified transaction to a market category, the conservative one is
# allowed to leave some fish unclassified. Both files contain the
# same total kilograms.

out_of_sample_predictions1<-readRDS(predictions_full_location1)
out_of_sample_predictions2<-readRDS(predictions_full_location2)


original_dataset_vintage<-list.files(here("data_folder","main","commercial"), pattern=glob2rx("BSB_original_combined_dataset*.Rds"))
original_dataset_vintage<-gsub("BSB_original_combined_dataset","",original_dataset_vintage)
original_dataset_vintage<-gsub(".Rds","",original_dataset_vintage)
original_dataset_vintage<-max(original_dataset_vintage)

# Pounds per kg
lbs_per_kg<-2.20462

# =============================================================================
# Section 1: Pull BSB data from stockeff
# =============================================================================


drv<-dbDriver("Oracle")
connection <- eval(nefscdb_con)

# NOTE THE YEAR RANGE. 2013-2024 here, against 1989-2024 in LAA_test_script.R
# and fit_BSB_WHAM.R. That is deliberate - the CAMS combined dataset read in
# Section 2 only covers 2013 on, and the comparison below is only meaningful
# over the years both sources cover. It does mean LAA_OLD computed here does not 
# have the same temporal range as LAA_OLD produced by the other scripts.

bsb_stockeff<-get_stockeff(species_itis = 167687,
                           fyr = 2013, #Just 2013
                           lyr = 2024,
                           connection = connection)

# Everything below this line works on the three data frames already
# returned into bsb_stockeff, so no further database access is needed.

dbDisconnect(connection)



# =============================================================================
# Section 2: READ in original combined dataset
# I'd prefer to bring in 2013-2024 "cams land"
# the out_of_sample_predictions1 dataset does a prediction of market category for the unclassified market category
# For pre 2013 data, we just use landings
# For 2013-2024 data, we replace the original unclassified with the New unclassified in the prediction dataset
# For 2013-2024 data, we add the newlly  classifieds to the original values when there are predictions
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
# Rename/retype CAMS columns into StockEff's vocabulary so the join keys line
# up. StockEff calls the semester BLOCK_ID and upper-cases its category names.
#
# THE 'MEDIUM' RECODE IS THE VISIBLE TIP OF A SILENT FAILURE MODE. NESPP4 is
# attached further down by joining mkt.res on MARKET_DESC, so any CAMS category
# string that does not match StockEff's exactly gets NESPP4 = NA, then fails to
# match the length/age table inside get_ages(), then gets dropped by the
# na.rm=TRUE in that function's summarize. 
# You may need to recode other categories

landings_prepped<-original_combined_dataset %>%
  mutate(YEAR = as.numeric(as.character(year)),
         STOCK_ABBREV= as.character(toupper(stockarea)),
         BLOCK_ID= as.integer(semester), #create block_id (for stockeff) that is the semester.
         MARKET_DESC = toupper(as.character(market_desc)),
         MARKET_DESC = case_when (MARKET_DESC == 'MEDIUM' ~ "MEDIUM OR SELECT",
                                  MARKET_DESC != 'MEDIUM' ~ MARKET_DESC)
  )         

# Collapse CAMS transactions to the StockEff landings grain
# (year x stock x semester x market category) and convert live pounds to kg.

aggregated_landings<-landings_prepped %>%
  group_by(YEAR,STOCK_ABBREV, BLOCK_ID, MARKET_DESC) %>%
  summarise(LANDINGS_CAMS_KG=sum(livlb, na.rm=TRUE)/lbs_per_kg,) %>%
  ungroup()

##########################################################
# make some columns for the merge
##########################################################
# These three are hardcoded purely so that the seven-column join key inside
# get_ages() (SPECIES_ITIS, NESPP4, YEAR, SEX_TYPE, STOCK_ABBREV, REGION_ID,
# BLOCK_ID) has something to match on.

# TYPE HAZARD: SPECIES_ITIS is set here as the CHARACTER "167687" to match what ROracle 
# returns for that column.

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


# THIS JOIN Could SILENTLY DROP LANDINGS. get_ages() matches on
# NESPP4, not on MARKET_DESC, so NESPP4 has to be attached here first. Any CAMS
# MARKET_DESC string that StockEff spells differently gets NESPP4 = NA and eventually
# falls out.
# The stopifnot() is designed to protect against this.

stopifnot(!anyNA(aggregated_landings2$NESPP4))

# The next two frames are the classified / unclassified split. They exist to
# support the additivity check at the end of the script


aggregated_landings_nounc<-aggregated_landings2 %>%
  filter(MARKET_DESC != "UNCLASSIFIED") 

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

stopifnot(!anyNA(out_of_sample_predictions1$NESPP4))

out_of_sample_predictions2<-out_of_sample_predictions2 %>%
  mutate(SPECIES_ITIS="167687",
         SEX_TYPE="NONE",
         REGION_ID=1,
         BLOCK_ID=as.integer(SEMESTER)
  ) 

out_of_sample_predictions2<-out_of_sample_predictions2 %>%
  left_join(bsb_stockeff$mkt.res, by=join_by(MARKET_DESC)) %>%
  relocate(YEAR, SPECIES_ITIS, STOCK_ABBREV, SEX_TYPE, NESPP4, REGION_ID, BLOCK_ID)

stopifnot(!anyNA(out_of_sample_predictions2$NESPP4))


# =============================================================================
# Section 3: Use get_ages() to compute length ages_CAMS, 

# =============================================================================



# get_ages() is the generalized engine: it applies the scaling chain
#   SCALING_FACTOR = <landings.kg.name> / AVG_FISH_WT
#   WT_AT_LENGTH   = PROP_WT_LENGTH * SCALING_FACTOR
#   WT_AT_AGE_LEN  = WT_AT_LENGTH   * PROP_AT_AGE
#   NO_AT_AGE_LEN  = WT_AT_AGE_LEN  / IND_AVG_WT_KG
# to whatever landings column you name, and returns the sum by
# (SPECIES_ITIS, STOCK_ABBREV, YEAR, AGE) under whatever name you ask for.
#
# Pass in bsb_stockeff$comm.land.res. This should match the stockeff Landings at age

ages_stockeff<-get_ages(
  species_itis             = "167687",
  landings.kg.name         ="LANDINGS_KG",
  comm.land.res            = bsb_stockeff$comm.land.res,
  comm.land.length.age.res = bsb_stockeff$comm.land.length.age.res,
  laa.new.name = "LAA_OLD"
)


# Pass in aggregated_landings2. This is the LAA corresponding to the minimally processed CAMS data

ages_CAMS<-get_ages(
  species_itis             = "167687",
  landings.kg.name         ="LANDINGS_CAMS_KG",
  comm.land.res            = aggregated_landings2,
  comm.land.length.age.res = bsb_stockeff$comm.land.length.age.res,
  laa.new.name = "LAA_CAMS"
)

# Pass in aggregated_landings_nounc.  This is the LAA corresponding CAMS, WITHOUT any unclassified fish

ages_CAMS_no_unclass<-get_ages(
  species_itis             = "167687",
  landings.kg.name         ="LANDINGS_CAMS_KG",
  comm.land.res            = aggregated_landings_nounc,
  comm.land.length.age.res = bsb_stockeff$comm.land.length.age.res,
  laa.new.name = "LAA_No_Unclass"
)

# Pass in aggregated_landings_nounc.  LAA corresponding to the Unclassified fish in CAMS

ages_CAMS_only_unclass<-get_ages(
  species_itis             = "167687",
  landings.kg.name         ="LANDINGS_CAMS_KG",
  comm.land.res            = aggregated_landings_only_unc,
  comm.land.length.age.res = bsb_stockeff$comm.land.length.age.res,
  laa.new.name = "LAA_Only_Unclass"
)

#######################################################################################
########## Assign ages to the RF-reclassified fish#####################################
#######################################################################################
# THE TWO reclass SERIES ARE NOT REAPPORTIONED TOTALS
# To get a full reapportioned series, add either age_reclass$LAA_reclass1 or ages_reclass_amb$LAA_reclass_amb to ages_CAMS_no_unclass$LAA_No_Unclass. 

# Pass in out_of_sample_predictions1.  LAA corresponding to the conservative predictions from the random forest

ages_reclass <-
  get_ages(
    species_itis             = "167687",
    landings.kg.name         ="LANDINGS_KG_CATEGORY_APPORTION",
    comm.land.res            = out_of_sample_predictions1,
    comm.land.length.age.res = bsb_stockeff$comm.land.length.age.res,
    laa.new.name = "LAA_reclass1"
  )
# Pass in out_of_sample_predictions1.  LAA corresponding to the ambitious predictions from the random forest

ages_reclass_amb <-
  get_ages(
    species_itis             = "167687",
    landings.kg.name         ="LANDINGS_KG_CATEGORY_APPORTION",
    comm.land.res            = out_of_sample_predictions2,
    comm.land.length.age.res = bsb_stockeff$comm.land.length.age.res,
    laa.new.name = "LAA_reclass_amb"
  )



#Then you have to merge together in a reasonable way. 

ages_combined <-ages_stockeff %>%
  left_join(ages_CAMS, by=join_by(SPECIES_ITIS, STOCK_ABBREV, YEAR, AGE)) %>%
  left_join(ages_CAMS_no_unclass, by=join_by(SPECIES_ITIS, STOCK_ABBREV, YEAR, AGE)) %>%
  left_join(ages_CAMS_only_unclass, by=join_by(SPECIES_ITIS, STOCK_ABBREV, YEAR, AGE)) %>%
  left_join(ages_reclass, by=join_by(SPECIES_ITIS, STOCK_ABBREV, YEAR, AGE)) %>%
  left_join(ages_reclass_amb, by=join_by(SPECIES_ITIS, STOCK_ABBREV, YEAR, AGE))

# Is is reasonable to split apart the LAA calculation?
# Do the "classifieds" separately from the "unclassifieds" and then add them together
# NA -> 0 across every LAA_ column.  After the left joins,
# an NA means "this series had no row for this stock/year/age". Treating as a true
# zero is correct

ages_combined<-ages_combined%>%
  mutate(across(starts_with("LAA_"), ~replace_na(.x, 0)))

# Tests that LAA_No_Unclass + LAA_Only_Unclass == LAA_CAMS to 1e-8.
# This check was built to give me confidence that I wrote the code properly.

check<-ages_combined %>%
  mutate(laa_re_combine=LAA_No_Unclass + LAA_Only_Unclass) %>%
  select(SPECIES_ITIS, STOCK_ABBREV, YEAR, AGE, LAA_CAMS, laa_re_combine) %>%
  mutate(diff=LAA_CAMS-laa_re_combine,
         diff_flag = as.integer(abs(diff) >1e-8)
  ) %>%
  arrange(-diff)

# yes, when I split apart I get the same answers
table(check$diff_flag)


