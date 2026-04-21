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
         SEMESTER= as.integer(semester),
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

comm.land.res_updated<-bsb_stockeff$comm.land.res %>%
  left_join(aggregated_landings, by=join_by(YEAR, SPECIES_ITIS, STOCK_ABBREV, SEX_TYPE, NESPP4, REGION_ID, BLOCK_ID==SEMESTER))

comm.land.res_updated <- comm.land.res_updated %>%
  mutate(LANDINGS_KG = case_when(
    is.na(LANDINGS_KG_CAMS) ~ LANDINGS_KG,
    .default=LANDINGS_KG_CAMS)
  ) %>%
  select(-c(MARKET_DESC,LANDINGS_KG_CAMS))



# NEITHER LANDINGS_KG_NOADJ NOR EXP_RATIO are used downstream
# Substitute in CAMS land for stockeff landings where available (2013-2024)
# Run the conversion to Catch at age
land.CAA <- reallocate_market_categories(
  species_itis             = "167687",
  mkt.res                  = bsb_stockeff$mkt.res,
  comm.land.res            = comm.land.res_updated,
  comm.land.length.age.res = bsb_stockeff$comm.land.length.age.res,
  out_of_sample_predictions = out_of_sample_predictions1
)

# TEST.  If i've done the allocation correctly, the total of CAA_OLD and CAA New are the same.
test1<-land.CAA %>%
  filter(YEAR>=2013) %>%
  summarise(CAA_OLD=sum(CAA_OLD),
            CAA_NEW=sum(CAA_NEW)
  )

test1<-land.CAA %>%
  filter(YEAR>=2013) %>%
  group_by(YEAR, STOCK_ABBREV) %>%
  summarise(CAA_OLD=sum(CAA_OLD),
            CAA_NEW=sum(CAA_NEW)
  )



# Run the conversion to Catch at age on the stockeff data
OG.land.CAA <- reallocate_market_categories(
  species_itis             = "167687",
  mkt.res                  = bsb_stockeff$mkt.res,
  comm.land.res            = bsb_stockeff$comm.land.res,
  comm.land.length.age.res = bsb_stockeff$comm.land.length.age.res,
  out_of_sample_predictions = out_of_sample_predictions1
)




# NEITHER LANDINGS_KG_NOADJ NOR EXP_RATIO are used downstream
# Substitute in CAMS land for stockeff landings where available (2013-2024)
# Run the conversion to Catch at age
# use the ambitious predictions that force all unclassifieds to be allocated to something
land.CAA.ambitious <- reallocate_market_categories(
  species_itis             = "167687",
  mkt.res                  = bsb_stockeff$mkt.res,
  comm.land.res            = comm.land.res_updated,
  comm.land.length.age.res = bsb_stockeff$comm.land.length.age.res,
  out_of_sample_predictions = out_of_sample_predictions2
)



# Run the conversion to Catch at age on the stockeff data
# use the ambitious predictions that force all unclassifieds to be allocated to something
OG.land.CAA.abmitious <- reallocate_market_categories(
  species_itis             = "167687",
  mkt.res                  = bsb_stockeff$mkt.res,
  comm.land.res            = bsb_stockeff$comm.land.res,
  comm.land.length.age.res = bsb_stockeff$comm.land.length.age.res,
  out_of_sample_predictions = out_of_sample_predictions2
)






out_of_sample_predictions1 <- out_of_sample_predictions1 %>%
  mutate(has_rf_pred = 1)

