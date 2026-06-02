library(tidyverse)
library(conflicted)
conflicts_prefer(dplyr::filter())

#' @title get_ages
#' @description This function converts a dataframe of catch by SPECIES_ITIS, NESPP4, YEAR, SEX_TYPE, STOCK_ABBREV, REGION_ID, and BLOCK_ID
#'    and return landings-at-age (LAA) by at the SPECIES_ITIS,STOCK_ABBREV, and YEAR level.  
#' @param species_itis A single character string specifying the ITIS code. Must match
#'   SPECIES_ITIS values in out_of_sample_predictions.
#' @param comm.land.res Data frame. Aggregate landings by block. Could be returned by get_stockeff() or constructed in an analogous way.  
#' @param comm.land.length.age.res Data frame. Landings by length and age returned by get_stockeff().
#' @param landings.kg.name The name of the column that will contains landings, in kilograms in the input dataframe. 
#' @param laa.new.name The name of the new column that will contains the Landings-at-Age returned by this function. 

#'
#' @return A data frame of landings-at-age with columns:
#' \itemize{
#'   \item{STOCK_ABBREV}
#'   \item{YEAR}
#'   \item{AGE}
#'   \item{LAA — landings-at-age corresponding to comm.land.res}
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
#' land.AA <- get_ages(
#'   species_itis             = "167687",
#'   comm.land.res            = stockeff_data$comm.land.res,
#'   comm.land.length.age.res = stockeff_data$comm.land.length.age.res,
#'   landings.kg.name="LANDINGS_KG",
#'   laa.new.name = "LAA_NEW"
#' )

get_ages <- function(      species_itis             = NULL,
                           comm.land.res            = NULL,
                           comm.land.length.age.res = NULL,
                           landings.kg.name="LANDINGS_KG",
                           laa.new.name = "LAA_NEW") {

  # --- Input validation -------------------------------------------------
  if (length(species_itis) != 1) stop("Only 1 species_itis code allowed")

#  if (!all(out_of_sample_predictions$SPECIES_ITIS == species_itis)) {
#    stop("species_itis doesn't match between requested and what provided by apportion file")
#  }
  
  #Throw a helpful error message if the input dataframe is missing anything.
  required_cols <- c("SPECIES_ITIS", "NESPP4", "YEAR", "SEX_TYPE", 
                     "STOCK_ABBREV", "REGION_ID", "BLOCK_ID",landings.kg.name )
  
  missing_cols <- setdiff(required_cols, names(comm.land.res))
  
  if (length(missing_cols) > 0) {
    stop(
      "comm.land.res is missing required columns: ",
      paste(missing_cols, collapse = ", ")
    )
  }
  
  if (!is.character(landings.kg.name) || length(landings.kg.name) != 1) {
    stop("landings.kg.name must be a single character string, e.g., \"LANDINGS_KG\"")
  }
  
  # --- End Input validation -------------------------------------------------
  
  
  # --- BEGIN Output name validation -------------------------------------------------
  if (!is.character(laa.new.name) || length(laa.new.name) != 1) {
    stop("laa.new.name must be a single character string, e.g., \"LAA_NEW\"")
  }
  
  
  # --- End Input validation -------------------------------------------------
  
  

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
      SCALING_FACTOR_NEW    = !!sym(landings.kg.name) / AVG_FISH_WT,
      WT_AT_LENGTH_NEW      = PROP_WT_LENGTH * SCALING_FACTOR_NEW,
      WT_AT_AGE_LENGTH_NEW  = WT_AT_LENGTH_NEW * PROP_AT_AGE,
      NO_AT_AGE_LENGTH_NEW  = WT_AT_AGE_LENGTH_NEW / IND_AVG_WT_KG
    )

  # --- Summarize to catch-at-age ----------------------------------------
  # laa.new.name: apportioned numbers at age (NO_AT_AGE_LENGTH_NEW).
  land.AA <- comm.land.length.age %>%
    group_by(SPECIES_ITIS,STOCK_ABBREV, YEAR, AGE) %>%
    summarize(!!sym(laa.new.name) := sum(NO_AT_AGE_LENGTH_NEW, na.rm=TRUE), .groups = "drop")


  return(land.AA)
}
