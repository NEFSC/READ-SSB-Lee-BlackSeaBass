################################################################################
################################################################################
# Script:       LAA_script.R
# Purpose:      Builds five parallel landings-at-age (LAA) series for black sea
#               bass from five different landings sources and joins them side by
#               side so they can be compared. This is a verification and
#               decomposition script, not a production path: it writes nothing
#               to disk and ends with an in-memory identity check.
# Inputs:       out_of_sample_predictions_YRS_nocluster<vintage>.Rds
#               ambitious_out_of_sample_predictions_YRS_nocluster<vintage>.Rds
#               StockEff, via get_stockeff() (ITIS 167687, 2013-2024)
# Outputs:      NONE. Everything stays in memory - `ages_combined` holds the six
#               joined series, `check` holds the reconciliation.
# Dependencies: get_intermediate_stockeff.R, get_ages.R,LAA_calculation_BSB.R
#               sourced in that order at lines 55-61
#               Also needs `nefscdb_con` to already exist in the session through .Rprofile
# Pipeline:     Hand-run. No wrapper calls this script, and it calls no other
#               script. It sits downstream of the random forest (which produces
#               the prediction files) and parallel to LAA_test_script.R, which
#               exercises the monolithic LAA_calculation() instead.
#
# THE Five SERIES. Each is landings-at-age computed from a different landings
# source, NOT YET  joined on (SPECIES_ITIS, STOCK_ABBREV, YEAR, AGE):
#   CAA_sum_reg      the conservative random forest apportionment.
#   CAA_sum_amb      the ambitious random forest apportionment.
#   CAA_solo_reg    Just the MARKET_DESC_ORIG=unclassified for the conservative random forest apportionment.
#   CAA_solo_amb    Just the MARKET_DESC_ORIG=unclassified for the ambitious random forest apportionment.
#   CAA_bau         Just the unclassifieds, straight out of Stockeff
#
#
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


here::i_am("R_code/LAA_calculation/LAA_script.R")

source(here("R_code/LAA_calculation/get_intermediate_stockeff.R"))

# The reapportionment work here is
# done with get_ages() instead, one call per landings source.

source(here("R_code/LAA_calculation/get_ages.R"))
source(here("R_code","LAA_calculation","LAA_calculation_BSB.R"))




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

# out_of_sample_predictions_reg contains some Unclassifieds
# out_of_sample_predictions_amb does not.
# i.e. "conservative" vs "ambitious": the ambitious model assigns every
# unclassified transaction to a market category, the conservative one is
# allowed to leave some fish unclassified. Both files contain the
# same total kilograms.

out_of_sample_predictions_reg<-readRDS(predictions_full_location1)
out_of_sample_predictions_amb<-readRDS(predictions_full_location2)


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

bsb_stockeff<-get_intermediate_stockeff(species_itis = 167687,
                           fyr = 2013, #Just 2013
                           lyr = 2024,
                           connection = connection)

# Everything below this line works on the three data frames already
# returned into bsb_stockeff, so no further database access is needed.




# Construct a dataset of Unclassifieds,that is zero-filled for all other market categories.
# dropping LANDINGS_KG will cause the LAA_calcuation_BSB to error when run with sumflag="sum" This is by design.
stockeff_unclass_only<-bsb_stockeff$comm.land.res %>%
  left_join(bsb_stockeff$mkt.res, by=join_by(NESPP4)) %>%
 mutate(LANDINGS_KG_CATEGORY_APPORTION = case_when(
      MARKET_DESC=="UNCLASSIFIED" ~ LANDINGS_KG,
      MARKET_DESC!="UNCLASSIFIED" ~ 0,
      TRUE ~ 0)
    )  %>%
  relocate(YEAR, SPECIES_ITIS, STOCK_ABBREV, SEX_TYPE, NESPP4, REGION_ID, BLOCK_ID) %>%
  select(-c(LANDINGS_KG_NOADJ, LANDINGS_KG,EXP_RATIO))



stopifnot(!anyNA(stockeff_unclass_only$NESPP4))

    
   

  

##########################################################
# Facilitate merge to Stockeff data for 
#out_of_sample_predictions1 and out_of_sample_predictions2 
##########################################################