# --- Join StockEff tables and reapportionment predictions -------------
# Join order:
#   1. comm.land.res (aggregate landings) is the spine.
#   2. comm.land.length.age.res adds length/age proportions.
#   3. mkt.res adds MARKET_DESC via NESPP4.
#   4. out_of_sample_predictions adds reapportioned landings and MARKET_DESC_ORIG.
#      BLOCK_ID (StockEff) maps to SEMESTER (predictions).
comm.land.length.age_DEFAULT <- comm.land.res_updated %>%
  left_join(bsb_stockeff$comm.land.length.age.res,
            by = join_by(SPECIES_ITIS, NESPP4, YEAR, SEX_TYPE,
                         STOCK_ABBREV, REGION_ID, BLOCK_ID)) %>%
  left_join(bsb_stockeff$mkt.res,
            by = join_by(NESPP4)) %>%
  left_join(out_of_sample_predictions1,
            by = join_by(SPECIES_ITIS, YEAR, STOCK_ABBREV,
                         MARKET_DESC, BLOCK_ID == SEMESTER))


comm.land.length.age_REVISED <- comm.land.res_updated %>%
  left_join(bsb_stockeff$mkt.res,
            by = join_by(NESPP4)) %>%
  left_join(out_of_sample_predictions1,
            by = join_by(SPECIES_ITIS, YEAR, STOCK_ABBREV,
                         MARKET_DESC, BLOCK_ID == SEMESTER)) %>%
  left_join(bsb_stockeff$comm.land.length.age.res,
            by = join_by(SPECIES_ITIS, NESPP4, YEAR, SEX_TYPE,
                         STOCK_ABBREV, REGION_ID, BLOCK_ID)) 

#comm.land.length.age_DEFAULT<-comm.land.length.age_DEFAULT %>%
#  mutate(source=1)


#comm.land.length.age_REVISED<-comm.land.length.age_REVISED %>%
#  mutate(source=2)

# identical datasets come out.
test<-rbind(comm.land.length.age_REVISED, comm.land.length.age_DEFAULT)
z<-duplicated(test)
table(z)


#SHort circuit the age key
comm.land.length.age_SS <- comm.land.res_updated %>%
  left_join(bsb_stockeff$mkt.res,
            by = join_by(NESPP4)) 

comm.land.length.age_SS  <- comm.land.length.age_SS  %>%
  mutate(.in_left  = TRUE)
out_of_sample_predictions1 <- out_of_sample_predictions1 %>%
  mutate(.in_right = TRUE)

comm.land.length.age_SS<-comm.land.length.age_SS %>%
  full_join(out_of_sample_predictions1,
            by = join_by(SPECIES_ITIS, YEAR, STOCK_ABBREV,
                         MARKET_DESC, BLOCK_ID == SEMESTER)) %>%
  mutate(
    across(c(.in_left, .in_right), \(x) replace_na(x, FALSE))  # coerce NAs first
  ) %>%
  mutate(
    .merge = case_when(
      .in_left & !.in_right ~ 1L,
      !.in_left &  .in_right ~ 2L,
      .in_left &  .in_right ~ 3L
    )
  )

table(comm.land.length.age_SS$YEAR, comm.land.length.age_SS$.merge)

#Update with the apportionment
comm.land.length.age_SS <- comm.land.length.age_SS %>%
  filter(YEAR>=2013) %>%
  mutate(LANDINGS_KG_ADJUSTED = case_when(
    is.na(has_rf_pred)         ~ LANDINGS_KG,
    !is.na(has_rf_pred)  & MARKET_DESC == "UNCLASSIFIED" ~ LANDINGS_KG_CATEGORY_APPORTION,
    !is.na(has_rf_pred)  & MARKET_DESC != "UNCLASSIFIED" ~ LANDINGS_KG + LANDINGS_KG_CATEGORY_APPORTION,
    .default = NA_real_
  ))



# TEST.  If i've done the allocation correctly, the total of CAA_OLD and CAA New are the same.
test1<-comm.land.length.age_SS %>%
  group_by(YEAR, STOCK_ABBREV, BLOCK_ID) %>%
  summarise(LANDINGS_KG=sum(LANDINGS_KG),
            LANDINGS_KG_ADJUSTED=sum(LANDINGS_KG_ADJUSTED)
  ) %>%
  mutate(LANDINGS_KG = scales::number(LANDINGS_KG, accuracy = 1, big.mark = ","),
         LANDINGS_KG_ADJUSTED = scales::number(LANDINGS_KG_ADJUSTED, accuracy = 1, big.mark = ",")
         )
