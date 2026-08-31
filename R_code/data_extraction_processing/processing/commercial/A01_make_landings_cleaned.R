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
  file.path(my_datapull, "data_folder", "main", "commercial",
            glue("landings_all_{in_string}.Rds"))
)
# drop rows where lndlb==0
landings<-landings%>%
  filter(lndlb != 0) 

# fill dlr_date with record_land if it is missing. This happens for "not sold" records
landings <- landings %>%
  mutate( 
    dlr_date = if_else(is.na(dlr_date), record_land, dlr_date) 
  )

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
# Flag suspect records 
# VA / DE records
# VA: PZERO + specific dealer license numbers + year >= 2021
# DE: PZERO + day-of-month == 1 + (price == 0 OR port == 80999)

# Flag observations that have no market_desc. (merge_species_codes==1). This is
# VTR_ORPHAN_SPECIES, VTR_NOT_SOLD, VTR_NO_CATCH
# -----------------------------------------------------------------------------
landings <- landings %>%
  mutate(
    questionable_status = case_when(
      status == "PZERO" & state == "VA" &
        dlr_cflic %in% c("2147", "1148") & year >= 2021            ~ 1L,
      status == "PZERO" & state == "DE" & dayofm == 1 & price == 0    ~ 1L,
      status == "PZERO" & state == "DE" & dayofm == 1 & port == 80999 ~ 1L,
      merge_species_codes==1                                       ~ 1L, 
      is.na(value)                                                 ~ 1L, 
      TRUE                                                         ~ 0L
    )
  ) %>%
  select(-dayofm)



table(landings$questionable_status)
# -----------------------------------------------------------------------------
# Drop unmatched species codes
# merge_species_codes == 1: master-only rows — no matching size/grade descriptor.
# These should be only VTR discards, orphan species, novel market/grade codes.
# -----------------------------------------------------------------------------
no_codes<-landings %>%
  filter(merge_species_codes==1)

valid_vals<-c("VTR_DISCARD", "VTR_NO_CATCH", "VTR_NOT_SOLD", "VTR_ORPHAN_SPECIES")
stopifnot(!anyNA(no_codes$status), all(no_codes$status %in% valid_vals))



# -----------------------------------------------------------------------------
# Merge gear lookup (m:1 on negear)
# Stata asserts all rows matched (_merge == 3 always). Replicate with stopifnot.
# -----------------------------------------------------------------------------
cams_gears <- read_rds(
  file.path(my_datapull, "data_folder", "main", "commercial",
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

# -----------------------------------------------------------------------------
# Market category rebinning
# apply_bsb_market_rebinning() recodes market_code / market_desc and returns
# market_desc as a factor. Separate into string (market_desc_string) and
# factor (market_desc) to match Stata's rename + encode pattern.
# Stata label market_category: 1=Jumbo 2=Large 3=Medium 4=Small
#                               5=Extra Small 6=Unclassified
# -----------------------------------------------------------------------------
market_levels <- c("Jumbo", "Large", "Medium", "Small", "Extra Small", "Unclassified")

landings <- apply_bsb_market_rebinning(landings) %>%
  mutate(
    market_desc_string = as.character(market_desc),
    market_desc        = factor(market_desc_string, levels = market_levels)
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
state_fips_levels <- c(
  "CT", "DE", "FL", "ME", "MD", "MA", "NH", "NJ",
  "NY", "NC", "PA", "RI", "SC", "VT", "VA", "CN"
)

landings <- landings %>%
  rename(state_string = state) %>%
  mutate(state = factor(state_string, levels = state_fips_levels))

# -----------------------------------------------------------------------------
# Stockarea: North / South stock partition by CAMS statistical area
# South: area >= 621, or area in {614, 615}
# North: area <= 613, or area == 616
# Stata label stockunit: 0=Unknown 1=South 2=North
# Stata asserts stockarea >= 1 after assignment (no Unknown rows remain).
# -----------------------------------------------------------------------------
landings <- landings %>%
  mutate(
    stockarea = case_when(
      area >= 621              ~ 1L,
      area %in% c(614L, 615L) ~ 1L,
      area == 616L             ~ 2L,
      area <= 613              ~ 2L,
      TRUE                     ~ 0L
    ),
    stockarea = factor(stockarea,
                       levels = c(0L, 1L, 2L),
                       labels = c("Unknown", "South", "North"))
  )

stopifnot(
  "stockarea assert: unassigned (Unknown) rows found" =
    !any(landings$stockarea == "Unknown", na.rm = TRUE)
)

landings <- landings %>%
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






# -----------------------------------------------------------------------------
# Merge quarterly CPI deflators (m:1 on dateq)
# Stata keep(1 3) then asserts master-only rows (_merge==1) are
# year==2025 & month>=5, then drops them.
# Replicate: left_join, assert on NA deflator rows, drop them.
# -----------------------------------------------------------------------------
deflators <- readRDS(
  file.path(my_datapull, "data_folder", "external",
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
# Save questionable dataset
# -----------------------------------------------------------------------------
saveRDS(
  questionable_status,
  file = here("data_folder", "main", "commercial",
              glue("questionable_status_{vintage_string}.Rds"))
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
  file = here("data_folder", "main", "commercial",
              glue("landings_cleaned_{vintage_string}.Rds"))
)
