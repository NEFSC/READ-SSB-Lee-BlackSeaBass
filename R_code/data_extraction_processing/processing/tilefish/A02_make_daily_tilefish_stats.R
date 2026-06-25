###############################################################################
# A02_make_daily_stats.R
# Purpose: R translation of A02_make_daily_stats.do
#
# Inputs:
#   - landings_cleaned_{vintage_string}.Rds
#
# Outputs:
#   - camsid_specific_cleaned_{vintage_string}.Rds
#   - daily_ma_{vintage_string}.Rds
#   - state_ma_{vintage_string}.Rds
#   - gear_ma_{vintage_string}.Rds
#
# Expects in environment: vintage_string, data_main
#
# Notes on moving average:
#   Stata tssmooth ma, window(7 0 0) computes a simple 7-day trailing mean.
#   After tsfill + zero-fill, the denominator is always 7. Reproduced here
#   via tidyr::complete() to fill gaps, zero-fill, then zoo::rollmeanr(k=7).
###############################################################################

# -----------------------------------------------------------------------------
# Read
# -----------------------------------------------------------------------------
landings <- readRDS(file = file.path(tile_data_dir,
  glue("tilefish_landings_cleaned_{vintage_string}.Rds"))
  )

                 

# Drop rows where lndlb is na.
landings<-landings %>%
  filter(!is.na(lndlb)) 

            
# -----------------------------------------------------------------------------
# Construct per-market-category lbs columns
# lndlbx{Size} = lndlb if market_desc_string == Size, else 0
# These are the building blocks for all downstream quantity aggregations.
# -----------------------------------------------------------------------------
sizes <-levels(landings$market_desc)

for (lvl in sizes) {
  landings[[paste0("Q_", lvl)]] <- as.numeric(landings$market_desc == lvl) * landings$lndlb
}

lndlbx_cols <- glue("Q_{sizes}")

# -----------------------------------------------------------------------------
# Daily market-level totals: DailyQ{Size}
# -----------------------------------------------------------------------------
landings <- landings %>%
  group_by(dlr_date) %>%
  mutate(across(all_of(lndlbx_cols), sum, .names = "Daily{.col}")) %>%
  ungroup()


# -----------------------------------------------------------------------------
# Trip (camsid x dlr_date) level totals: OwnQ{Size}
# -----------------------------------------------------------------------------
landings <- landings %>%
  group_by(dlr_date,camsid) %>%
  mutate(across(all_of(lndlbx_cols), sum, .names = "Own{.col}")) %>%
  ungroup()

# -----------------------------------------------------------------------------
# Other-trip quantity: DailyQ - OwnQ
# Stata asserts OtherQ >= 0 for all rows.
# -----------------------------------------------------------------------------

for (lvl in sizes) {
  landings[[paste0("OtherQ_", lvl)]] <- landings[[paste0("DailyQ_", lvl)]] - landings[[paste0("OwnQ_", lvl)]]
}


stopifnot(
  "OtherQ assert: negative values found" =
    all(select(landings, starts_with("OtherQ")) >= 0, na.rm = TRUE)
)

# -----------------------------------------------------------------------------
# State x day totals: StateQ{Size}
# -----------------------------------------------------------------------------
landings <- landings %>%
  group_by(dlr_date,state) %>%
  mutate(across(all_of(lndlbx_cols), sum, .names = "State{.col}")) %>%
  ungroup()


# State x day x trip totals: StateOwnQ{Size}
# adding state to the group_by() produces only a small 
# slight difference between this and the "OwnQ" 
landings <- landings %>%
  group_by(dlr_date, camsid, state) %>%
  mutate(across(all_of(lndlbx_cols), sum, .names = "StateOwn{.col}")) %>%
  ungroup()

# State other-trip quantity


for (lvl in sizes) {
  landings[[paste0("StateOtherQ_", lvl)]] <- landings[[paste0("StateQ_", lvl)]] - landings[[paste0("StateOwnQ_", lvl)]]
}


stopifnot(
  "StateOtherQ assert: negative values found" =
    all(select(landings, starts_with("StateOtherQ")) >= 0, na.rm = TRUE)
)

landings <- landings %>%
  select(-starts_with("StateOwnQ"))
# -----------------------------------------------------------------------------
# Gear x day totals: gearQ{Size}
# -----------------------------------------------------------------------------
landings <- landings %>%
  group_by(dlr_date, mygear) %>%
  mutate(across(all_of(lndlbx_cols), sum, .names = "gear{.col}")) %>%
  ungroup()

# -----------------------------------------------------------------------------
# Distinct trip counts by grouping strata
# Stata idiom: tag(vars) then total(tag), by(grouping vars)
# Equivalent: n_distinct(camsid) within each group
# -----------------------------------------------------------------------------

# ndistinct_stateM: distinct camsids per state x dlr_date x market_desc
landings <- landings %>%
  group_by(state, dlr_date, market_desc) %>%
  mutate(ndistinct_stateM = n_distinct(camsid)) %>%
  ungroup()

# ndistinct_gear: distinct camsids per mygear x dlr_date x market_desc
landings <- landings %>%
  group_by(mygear, dlr_date, market_desc) %>%
  mutate(ndistinct_gear = n_distinct(camsid)) %>%
  ungroup()

# ndistinct_state: distinct camsids per state x dlr_date
landings <- landings %>%
  group_by(state, dlr_date) %>%
  mutate(ndistinct_state = n_distinct(camsid)) %>%
  ungroup()

# ndistinct_trips: distinct camsids per dlr_date
landings <- landings %>%
  group_by(dlr_date) %>%
  mutate(ndistinct_trips = n_distinct(camsid)) %>%
  ungroup()

