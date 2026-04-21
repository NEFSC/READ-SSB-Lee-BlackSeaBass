library(here)
library(glue)
library("conflicted")
conflicts_prefer(dplyr::filter())


here::i_am("R_code/LAA_calculation/revised_LAA_test_script.R")
source(here("R_code/LAA_calculation/get_stockeff.R"))
source(here("R_code/LAA_calculation/reallocate_market_categories.R"))

drv<-dbDriver("Oracle")
connection <- eval(nefscdb_con)

predictions_vintage<-list.files(here("data_folder","predictions"), pattern=glob2rx("out_of_sample_predictions_YRS_nocluster*.Rds"))
predictions_vintage<-gsub("out_of_sample_predictions_YRS_nocluster","",predictions_vintage)
predictions_vintage<-gsub(".Rds","",predictions_vintage)
predictions_vintage<-max(predictions_vintage)

predictions_full_location1<-here("data_folder","predictions", glue("out_of_sample_predictions_YRS_nocluster{predictions_vintage}.Rds"))
predictions_full_location2<-here("data_folder","predictions", glue("ambitious_out_of_sample_predictions_YRS_nocluster{predictions_vintage}.Rds"))


out_of_sample_predictions1<-readRDS(predictions_full_location1)
out_of_sample_predictions2<-readRDS(predictions_full_location2)

original_dataset_vintage <-"2026-03-16"




# =============================================================================
# Section 1: Pull BSB data from stockeff
# =============================================================================
drv<-dbDriver("Oracle")
connection <- eval(nefscdb_con)

bsb_stockeff<-get_stockeff(species_itis = 167687,
                           fyr = 1989,
                           lyr = 2024,
                           connection = connection)

dbDisconnect(connection)


# bring in my own 2013-2024 "cams land" data 

# =============================================================================
# Section 2: READ in original combined dataset
# =============================================================================


input_path  <- here("data_folder", "main", "commercial")
input_file <- glue("BSB_original_combined_dataset{original_dataset_vintage}.Rds")
input_path <- file.path(input_path, input_file)

original_combined_dataset <-readRDS(file = input_path)

landings_prepped<-original_combined_dataset %>%
  mutate(YEAR = as.numeric(as.character(year)),
         STOCK_ABBREV= as.character(toupper(stockarea)),
         SEMESTER= as.character(semester),
         MARKET_DESC = toupper(as.character(market_desc)),
         MARKET_DESC = case_when (MARKET_DESC == 'MEDIUM' ~ "MEDIUM OR SELECT",
                                  MARKET_DESC != 'MEDIUM' ~ MARKET_DESC)
  )         

aggregated_landings<-landings_prepped %>%
  group_by(YEAR,STOCK_ABBREV, SEMESTER, MARKET_DESC) %>%
  summarise(LANDINGS_KG_CAMS=sum(livlb/2.204, na.rm=TRUE),.groups="drop_last")

# make some columns for the merge

aggregated_landings <-aggregated_landings %>%
  mutate(SPECIES_ITIS="167687",
         SEX_TYPE="NONE",
         REGION_ID=1
  ) 

# pull NEPP4 from bsb_stockeff$mkt.res

aggregated_landings<-aggregated_landings %>%
  left_join(bsb_stockeff$mkt.res, by=join_by(MARKET_DESC)) %>%
  relocate(YEAR, SPECIES_ITIS, STOCK_ABBREV, SEX_TYPE, NESPP4, REGION_ID, SEMESTER)

# Stick LANDINGS_KG_CAMS into bsb_stockeff$comm.land.res's LANDINGS_KG

bsb_stockeff$comm.land.res<-bsb_stockeff$comm.land.res %>%
  left_join(aggregated_landings, by=join_by(YEAR, SPECIES_ITIS, STOCK_ABBREV, SEX_TYPE, NESPP4, REGION_ID, BLOCK_ID==SEMESTER))

# NEITHER LANDINGS_KG_NOADJ NOR EXP_RATIO are used downstream

land.CAA_refactored <- reallocate_market_categories(
  species_itis             = "167687",
  mkt.res                  = bsb_stockeff$mkt.res,
  comm.land.res            = bsb_stockeff$comm.land.res,
  comm.land.length.age.res = bsb_stockeff$comm.land.length.age.res,
  out_of_sample_predictions = readRDS(predictions_full_location1)
)


mm<-bsb_stockeff$mkt.res
zz<-bsb_stockeff$comm.land.res


