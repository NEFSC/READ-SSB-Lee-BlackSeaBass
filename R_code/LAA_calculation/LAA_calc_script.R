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



predictions_vintage<-list.files(here("data_folder","predictions"), pattern=glob2rx("SA_out_of_sample_predictions_YRS_*.Rds"))
predictions_vintage<-gsub("SA_out_of_sample_predictions_YRS_nocluster","",predictions_vintage)
predictions_vintage<-gsub(".Rds","",predictions_vintage)
predictions_vintage<-max(predictions_vintage)

predictions_full_location1<-here("data_folder","predictions", glue("SA_out_of_sample_predictions_YRS_nocluster{predictions_vintage}.Rds"))
predictions_full_location2<-here("data_folder","predictions", glue("SA_ambitious_out_of_sample_predictions_YRS_nocluster{predictions_vintage}.Rds"))

# out_of_sample_predictions1 contains some Unclassifieds
# out_of_sample_predictions2 does not.
out_of_sample_predictions1<-readRDS(predictions_full_location1)
out_of_sample_predictions2<-readRDS(predictions_full_location2)



original_dataset_vintage<-list.files(here("data_folder","main","commercial"), pattern=glob2rx("PRED_BSB_original_combined_dataset*.Rds"))
original_dataset_vintage<-gsub("PRED_BSB_original_combined_dataset","",original_dataset_vintage)
original_dataset_vintage<-gsub(".Rds","",original_dataset_vintage)
original_dataset_vintage<-max(original_dataset_vintage)

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
input_file <- glue("PRED_BSB_original_combined_dataset{original_dataset_vintage}.Rds")
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


# Pass in bsb_stockeff$comm.land.res. This should match the stockeff CAA

ages_stockeff<-get_ages(
  species_itis             = "167687",
  landings.kg.name         ="LANDINGS_KG",
  comm.land.res            = bsb_stockeff$comm.land.res,
  comm.land.length.age.res = bsb_stockeff$comm.land.length.age.res,
  caa.new.name = "CAA_OLD"
)


# Pass in aggregated_landings2. This is the CAA corresponding to the minimally processed CAMS data

ages_CAMS<-get_ages(
  species_itis             = "167687",
  landings.kg.name         ="LANDINGS_CAMS_KG",
  comm.land.res            = aggregated_landings2,
  comm.land.length.age.res = bsb_stockeff$comm.land.length.age.res,
  caa.new.name = "CAA_CAMS"
)

# Pass in aggregated_landings_nounc.  This is the CAA corresponding CAMS, WITHOUT any unclassified fish

ages_CAMS_no_unclass<-get_ages(
  species_itis             = "167687",
  landings.kg.name         ="LANDINGS_CAMS_KG",
  comm.land.res            = aggregated_landings_nounc,
  comm.land.length.age.res = bsb_stockeff$comm.land.length.age.res,
  caa.new.name = "CAA_No_Unclass"
)

# Pass in aggregated_landings_nounc.  CAA corresponding to the Unclassified fish in CAMS

ages_CAMS_only_unclass<-get_ages(
  species_itis             = "167687",
  landings.kg.name         ="LANDINGS_CAMS_KG",
  comm.land.res            = aggregated_landings_only_unc,
  comm.land.length.age.res = bsb_stockeff$comm.land.length.age.res,
  caa.new.name = "CAA_Only_Unclass"
)


# Pass in out_of_sample_predictions1.  CAA corresponding to the conservative predictions from the random forest


ages_reclass <-
  get_ages(
    species_itis             = "167687",
    landings.kg.name         ="LANDINGS_KG_CATEGORY_APPORTION",
    comm.land.res            = out_of_sample_predictions1,
    comm.land.length.age.res = bsb_stockeff$comm.land.length.age.res,
    caa.new.name = "CAA_reclass1"
  )
# Pass in out_of_sample_predictions1.  CAA corresponding to the ambitious predictions from the random forest

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


