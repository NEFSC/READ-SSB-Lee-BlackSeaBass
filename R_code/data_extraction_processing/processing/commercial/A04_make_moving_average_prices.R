###############################################################################
# A04_make_moving_average_prices.R
# Purpose: R translation of A04_make_moving_average_prices.do
#
# Inputs:
#   - landings_cleaned_{vintage_string}.Rds
#
# Outputs:
#   - grand_moving_average_prices_{vintage_string}.Rds
#
# Expects in environment: vintage_string, data_main
#
# Notes on rangestat equivalent:
#   Stata rangestat interval(dlr_date -14 -1) sums over the 14-day window
#   ending the day BEFORE the observation date (excludes day 0).
#   Reproduced with slider::slide_index() using .before=14, .after=-1.
###############################################################################

landings <- readRDS(
  file = here("data_folder", "main", "commercial",
              glue("landings_cleaned_{vintage_string}.Rds"))
)

# Drop Unclassified throughout this script
landings <- landings %>%
  filter(as.character(market_desc) != "Unclassified") %>%
  mutate(market_desc=fct_drop(market_desc))

# Drop rows where value is na.
landings<-landings %>%
  filter(!is.na(valueR_CPI)) 


# make a placeholder dataframe (combined_prices).  
market_cats<-levels(landings$market_desc)

states<-levels(landings$state)
start_date<-min(landings$dlr_date)
end_date<-max(landings$dlr_date)

combined_prices <- expand_grid(
  state = states,
  market_desc=market_cats,
  dlr_date  = seq(as.Date(start_date), as.Date(end_date), by = "day")
)








# Subregion assignment -- this is based on the hedonic model results.  prices tend to be regional (ish)
# CT+NY -> CTNY; DE/MD/VA/NC/SC -> DELMARVAC; MA/NH/ME -> MA_N
# NJ by itself.
# RI by itself.

# Add FL to the southern. Add CN to the northern. Add PA to NJ
landings <- landings %>%
  mutate(
    subregion = case_when(
      state %in% c("CT", "NY")                   ~ "CTNY",
      state %in% c("DE", "MD", "VA", "NC", "SC", "FL")  ~ "DELMARVAC",
      state %in% c("MA", "NH", "ME", "CN", "VT")             ~ "MA_N",
      state %in% c("NJ", "PA")                         ~ "NJ",
      state %in% c("RI")                         ~ "RI",
      TRUE                                          ~ NA
    )
  ) 

# Add subregion to the panel.
combined_prices<- combined_prices %>%
  mutate(
    subregion = case_when(
      state %in% c("CT", "NY")                   ~ "CTNY",
      state %in% c("DE", "MD", "VA", "NC", "SC", "FL")  ~ "DELMARVAC",
      state %in% c("MA", "NH", "ME", "CN", "VT")             ~ "MA_N",
      state %in% c("NJ", "PA")                         ~ "NJ",
      state %in% c("RI")                         ~ "RI",
      TRUE                                          ~ NA
    )
  ) 

# =============================================================================
# Block 1: Annual state price adjustment
# Computed on Large, Jumbo, Medium only. There's just not much smalls and Unclassified.
# state_multiplier = state average divided coastwide average 
# there will be some state-year combinations without an adjustment factor.
# =============================================================================
state_adjust <- landings %>%
  filter(as.character(market_desc) %in% c("Large", "Jumbo", "Medium")) %>%
  filter(!is.na(valueR_CPI)) %>%
  group_by(year, state) %>%
  summarise(
    valueR_CPI = sum(valueR_CPI),
    lndlb      = sum(lndlb),
    .groups    = "drop"
  ) %>%
  group_by(year) %>%
  mutate(
    tv       = sum(valueR_CPI),
    tl       = sum(lndlb),
    price    = valueR_CPI / lndlb, #state-year level average price 
    pricebar = tv / tl,            # year level average price
    # state_multiplier: state average divided coastwide average 
    # mutiply the coastwide average to get the state  price
    state_multiplier = price/pricebar
  ) %>%
  ungroup() %>%
  select(year, state, state_multiplier)

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
      .before = 15, .after = -1
    ),
    lndlb_sum        = slide_index_dbl(
      lndlb, dlr_date, sum, na.rm = TRUE,
      .before = 15, .after = -1
    ),
    valueR_CPI_count = slide_index_int(
      !is.na(valueR_CPI), dlr_date, sum,
      .before = 15, .after = -1
    ),
    coastwide_ma14price = valueR_CPI_sum / lndlb_sum
  ) %>%
  ungroup() %>%
  select(dlr_date, market_desc, coastwide_ma14price)

#First day min(dlr_date) becomes NaN

# =============================================================================
# Block 3: Subregion-level 14-day trailing moving average price
# Suppressed if <= 5 days of data in the 14-day window.
# Compute a moving average price for subregions  
# =============================================================================
daily_by_subregion <- landings %>%
  group_by(dlr_date, subregion, market_desc) %>%
  summarise(
    valueR_CPI = sum(valueR_CPI),
    lndlb      = sum(lndlb),
    .groups    = "drop"
  ) %>%
  # tsfill equivalent: complete all subregion x market_desc x date combinations
  complete(
    subregion, market_desc,
    dlr_date = seq(min(dlr_date), max(dlr_date), by = "day")
  ) %>%
  arrange(subregion, market_desc, dlr_date)

