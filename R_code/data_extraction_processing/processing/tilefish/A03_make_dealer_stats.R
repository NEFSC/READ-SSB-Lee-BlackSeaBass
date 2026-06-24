###############################################################################
# A03_make_dealer_stats.R
# Purpose:Target encode dealer ids
#
# Inputs:
#   - landings_cleaned_{vintage_string}.Rds
#
# Outputs:
#   - dlrid_tile_lag_stats_{vintage_string}.Rds
#
# Expects in environment: vintage_string, data_main
###############################################################################

landings <- readRDS(
  file = here("R_code", "data_extraction_processing", "processing", "tilefish",
              glue("tilefish_landings_cleaned_{vintage_string}.Rds")))


# Drop rows where lndlb is na.
landings<-landings %>%
  filter(!is.na(lndlb)) 

# =============================================================================
# Block 2: Lagged annual dealer statistics 
# Produces 1-year lags of size-category share of pounds
# After reshape, tsfill equivalent fills all dlrid x year combinations;
# missing values mean the dealer bought nothing that year (no zero-fill here).
# =============================================================================
lag_stats <- landings %>%
  group_by(dlrid, market_desc, year) %>%
  summarise(
    lndlb            = sum(lndlb),
    .groups          = "drop"
  ) %>%
  mutate(mymarket = as.character(market_desc)) %>%
  filter(mymarket != "Unclassified") %>%
  select(dlrid, year, mymarket, lndlb)

# Compute within-year totals and shares
lag_stats <- lag_stats %>%
  group_by(dlrid, year) %>%
  mutate(
    TotalPounds = sum(lndlb)
  ) %>%
  ungroup() %>%
  mutate(
    LagSharePounds = lndlb / TotalPounds
  ) %>%
  rename(LagPounds = lndlb) %>%
  select(dlrid, year, mymarket, LagSharePounds, LagPounds)

# Lag: shift year forward by 1 so year t row contains year t-1 statistics
lag_stats <- lag_stats %>%
  mutate(year = year + 1L)

#there are no missing values. If a firm didn't buy any Medium, the dlrid-year-mymarket combination doesn't show up.
# If a firm didn't buy anything, there is no row of data
stopifnot(nrow(filter(lag_stats, if_any(c(LagSharePounds, LagPounds), is.na))) == 0)



# Reshape wide
lag_wide <- lag_stats %>%
  pivot_wider(
    id_cols     = c(dlrid, year),
    names_from  = mymarket,
    names_sep = "",
    values_from = c(LagSharePounds, LagPounds),
    values_fill = 0
  )

# tsfill equivalent: complete all dlrid x year combinations within each dealer's
# observed range. Do NOT zero-fill — NA means no activity that year.
lag_wide <- lag_wide %>%
  group_by(dlrid) %>%
  complete(year = seq(min(year), max(year))) %>%
  ungroup() %>%
  arrange(dlrid, year)

saveRDS(
  lag_wide,
  file = here("data_folder", "main", "commercial",
              glue("dlrid_tile_lag_stats_{vintage_string}.Rds"))
)