#It's not perfect, it's within 10kg and I don't know why.
View(test1)



# Go back to the regular way in the code:


comm.land.length.age_DEFAULT

comm.land.length.age_SS <- comm.land.length.age_SS %>%
  filter(YEAR>=2013) %>%
  mutate(LANDINGS_KG_ADJUSTED = case_when(
    is.na(has_rf_pred)         ~ LANDINGS_KG,
    !is.na(has_rf_pred)  & MARKET_DESC == "UNCLASSIFIED" ~ LANDINGS_KG_CATEGORY_APPORTION,
    !is.na(has_rf_pred)  & MARKET_DESC != "UNCLASSIFIED" ~ LANDINGS_KG + LANDINGS_KG_CATEGORY_APPORTION,
    .default = NA_real_
  ))




comm.land.length.age_DEFAULT <- comm.land.length.age_DEFAULT %>%
  mutate(LANDINGS_KG_ADJUSTED = case_when(
    is.na(has_rf_pred)         ~ LANDINGS_KG,
    !is.na(has_rf_pred)  & MARKET_DESC == "UNCLASSIFIED" ~ LANDINGS_KG_CATEGORY_APPORTION,
    !is.na(has_rf_pred)  & MARKET_DESC != "UNCLASSIFIED" ~ LANDINGS_KG + LANDINGS_KG_CATEGORY_APPORTION,
    .default = NA_real_
  ))

# --- Scaling chain ----------------------------------------------------
# Disaggregate adjusted landings into numbers at age via the proportions
# stored in the length-age view.
#
# SCALING_FACTOR_NEW:    total number of fish implied by adjusted landings
#                        (LANDINGS_KG_ADJUSTED / AVG_FISH_WT)
# WT_AT_LENGTH_NEW:      weight allocated to each length bin
#                        (PROP_WT_LENGTH * SCALING_FACTOR_NEW)
# WT_AT_AGE_LENGTH_NEW:  weight allocated to each age within each length bin
#                        (WT_AT_LENGTH_NEW * PROP_AT_AGE)
# NO_AT_AGE_LENGTH_NEW:  numbers at age within each length bin
#                        (WT_AT_AGE_LENGTH_NEW / IND_AVG_WT_KG)
comm.land.length.age_DEFAULT <- comm.land.length.age_DEFAULT %>%
  mutate(
    SCALING_FACTOR_NEW    = LANDINGS_KG_ADJUSTED / AVG_FISH_WT,
    WT_AT_LENGTH_NEW      = PROP_WT_LENGTH * SCALING_FACTOR_NEW,
    WT_AT_AGE_LENGTH_NEW  = WT_AT_LENGTH_NEW * PROP_AT_AGE,
    NO_AT_AGE_LENGTH_NEW  = WT_AT_AGE_LENGTH_NEW / IND_AVG_WT_KG
  )

# --- Summarize to catch-at-age ----------------------------------------
# CAA_OLD: original StockEff numbers at age (NO_AT_AGE_LENGTH), summed
#          across all length bins within stock/year/age.
# CAA_NEW: reapportioned numbers at age (NO_AT_AGE_LENGTH_NEW), same grouping.
land.CAA <- comm.land.length.age_DEFAULT %>%
  group_by(SPECIES_ITIS,STOCK_ABBREV, YEAR, AGE) %>%
  summarize(CAA_OLD = sum(NO_AT_AGE_LENGTH, na.rm=TRUE),
            CAA_NEW = sum(NO_AT_AGE_LENGTH_NEW, na.rm=TRUE), .groups = "drop")

# Full join preserves any stock/year/age combinations present in one
# summary but not the other (e.g., years with no RF predictions).

land.CAA<-land.CAA %>%
  mutate(CAA_NEW = scales::number(CAA_NEW, accuracy = 1, big.mark = ","),
       CAA_OLD = scales::number(CAA_OLD, accuracy = 1, big.mark = ",")
)

