library(tidyverse)
library(conflicted)
conflicts_prefer(dplyr::filter())

#' @title reallocate_market_categories
#' @description Join StockEff query results with RF-based market category reapportionment
#'   predictions, construct adjusted landings, and return catch-at-age (CAA) by stock and year.
#'
#' @param species_itis A single character string specifying the ITIS code. Must match
#'   SPECIES_ITIS values in out_of_sample_predictions.
#' @param mkt.res Data frame. Market category lookup (NESPP4, MARKET_DESC) returned by get_stockeff().
#' @param comm.land.res Data frame. Aggregate landings by block returned by get_stockeff().
#' @param comm.land.length.age.res Data frame. Landings by length and age returned by get_stockeff().
#' @param out_of_sample_predictions Data frame. RF-model reapportioned landings in metric tons
#'   across market categories. Required columns:
#' \itemize{
#'   \item{YEAR}
#'   \item{SEMESTER}
#'   \item{STOCK_ABBREV}
#'   \item{MARKET_DESC_ORIG}
#'   \item{SPECIES_ITIS}
#'   \item{MARKET_DESC}
#'   \item{LANDINGS_KG}
#' }
#'
#' @return A data frame of catch-at-age with columns:
#' \itemize{
#'   \item{STOCK_ABBREV}
#'   \item{YEAR}
#'   \item{AGE}
#'   \item{CAA — numbers at age from original StockEff landings}
#' }
#'
#' @examples
#' stockeff_data <- get_stockeff(
#'   species_itis = "167687",
#'   fyr          = 1989,
#'   lyr          = 2024,
#'   connection   = connection
#' )
#'
#' land.CAA <- get_ages(
#'   species_itis             = "167687",
#'   comm.land.res            = stockeff_data$comm.land.res,
#'   comm.land.length.age.res = stockeff_data$comm.land.length.age.res,
#' )

get_ages <- function(      species_itis             = NULL,
                           comm.land.res            = NULL,
                           comm.land.length.age.res = NULL) {

  # --- Input validation -------------------------------------------------
  if (length(species_itis) != 1) stop("Only 1 species_itis code allowed")

#  if (!all(out_of_sample_predictions$SPECIES_ITIS == species_itis)) {
#    stop("species_itis doesn't match between requested and what provided by apportion file")
#  }


  # --- Join StockEff tables and reapportionment predictions -------------
  # Join order:
  #   1. comm.land.res (aggregate landings) is the spine.
  #   2. comm.land.length.age.res adds length/age proportions.
  #      BLOCK_ID (StockEff) maps to SEMESTER (predictions).
  comm.land.length.age <- comm.land.res %>%
    left_join(comm.land.length.age.res,
              by = join_by(SPECIES_ITIS, NESPP4, YEAR, SEX_TYPE,
                           STOCK_ABBREV, REGION_ID, BLOCK_ID))

  # --- Scaling chain ----------------------------------------------------
  # Disaggregate adjusted landings into numbers at age via the proportions
  # stored in the length-age view.
  #
  # SCALING_FACTOR_NEW:    total number of fish implied by landings
  #                        (LANDINGS_KG / AVG_FISH_WT)
  # WT_AT_LENGTH_NEW:      weight allocated to each length bin
  #                        (PROP_WT_LENGTH * SCALING_FACTOR_NEW)
  # WT_AT_AGE_LENGTH_NEW:  weight allocated to each age within each length bin
  #                        (WT_AT_LENGTH_NEW * PROP_AT_AGE)
  # NO_AT_AGE_LENGTH_NEW:  numbers at age within each length bin
  #                        (WT_AT_AGE_LENGTH_NEW / IND_AVG_WT_KG)
  comm.land.length.age <- comm.land.length.age %>%
    mutate(
      SCALING_FACTOR_NEW    = LANDINGS_KG / AVG_FISH_WT,
      WT_AT_LENGTH_NEW      = PROP_WT_LENGTH * SCALING_FACTOR_NEW,
      WT_AT_AGE_LENGTH_NEW  = WT_AT_LENGTH_NEW * PROP_AT_AGE,
      NO_AT_AGE_LENGTH_NEW  = WT_AT_AGE_LENGTH_NEW / IND_AVG_WT_KG
    )

  # --- Summarize to catch-at-age ----------------------------------------
  # CAA_orig: original StockEff numbers at age (NO_AT_AGE_LENGTH), summed
  #          across all length bins within stock/year/age.
  # CAA_NEW: reapportioned numbers at age (NO_AT_AGE_LENGTH_NEW), same grouping that comes from 
  land.CAA <- comm.land.length.age %>%
    group_by(SPECIES_ITIS,STOCK_ABBREV, YEAR, AGE) %>%
    summarize(CAA_Orig = sum(NO_AT_AGE_LENGTH, na.rm=TRUE),
              CAA_NEW = sum(NO_AT_AGE_LENGTH_NEW, na.rm=TRUE), .groups = "drop")


  return(land.CAA)
}
