###############################################################################
# A04_make_moving_average_tilefish_prices.R
# Purpose:Compute coastiwde average tilefish prices
#
# Inputs:
#   - tilefish_landings_cleaned_{vintage_string}.Rds
#
# Outputs:
#   - tile_grand_moving_average_prices_{vintage_string}.Rds
#
# Expects in environment: vintage_string, data_main
#
# Notes on rangestat equivalent:
#   Stata rangestat interval(dlr_date -14 -1) sums over the 14-day window
#   ending the day BEFORE the observation date (excludes day 0).
#   Reproduced with slider::slide_index() using .before=14, .after=-1.
###############################################################################



landings <- readRDS(
  file = here("data_folder","main","tilefish",
              glue("tilefish_landings_cleaned_{vintage_string}.Rds"))
)

landings <- landings %>%
  filter(market_desc %in% c("Large","Medium", "Small Kitten")) %>%
  mutate(market_desc=fct_drop(market_desc))

# Drop rows where value is na.
landings<-landings %>%
  filter(!is.na(valueR_CPI)) 


# make a placeholder dataframe (combined_prices).  
market_cats<-levels(landings$market_desc)

start_date<-min(landings$dlr_date)
end_date<-max(landings$dlr_date)

combined_prices <- expand_grid(
  market_desc=market_cats,
  dlr_date  = seq(as.Date(start_date), as.Date(end_date), by = "day")
)






# =============================================================================
# Block 2: Region-wide 14-day trailing moving average price by market_desc
# Stata: collapse sum(valueR_CPI) sum(lndlb) by(dlr_date market_desc);
#        tsset market_desc dlr_date; tsfill;
#        rangestat (sum) valueR_CPI lndlb (count) valueR_CPI,
#                  interval(dlr_date -14 -1) by(market_desc)
#        ma14price = valueR_CPI_sum / lndlb_sum
#
# slider::slide_index() with .before=14, .after=-1 excludes day 0,
# matching Stata's interval specification exactly.
# =============================================================================

# =============================================================================
# Block 2A: 
# A full timeseries dataset of daily value and landings, by market category. 
# Zero filled with "complete"
# =============================================================================

daily_by_market <- landings %>%
  group_by(dlr_date, market_desc) %>%
  summarise(
    valueR_CPI = sum(valueR_CPI),
    lndlb      = sum(lndlb),
    .groups    = "drop"
  ) %>%
  # tsfill: complete all market_desc x date combinations
  complete(
    market_desc,
    dlr_date = seq(min(dlr_date), max(dlr_date), by = "day"),
    fill=list(valueR_CPI=0,lndlb=0)) %>%
  arrange(market_desc, dlr_date)



# =============================================================================
# Block 2B: 
# by market category, compute moving sums of value_CPI and lndlb    
# also create a count variable. 
# Compute a moving average price for the entire region 
# =============================================================================

moving_average_prices <- daily_by_market %>%
  group_by(market_desc) %>%
  mutate(
    valueR_CPI_sum   = slide_index_dbl(
      valueR_CPI, dlr_date, sum, na.rm = TRUE,
      .before = 30, .after = -1
    ),
    lndlb_sum        = slide_index_dbl(
      lndlb, dlr_date, sum, na.rm = TRUE,
      .before = 30, .after = -1
    ),
    valueR_CPI_count = slide_index_int(
      !is.na(valueR_CPI), dlr_date, sum,
      .before = 30, .after = -1
    ),
    coastwide_ma30price = valueR_CPI_sum / lndlb_sum
  ) %>%
  ungroup() %>%
  select(dlr_date, market_desc, coastwide_ma30price)

#First day min(dlr_date) becomes NaN

# =============================================================================
# Block 5: Combine all moving average prices
# Merge region-wide  prices onto state-level frame.
# Stata asserts all three merges are _merge==3.
# =============================================================================

# add coastwide price  moving average prices to dataframe
combined_prices <- combined_prices %>%
  left_join(moving_average_prices,
            by = c("dlr_date", "market_desc")) #%>%

combined_prices<-combined_prices %>%
  filter(dlr_date>="2001-01-01")

# Assert all rows have region-wide price (should always exist post-tsfill)
stopifnot(
  "ma30price merge: unexpected missing values" =
    !anyNA(combined_prices$coastwide_ma30price)
)







# =============================================================================
# Final: trim date range, reshape wide by market_desc, rename
# =============================================================================
grand_ma_prices <- combined_prices %>%
  select(dlr_date, market_desc, coastwide_ma30price) %>%
  pivot_wider(
    id_cols     = c(dlr_date),
    names_from  = market_desc,
    values_from = coastwide_ma30price
  ) %>%
  rename(
    LargeMA30price  = Large,
    MediumMA30price = Medium,
    SmallKittenMA30price  = `Small Kitten`
  ) %>%
  arrange(dlr_date)

# dataset should have no missing values
stopifnot(
    !anyNA(grand_ma_prices)
)

saveRDS(
  grand_ma_prices,
  file = here("data_folder", "main", "tilefish",
              glue("tile_grand_moving_average_prices_{vintage_string}.Rds"))
)