# Drop the lndlbx* and OwnQ* working columns (matches Stata drop at end)
landings <- landings %>%
  select(-starts_with("lndlbx"), -starts_with("OwnQ"))

# =============================================================================
# Output 1: camsid_specific_cleaned
# Stata: preserve; keep <columns>; collapse (first) ..., by(camsid dlr_date);
#        compress; sort dlr_date camsid; save
#
# collapse (first) on variables that are already constant within camsid x
# dlr_date by construction — so first() == any(). Use slice(1).
# =============================================================================
camsid_cols <- c(
  "camsid", "dlr_date",
  paste0("OtherQ_",        sizes),
  paste0("StateOtherQ_",   sizes),
  paste0("StateQ_",        sizes),
  paste0("DailyQ_",        sizes),
  "ndistinct_state", "ndistinct_trips"
)

camsid_specific <- landings %>%
  select(all_of(camsid_cols)) %>%
  group_by(camsid, dlr_date) %>%
  slice(1) %>%
  ungroup() %>%
  arrange(dlr_date, camsid)

saveRDS(
  camsid_specific,
  file = file.path(tile_data_dir,
                   glue("camsid_tilefish_specific_cleaned_{vintage_string}.Rds"))
)

# =============================================================================
# Helper: 7-day trailing simple moving average
# Stata: tsfill (zero-fill gaps) then tssmooth ma, window(7 0 0)
# = simple mean of [t-7, t-5, ..., t-1] with zeros for gap days.
# Denominator is always 7 because gaps are filled with 0, not NA.
# Reproduced with tidyr::complete() + zero-fill + slider::slide_dbl( .before=6, .after=0, fill = NA)
# =============================================================================

rolling_ma7 <- function(x) {
  slider::slide_dbl(x, mean, .before=6, .after=0, fill = NA)
}


# =============================================================================
# Output 2: daily_ma
# Stata: collapse (first) DailyQ* trips, by(dlr_date); tsset dlr_date;
#        tsfill; zero-fill; tssmooth ma window(7 0 0)
# =============================================================================
daily_ma <- landings %>%
  select(dlr_date, starts_with("DailyQ"), ndistinct_trips) %>%
  rename(trips = ndistinct_trips) %>%
  group_by(dlr_date) %>%
  slice(1) %>%
  ungroup() %>%
  # tsfill: expand to complete daily sequence, zero-fill gaps
  complete(dlr_date = seq(min(dlr_date), max(dlr_date), by = "day")) %>%
  mutate(across(c(starts_with("DailyQ"), trips),
                ~ replace_na(.x, 0L))) %>%
  arrange(dlr_date) %>%
  mutate(across(
    c(starts_with("DailyQ"), trips),
    rolling_ma7,
    .names = "MA7_{.col}"
  )) %>%
  select(dlr_date, starts_with("MA7_"))







saveRDS(
  daily_ma,
  file = file.path(tile_data_dir,
                   glue("daily_tilefish_ma_{vintage_string}.Rds"))
)

# =============================================================================
# Output 3: state_ma
# Stata: collapse (first) StateQ* ndistinct_state, by(dlr_date state);
#        tsset state dlr_date; tsfill; zero-fill; tssmooth ma window(7 0 0)
# tsfill on a two-way panel fills all state x date combinations.
# =============================================================================
state_ma <- landings %>%
  select(dlr_date, state, starts_with("StateQ"), ndistinct_state) %>%
  rename(state_trips = ndistinct_state) %>%
  group_by(dlr_date, state) %>%
  slice(1) %>%
  ungroup() %>%
  # tsfill: expand to all state x date combinations within the date range
  complete(
    state,
    dlr_date = seq(min(dlr_date), max(dlr_date), by = "day")
  ) %>%
  mutate(across(c(starts_with("StateQ"), state_trips),
                ~ replace_na(.x, 0L))) %>%
  arrange(state, dlr_date) %>%
  group_by(state) %>%
  mutate(across(
    c(starts_with("StateQ"), state_trips),
    rolling_ma7,
    .names = "MA7_{.col}"
  )) %>%
  ungroup() %>%
  select(dlr_date, state, starts_with("MA7_"))

saveRDS(
  state_ma,
  file = file.path(tile_data_dir,
                   glue("state_tilefish_ma_{vintage_string}.Rds"))
)
# =============================================================================
# Output 5: gear_ma
# Stata: collapse (first) gearQ* ndistinct_gear, by(dlr_date mygear);
#        tsset mygear dlr_date; tsfill; zero-fill; tssmooth ma window(7 0 0)
# =============================================================================
gear_ma <- landings %>%
  select(dlr_date, mygear, starts_with("gearQ"), ndistinct_gear) %>%
  rename(gear_trips = ndistinct_gear) %>%
  group_by(dlr_date, mygear) %>%
  slice(1) %>%
  ungroup() %>%
  complete(
    mygear,
    dlr_date = seq(min(dlr_date), max(dlr_date), by = "day")
  ) %>%
  mutate(across(c(starts_with("gearQ"), gear_trips),
                ~ replace_na(.x, 0L))) %>%
  arrange(mygear, dlr_date) %>%
  group_by(mygear) %>%
  mutate(across(
    c(starts_with("gearQ"), gear_trips),
    rolling_ma7,
    .names = "MA7_{.col}"
  )) %>%
  ungroup() %>%
  select(dlr_date, mygear, starts_with("MA7_"))

saveRDS(
  gear_ma,
  file = file.path(tile_data_dir,
                   glue("gear_tilefish_ma_{vintage_string}.Rds"))
)