subregionprice <- daily_by_subregion %>%
  group_by(subregion, market_desc) %>%
  mutate(
    valueR_CPI_sum   = slide_index_dbl(
      valueR_CPI, dlr_date, sum, na.rm = TRUE,
      .before = 14, .after = -1
    ),
    lndlb_sum        = slide_index_dbl(
      lndlb, dlr_date, sum, na.rm = TRUE,
      .before = 14, .after = -1
    ),
    valueR_CPI_count = slide_index_int(
      !is.na(valueR_CPI), dlr_date, sum,
      .before = 14, .after = -1
    ),
    ma14subregionprice = valueR_CPI_sum / lndlb_sum,
    # Suppress if 5 or fewer days of data in the 14-day window
    ma14subregionprice = if_else(valueR_CPI_count <= 5,
                                 NA_real_, ma14subregionprice)
  ) %>%
  ungroup() %>%
  select(dlr_date, market_desc, subregion, ma14subregionprice)

# =============================================================================
# Block 4: State-level 14-day trailing moving average price
# Drop FL(12), PA(42), SC(45), ME(23), NH(33) before computing.
# There's so little info there anyway. I'd prefer to use regional prices
# Stata drops by numeric state code; match on state_string here.
# Suppressed if <= 3 days of data in the 14-day window.
# =============================================================================
drop_states <- c("FL", "PA", "SC", "ME", "NH")

daily_by_state <- landings %>%
  filter(!state_string %in% drop_states) %>%
  group_by(dlr_date, state, subregion, market_desc) %>%
  summarise(
    valueR_CPI = sum(valueR_CPI),
    lndlb      = sum(lndlb),
    .groups    = "drop"
  ) %>%
  complete(
    nesting(state, subregion), market_desc,
    dlr_date = seq(min(dlr_date), max(dlr_date), by = "day")
  ) %>%
  # fill subregion into tsfill-created rows (Stata: fillmissing subregion, with(any))
  group_by(state, market_desc) %>%
  fill(subregion, .direction = "downup") %>%
  ungroup() %>%
  arrange(state, market_desc, dlr_date)

state_prices <- daily_by_state %>%
  group_by(state, market_desc) %>%
  mutate(
    valueR_CPI_sum   = slide_index_dbl(
      valueR_CPI, dlr_date, sum, na.rm = TRUE,
      .before = 14, .after = -1
    ),
    lndlb_sum        = slide_index_dbl(
      lndlb, dlr_date, sum, na.rm = TRUE,
      .before = 14, .after = -1
    ),
    valueR_CPI_count = slide_index_int(
      !is.na(valueR_CPI), dlr_date, sum,
      .before = 14, .after = -1
    ),
    ma14stateprice = valueR_CPI_sum / lndlb_sum,
    # Suppress if 3 or fewer days of data in the 14-day window
    ma14stateprice = if_else(valueR_CPI_count <= 3,
                             NA_real_, ma14stateprice)
  ) %>%
  ungroup() %>%
  select(dlr_date, market_desc, state, subregion, ma14stateprice)

# =============================================================================
# Block 5: Combine all moving average prices
# Merge region-wide and subregion prices onto state-level frame.
# Stata asserts all three merges are _merge==3.
# =============================================================================

# add ma14stateprice to dataframe
combined_prices <- combined_prices %>%
  left_join(state_prices,
  by=c("dlr_date", "state", "subregion", "market_desc"), relationship="one-to-one")

# add coastwide price and subregion moving average prices to dataframe
combined_prices <- combined_prices %>%
  left_join(moving_average_prices,
            by = c("dlr_date", "market_desc")) #%>%
#  left_join(subregionprice,
#            by = c("dlr_date", "subregion", "market_desc"))

combined_prices<-combined_prices %>%
  filter(dlr_date>="1996-01-03")

# Assert all rows have region-wide price (should always exist post-tsfill)
stopifnot(
  "ma14price merge: unexpected missing values" =
    !anyNA(combined_prices$coastwide_ma14price)
)

# Merge state adjustment (m:1 on year x state)
combined_prices <- combined_prices %>%
  mutate(year = lubridate::year(dlr_date)) %>%
  left_join(state_adjust, by = c("year", "state"))

# =============================================================================
# Impute missing state prices
# imp_ma14stateprice = ma14stateprice if available,
#                    = ma14price - state_adjust otherwise
# =============================================================================
combined_prices <- combined_prices %>%
  mutate(
    imp_ma14stateprice = if_else(
      is.na(ma14stateprice),
      coastwide_ma14price * state_multiplier,
      ma14stateprice
    )
  )

# Some states don't have a multipler, in that case just use the region price 
combined_prices <- combined_prices %>%
  mutate(imp_ma14stateprice = case_when(
         state  %in% c("CN","CT", "DE", "FL", "ME", "NH", "PA", "SC", "VT") & is.na(imp_ma14stateprice) & is.na(state_multiplier) ~ coastwide_ma14price,
         TRUE ~ imp_ma14stateprice)
  )







# =============================================================================
# Final: trim date range, reshape wide by market_desc, rename
# =============================================================================
grand_ma_prices <- combined_prices %>%
  select(dlr_date, market_desc, state, imp_ma14stateprice) %>%
  pivot_wider(
    id_cols     = c(dlr_date, state),
    names_from  = market_desc,
    values_from = imp_ma14stateprice
  ) %>%
  rename(
    JumboMA14price  = Jumbo,
    LargeMA14price  = Large,
    MediumMA14price = Medium,
    SmallMA14price  = Small
  ) %>%
  arrange(dlr_date, state)

# dataset should have no missing values
stopifnot(
    !anyNA(grand_ma_prices)
)

saveRDS(
  grand_ma_prices,
  file = here("data_folder", "main", "commercial",
              glue("grand_moving_average_prices_{vintage_string}.Rds"))
)
