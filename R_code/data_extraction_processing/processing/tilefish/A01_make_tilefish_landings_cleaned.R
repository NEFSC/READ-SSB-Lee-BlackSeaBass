###############################################################################
# A01_make_landings_cleaned.R
# Purpose: R translation of A01_make_landings_cleaned.do
#
# Inputs:
#   - landings_all_{in_string}.Rds       (R-produced, DataPull repo)
#   - cams_gears_{in_string}.Rds         (R-produced, DataPull repo)
#   - deflatorsQ_{in_string}.Rds         (R-produced, DataPull repo)
#
# Outputs:
#   - landings_cleaned_{vintage_string}.Rds
#
# Expects in environment:
#   in_string, vintage_string, my_datapull, data_main
#   apply_gear_categories(), apply_bsb_market_rebinning(), apply_bsb_grade_cleaning()
#   from gear_market_helpers.R (sourced by wrapper)
###############################################################################


# -----------------------------------------------------------------------------
# Read landings_all
# -----------------------------------------------------------------------------
landings <- read_rds(
  file.path(cfg$data_root, "data_folder", "main", "commercial", "tilefish",
            glue("tile_landings_all_{cfg$dataset_type}{in_string}.Rds"))
)
# drop rows where lndlb==0
landings<-landings%>%
  filter(lndlb != 0) 



# # -----------------------------------------------------------------------------
# # Drop zero-pound landings
# # -----------------------------------------------------------------------------
# landings <- landings %>%
#   filter(lndlb != 0)



# -----------------------------------------------------------------------------
# Date handling
# dlr_date is  (%tc) as POSIXct. Convert to Date (= Stata dofc()).
# dateq: year.quarter float e.g. 2018.1 — used as deflator merge key.
# -----------------------------------------------------------------------------
landings <- landings %>%
  mutate(
    dlr_date = as.Date(dlr_date),
    dateq    = lubridate::quarter(dlr_date, with_year = TRUE),
    dayofm = lubridate::mday(dlr_date) # dayofm is used later on to filter some questionable records from DE
    
  )


# -----------------------------------------------------------------------------
# Drop unmatched species codes
# merge_species_codes == 1: master-only rows — no matching size/grade descriptor.
# These should be only VTR discards, orphan species, novel market/grade codes.
# -----------------------------------------------------------------------------

#Patch some mis-matched kittens.  There are no Round Kittens in the keyfile, causing 
#mis-matches

landings<-landings %>%
  mutate(market_desc=ifelse(
      (market_code=="KT" & is.na(market_desc)),
            "KITTENS", market_desc)
  ) %>%
  mutate(grade_desc=ifelse(
    (market_code=="KT" & is.na(grade_desc)),
    "ROUND", grade_desc)
  ) %>%
  mutate(cf_lndlb_livlb=ifelse(
    (market_code=="KT" & is.na(cf_lndlb_livlb)),
    1, cf_lndlb_livlb)
  )%>%
  mutate(cf_lndlb_livlb=ifelse(
    (market_code=="KT" & is.na(cf_lndlb_livlb)),
    1, cf_lndlb_livlb)
  )%>%
  mutate(nespp4=ifelse(
    (market_code=="KT" & is.na(nespp4)),
    4464, nespp4)
  )%>%
  mutate(merge_species_codes=ifelse(
    (market_code=="KT" & merge_species_codes==1 & market_desc=="KITTENS"),
    3, merge_species_codes)
  )


# -----------------------------------------------------------------------------
# Flag observations that have no market_desc. (merge_species_codes==1). This is
# VTR_ORPHAN_SPECIES, VTR_NOT_SOLD, VTR_NO_CATCH
# -----------------------------------------------------------------------------


landings <- landings %>%
  mutate(
    questionable_status = case_when(
      status  %in% c("VTR_NOT_SOLD")   ~ 1L,
      merge_species_codes==1                                          ~ 1L,
      is.na(value)                                                    ~ 1L,
      TRUE                                                            ~ 0L
    )
  )

landings<-landings %>%
  select(-dayofm)



table(landings$questionable_status)



no_codes<-landings %>%
  filter(merge_species_codes==1)

valid_vals<-c("VTR_DISCARD", "VTR_NO_CATCH", "VTR_NOT_SOLD", "VTR_ORPHAN_SPECIES")
stopifnot(!anyNA(no_codes$status), all(no_codes$status %in% valid_vals))

# Saving dataset
saveRDS(no_codes,  file = file.path(tile_data_dir, glue("no_codes_{cfg$dataset_type}.Rds")))


# -----------------------------------------------------------------------------
# Merge gear lookup (m:1 on negear)
# Stata asserts all rows matched (_merge == 3 always). Replicate with stopifnot.
# -----------------------------------------------------------------------------
cams_gears <- read_rds(
  file.path(cfg$data_root, "data_folder", "main", "commercial",
            glue("cams_gears_{in_string}.Rds"))
)

n_before <- nrow(landings)
landings  <- landings %>%
  left_join(cams_gears, by = "negear")

stopifnot(
  "Gear merge: row count changed (unexpected many-to-many)" =
    nrow(landings) == n_before,
  "Gear merge: unmatched negear codes present" =
    !anyNA(landings$negear)
)