out_of_sample_predictions_reg<-out_of_sample_predictions_reg %>%
  mutate(SPECIES_ITIS="167687",
         SEX_TYPE="NONE",
         REGION_ID=1,
         BLOCK_ID=as.integer(SEMESTER)
  ) %>%
  select(-SEMESTER)

out_of_sample_predictions_reg<-out_of_sample_predictions_reg %>%
  left_join(bsb_stockeff$mkt.res, by=join_by(MARKET_DESC)) %>%
  relocate(YEAR, SPECIES_ITIS, STOCK_ABBREV, SEX_TYPE, NESPP4, REGION_ID, BLOCK_ID)

stopifnot(!anyNA(out_of_sample_predictions_reg$NESPP4))

out_of_sample_predictions_amb<-out_of_sample_predictions_amb %>%
  mutate(SPECIES_ITIS="167687",
         SEX_TYPE="NONE",
         REGION_ID=1,
         BLOCK_ID=as.integer(SEMESTER)
  )  %>%
  select(-SEMESTER)

out_of_sample_predictions_amb<-out_of_sample_predictions_amb %>%
  left_join(bsb_stockeff$mkt.res, by=join_by(MARKET_DESC)) %>%
  relocate(YEAR, SPECIES_ITIS, STOCK_ABBREV, SEX_TYPE, NESPP4, REGION_ID, BLOCK_ID)

stopifnot(!anyNA(out_of_sample_predictions_amb$NESPP4))

####################################
# Full Age and length structures ###
####################################
CAA_sum_reg<- LAA_calculation(species_itis = '167687',
                          out_of_sample_predictions = out_of_sample_predictions_reg,
                          fyr = 2013,
                          lyr = 2024,
                          connection = connection,
                          sumflag="sum",
                          plotstub="reg")
CAA_sum_amb<- LAA_calculation(species_itis = '167687',
                          out_of_sample_predictions = out_of_sample_predictions_amb,
                          fyr = 2013,
                          lyr = 2024,
                          connection = connection,
                          sumflag="sum",
                          plotstub="amb")

####################################
# Just the reclassified fish     ###
####################################

CAA_solo_reg<- LAA_calculation(species_itis = '167687',
                          out_of_sample_predictions = out_of_sample_predictions_reg,
                          fyr = 2013,
                          lyr = 2024,
                          connection = connection,
                          sumflag="solo",
                          plotstub="reg")

CAA_solo_amb<- LAA_calculation(species_itis = '167687',
                          out_of_sample_predictions = out_of_sample_predictions_amb,
                          fyr = 2013,
                          lyr = 2024,
                          connection = connection,
                          sumflag="solo",
                          plotstub="amb")

####################################
# pass in just the stockeff Unclassified fish
# and see what the business as usual case thinks about the unclassified fish
####################################
CAA_bau<- LAA_calculation(species_itis = '167687',
                               out_of_sample_predictions = stockeff_unclass_only,
                               fyr = 2013,
                               lyr = 2024,
                               connection = connection,
                               sumflag="solo",
                               plotstub="bau")
# I think the figures that come out of this are incorrect for the "original"
# I think the figures that come out of all the sumflag=solo are incorrect.
dbDisconnect(connection)



#mass check
test1<-CAA_sum_reg %>%
  group_by(CAA_TYPE) %>%
  summarise(sum=sum(WAA))
test1

test2<-CAA_sum_amb %>%
  group_by(CAA_TYPE) %>%
  summarise(sum=sum(WAA))
test2


test3<-CAA_solo_reg %>%
  group_by(CAA_TYPE) %>%
  summarise(sum=sum(WAA))
test3

test4<-CAA_solo_amb %>%
  group_by(CAA_TYPE) %>%
  summarise(sum=sum(WAA))
test4


# note -- there's a differnt amount of weight passed through with the BAU and the other types.
# It's a difference between CAMS combined with the RF data processing compared to the StockEff processing
# We were aware of this and not particularly concerned.
test5<-CAA_bau %>%
  group_by(CAA_TYPE) %>%
  summarise(sum=sum(WAA))
test5

