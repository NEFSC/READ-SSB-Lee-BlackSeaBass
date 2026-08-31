library(tidyverse)
library(conflicted)
conflicts_prefer(dplyr::filter())

#' @title reallocate_market_categories
#' @description Join StockEff query results with RF-based market category reapportionment
#'   predictions, construct adjusted landings, and return catch-at-age (CAA) by stock and year.
#'
#' @param species_itis A single character string specifying the ITIS code. Must match
#'   SPECIES_ITIS values in out_of_sample_predictions.
#' @param mkt.res Data frame. Market category lookup (NESPP4, MARKET_DESC) returned by get_intermediate_stockeff().
#' @param comm.land.res Data frame. Aggregate landings by block returned by get_intermediate_stockeff().
#' @param comm.land.length.age.res Data frame. Landings by length and age returned by get_intermediate_stockeff().
#' @param out_of_sample_predictions Data frame. RF-model reapportioned landings in metric tons
#'   across market categories. Required columns:
#' \itemize{
#'   \item{YEAR}
#'   \item{SEMESTER}
#'   \item{STOCK_ABBREV}
#'   \item{MARKET_DESC_ORIG}
#'   \item{SPECIES_ITIS}
#'   \item{MARKET_DESC}
#'   \item{LANDINGS_KG_CATEGORY_APPORTION}
#' }
#'
#' @return A data frame of catch-at-age with columns:
#' \itemize{
#'   \item{STOCK_ABBREV}
#'   \item{YEAR}
#'   \item{AGE}
#'   \item{CAA_OLD — numbers at age from original StockEff landings}
#'   \item{CAA_NEW — numbers at age from reapportioned landings}
#' }
#'
#' @examples
#' stockeff_data <- get_intermediate_stockeff(
#'   species_itis = "167687",
#'   fyr          = 1989,
#'   lyr          = 2024,
#'   connection   = connection
#' )
#'
#' land.CAA <- reallocate_market_categories(
#'   species_itis             = "167687",
#'   mkt.res                  = stockeff_data$mkt.res,
#'   comm.land.res            = stockeff_data$comm.land.res,
#'   comm.land.length.age.res = stockeff_data$comm.land.length.age.res,
#'   out_of_sample_predictions = readRDS(here("data_folder", "predictions",
#'                                 glue("out_of_sample_predictions_YRS_nocluster{predictions_vintage}.Rds")))
#' )

reallocate_market_categories <- function(species_itis             = NULL,
                                         mkt.res                  = NULL,
                                         comm.land.res            = NULL,
                                         comm.land.length.age.res = NULL,
                                         out_of_sample_predictions = NULL) {

  # --- Input validation -------------------------------------------------
  if (length(species_itis) != 1) stop("Only 1 species_itis code allowed")

  if (!all(out_of_sample_predictions$SPECIES_ITIS == species_itis)) {
    stop("species_itis doesn't match between requested and what provided by apportion file")
  }

  # --- Marker flag ------------------------------------------------------
  # has_rf_pred distinguishes rows that matched a prediction (has_rf_pred = 1)
  # from rows that did not match (has_rf_pred = NA after left join).
  # This makes the LANDINGS_KG_ADJUSTED case_when logic explicit and safe.
  out_of_sample_predictions <- out_of_sample_predictions %>%
    mutate(has_rf_pred = 1)

  # --- Join StockEff tables and reapportionment predictions -------------
  # Join order:
  #   1. comm.land.res (aggregate landings) is the spine.
  #   2. comm.land.length.age.res adds length/age proportions.
  #   3. mkt.res adds MARKET_DESC via NESPP4.
  #   4. out_of_sample_predictions adds reapportioned landings and MARKET_DESC_ORIG.
  #      BLOCK_ID (StockEff) maps to SEMESTER (predictions).
  comm.land.length.age <- comm.land.res %>%
    left_join(comm.land.length.age.res,
              by = join_by(SPECIES_ITIS, NESPP4, YEAR, SEX_TYPE,
                           STOCK_ABBREV, REGION_ID, BLOCK_ID)) %>%
    left_join(mkt.res,
              by = join_by(NESPP4)) %>%
    left_join(out_of_sample_predictions,
              by = join_by(SPECIES_ITIS, YEAR, STOCK_ABBREV,
                           MARKET_DESC, BLOCK_ID == SEMESTER))

  # --- Construct LANDINGS_KG_ADJUSTED -----------------------------------
  # Logic (applied per row):
  #   - No RF prediction available (has_rf_pred is NA): use original StockEff landings as-is.
  #   - RF prediction exists and new market category is UNCLASSIFIED: replace with
  #     apportioned value (the original landings are unclassified and should be
  #     fully replaced by the RF-allocated quantity).
  #   - RF prediction exists and new market category is a real category: add the
  #     apportioned quantity to the existing classified landings.
  comm.land.length.age <- comm.land.length.age %>%
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
  comm.land.length.age <- comm.land.length.age %>%
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
  land.CAA <- comm.land.length.age %>%
    group_by(SPECIES_ITIS,STOCK_ABBREV, YEAR, AGE) %>%
    summarize(CAA_OLD = sum(NO_AT_AGE_LENGTH, na.rm=TRUE),
              CAA_NEW = sum(NO_AT_AGE_LENGTH_NEW, na.rm=TRUE), .groups = "drop")


  return(land.CAA)
}