# -----------------------------------------------------------------------------
# Gear category construction
# apply_gear_categories() adds mygear (character). Seine / Dredge / Unknown
# collapse to Misc; case_when order reproduces Stata's last-replace-wins logic.
# Rename to mygear_string and encode as factor with alphabetical levels
# (matches Stata encode() behavior).
# -----------------------------------------------------------------------------
landings <- apply_gear_categories(landings) %>%
  rename(mygear_string = mygear) %>%
  mutate(
    mygear = factor(mygear_string,
                    levels = sort(unique(na.omit(mygear_string))))
  )


# aggregate before rebinning

aggregated<-landings %>%
  group_by(market_desc, year) %>%
  filter(year>=2001 & questionable_status==0) %>%
  summarise(total_lbs=sum(livlb, na.rm=TRUE),
            total_count=n()) %>%
  ungroup() %>%
  arrange(year, market_desc) %>%
  mutate(total_lbs=case_when(
         total_count<=2 ~ NA, 
         TRUE ~ total_lbs)
  )

# -----------------------------------------------------------------------------
# Save cleaned dataset
# -----------------------------------------------------------------------------
saveRDS(
  aggregated,
  file = file.path(tile_data_dir,
                   glue("tilefish_aggregated_prebin_{cfg$dataset_type}{vintage_string}.Rds"))
)


# -----------------------------------------------------------------------------
# Market category rebinning
# apply_bsb_market_rebinning() recodes market_code / market_desc and returns
# market_desc as a factor. Separate into string (market_desc_string) and
# factor (market_desc) to match Stata's rename + encode pattern.
# Stata label market_category: 1=Jumbo 2=Large 3=Medium 4=Small
#                               5=Extra Small 6=Unclassified
# -----------------------------------------------------------------------------

# Fix this part too

landings <- apply_tilefish_market_rebinning(landings) %>%
  mutate(
    market_desc_string = as.character(market_desc)
  )

# -----------------------------------------------------------------------------
# Grade cleaning
# apply_grade_cleaning() standardizes grade_desc and returns it as a factor.
# Stata label grade_category: 1=Round 2=Live 3=Ungraded
# Factor levels in helper are c("Round", "Live", "Ungraded") — matches.
# Stata pattern: drop grade_desc string, rename mygrade -> grade_desc.
# Net effect reproduced: grade_desc is now the factor.
# -----------------------------------------------------------------------------
landings <- apply_bsb_grade_cleaning(landings)

# -----------------------------------------------------------------------------
# State encoding
# Stata: rename state -> state_string, encode -> state (integer with FIPS labels)
# Factor levels ordered by FIPS integer value, matching Stata encode() ordering.
#   09=CT 10=DE 12=FL 23=ME 24=MD 25=MA 33=NH 34=NJ
#   36=NY 37=NC 42=PA 44=RI 45=SC 50=VT 51=VA 99=CN
# -----------------------------------------------------------------------------

#specify order in same order as fips codes.
state_fips_levels <- c(
  "CT", "DE", "FL", "ME", "MD", "MA", "NH", "NJ",
  "NY", "NC", "PA", "RI", "SC", "VT", "VA", "CN"
)

landings <- landings %>%
  rename(state_string = state) %>%
  mutate(state = factor(state_string, levels = state_fips_levels))



# -----------------------------------------------------------------------------
# Merge quarterly CPI deflators (m:1 on dateq)
# Stata keep(1 3) then asserts master-only rows (_merge==1) are
# year==2025 & month>=5, then drops them.
# Replicate: left_join, assert on NA deflator rows, drop them.
# -----------------------------------------------------------------------------
deflators <- readRDS(
  file.path(cfg$data_root, "data_folder", "external",
            glue("deflatorsQ_{in_string}.Rds"))
)

landings <- landings %>%
  left_join(deflators, by = "dateq")

undeflatable <- landings %>% filter(is.na(fCPIAUCSL_2023Q1))
stopifnot(
  "Undeflatable rows outside expected window (year==2026, month>=3)" =
    all(undeflatable$year == 2026 & undeflatable$month >= 3)
)

landings <- landings %>%
  filter(!is.na(fCPIAUCSL_2023Q1))

# -----------------------------------------------------------------------------
# Derived variables
# valueR_CPI : real value deflated to 2023Q1 CPI-U dollars
# weighting  : clone of lndlb (Stata clonevar weighting = lndlb)
# semester   : 1 = Jan-Jun, 2 = Jul-Dec
# -----------------------------------------------------------------------------
landings <- landings %>%
  mutate(
    valueR_CPI = value / fCPIAUCSL_2023Q1,
    weighting  = lndlb,
    semester   = if_else(month <= 6L, 1L, 2L)
  )




# split dataset
questionable_status<-landings%>%
  filter(questionable_status == 1) 
# -----------------------------------------------------------------------------
# Save questionable dataset # Need to change these.
# -----------------------------------------------------------------------------
saveRDS(
  questionable_status,
  file = file.path(tile_data_dir,
                   glue("questionable_tilefish_status_{cfg$dataset_type}{vintage_string}.Rds"))
)


landings<-landings%>%
  filter(questionable_status == 0) 

# break if we have any rows with missing value
stopifnot(!anyNA(landings$value) )

# -----------------------------------------------------------------------------
# Save cleaned dataset
# -----------------------------------------------------------------------------
saveRDS(
  landings,
  file = file.path(tile_data_dir,
                   glue("tilefish_landings_cleaned_{cfg$dataset_type}{vintage_string}.Rds"))
)

cat("A01_make_tilefish_landings_cleaned.R finished \n")
