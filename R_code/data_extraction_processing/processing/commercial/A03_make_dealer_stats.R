###############################################################################
# A03_make_dealer_stats.R
# Purpose: R translation of A03_make_dealer_stats.do
#
# Inputs:
#   - landings_cleaned_{vintage_string}.Rds
#
# Outputs:
#   - dlrid_historical_stats_{vintage_string}.Rds
#   - dlrid_lag_stats_{vintage_string}.Rds
#
# Expects in environment: vintage_string, data_main
###############################################################################

library(tidyverse)
library(glue)

landings <- readRDS(
  file.path(data_main, "commercial",
            glue("landings_cleaned_{vintage_string}.Rds"))
)

# =============================================================================
# Block 1: Historical dealer statistics (2010-2014)
# Used for target encoding of dlrid.
# One row per dlrid x market_desc, then reshaped wide.
# Unclassified is dropped throughout.
# =============================================================================

# TransactionCount: 1 per unique dlrid x camsid x market_desc combination.
# Stata: bysort dlrid camsid market_desc: gen TransactionCount = (_n==1)
# then collapse (sum). Net effect: count distinct camsid per dlrid x market_desc.
historical <- landings %>%
  filter(year >= 2010, year <= 2014) %>%
  group_by(dlrid, camsid, market_desc) %>%
  mutate(TransactionCount = row_number() == 1L) %>%
  ungroup() %>%
  group_by(dlrid, market_desc) %>%
  summarise(
    lndlb          = sum(lndlb),
    TransactionCount = sum(as.integer(TransactionCount)),
    .groups = "drop"
  ) %>%
  mutate(mymarket = as.character(market_desc)) %>%
  filter(mymarket != "Unclassified") %>%
  select(dlrid, mymarket, lndlb, TransactionCount)

# Reshape wide: one row per dlrid, columns per size category
historical_wide <- historical %>%
  pivot_wider(
    id_cols     = dlrid,
    names_from  = mymarket,
    values_from = c(lndlb, TransactionCount),
    values_fill = 0L
  )

# Rename lndlb columns to DealerHLbsPurchased{Size}
historical_wide <- historical_wide %>%
  rename_with(~ gsub("^lndlb_", "DealerHLbsPurchased", .x),
              starts_with("lndlb_"))

# Compute totals and shares across the four size categories
sizes_hist <- c("Jumbo", "Large", "Medium", "Small")

historical_wide <- historical_wide %>%
  mutate(
    totalland  = rowSums(select(., paste0("DealerHLbsPurchased", sizes_hist)),
                         na.rm = TRUE),
    totaltrans = rowSums(select(., paste0("TransactionCount",    sizes_hist)),
                         na.rm = TRUE)
  )

for (s in sizes_hist) {
  historical_wide[[glue("Share2014{s}")]] <-
    historical_wide[[glue("DealerHLbsPurchased{s}")]] / historical_wide$totalland
  historical_wide[[glue("Frac2014T{s}")]] <-
    historical_wide[[glue("TransactionCount{s}")]] / historical_wide$totaltrans
}

historical_wide <- historical_wide %>%
  select(-totalland, -totaltrans)

saveRDS(
  historical_wide,
  file = file.path(data_main, "commercial",
                   glue("dlrid_historical_stats_{vintage_string}.Rds"))
)


# =============================================================================
# Block 2: Lagged annual dealer statistics 
# Produces 1-year lags of size-category share of pounds and transactions.
# After reshape, tsfill equivalent fills all dlrid x year combinations;
# missing values mean the dealer bought nothing that year (no zero-fill here).
# =============================================================================
lag_stats <- landings %>%
  group_by(dlrid, camsid, market_desc) %>%
  mutate(TransactionCount = row_number() == 1L) %>%
  ungroup() %>%
  group_by(dlrid, market_desc, year) %>%
  summarise(
    lndlb            = sum(lndlb),
    TransactionCount = sum(as.integer(TransactionCount)),
    .groups          = "drop"
  ) %>%
  mutate(mymarket = as.character(market_desc)) %>%
  filter(mymarket != "Unclassified") %>%
  select(dlrid, year, mymarket, lndlb, TransactionCount)

# Compute within-year totals and shares
lag_stats <- lag_stats %>%
  group_by(dlrid, year) %>%
  mutate(
    TotalPounds = sum(lndlb),
    TotalTrans  = sum(TransactionCount)
  ) %>%
  ungroup() %>%
  mutate(
    LagSharePounds = lndlb / TotalPounds,
    LagShareTrans  = TransactionCount / TotalTrans
  ) %>%
  rename(LagPounds = lndlb, LagTrans = TransactionCount) %>%
  select(dlrid, year, mymarket, LagSharePounds, LagShareTrans, LagPounds, LagTrans)

# Lag: shift year forward by 1 so year t row contains year t-1 statistics
lag_stats <- lag_stats %>%
  mutate(year = year + 1L)

# Reshape wide
lag_wide <- lag_stats %>%
  pivot_wider(
    id_cols     = c(dlrid, year),
    names_from  = mymarket,
    values_from = c(LagSharePounds, LagShareTrans, LagPounds, LagTrans)
    # NAs left as NA: dealer did not buy that category that year
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
  file = file.path(data_main, "commercial",
                   glue("dlrid_lag_stats_{vintage_string}.Rds"))
)
