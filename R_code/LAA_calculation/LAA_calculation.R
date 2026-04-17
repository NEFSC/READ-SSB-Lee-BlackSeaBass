#' @title LAA_calculation
#' @description Use reapportionment information to recalculate Landings-at-age
#' @param species_itis A string specifying the itis code to query stockeff 
#' @param out_of_sample_predictions A data frame frame specifying reapportioned metric tons across market caategories
#' \itemize{
#'   \item{year}
#'   \item{semester}
#'   \item{stockarea}
#'   \item{original_market_category}
#'   \item{species_itis}
#'   \item{Market.Comb}
#'   \item{live_metric_tons}
#' }
#' @param fyr first year for which you want LAA data
#' @param lyr last year for which you want LAA data
#' @param connection the connection information to access stockeff using sql 
#'
#' @return A data frame of the landings at age 
#' \itemize{
#'   \item{indices - A matrix containing stratified mean indices by weight (WT) and numbers (NO), by year, season, and survey}
#'   \item{strata_means_summary - A matrix of strata means used in index calculations by weight (CATCH_WT) and numbers (CATCH_NO) for each year, season, and survey. Strata included in summary are specified using summary_strata argument}
#' }
#' @examples
#' CAA<- LAA_calculation(species_itis = 167687,
#'                             out_of_sample_predictions = readRDS(here("data_folder","predictions", glue("out_of_sample_predictions_YRS_nocluster{predictions_vintage}.Rds"))),
#'                             fyr = 1989,
#'                             lyr = 2024,
#'                             connection = connection)

# Library and Source Code/Functions
library(ROracle)
library(tidyverse)
library(here)
library(glue)
library("conflicted")
conflicts_prefer(dplyr::filter())


LAA_calculation <- function(species_itis = NULL,
                            out_of_sample_predictions = NULL,
                            fyr = NULL,
                            lyr = NULL,
                            connection = NULL){

  if(unique(out_of_sample_predictions$species_itis) != species_itis) print("species_itis doesn't match between requested and what provided by apportion file")
  else{
  
  # Query the market categories from StockEff:
  mkt.qry <- paste0("select NESPP4, market_desc ",
                          "from stockeff.e_cf_market_c ",
                          "where species_itis in ", species_itis, sep="")
  mkt.res <- fetch(dbSendQuery(connection, mkt.qry))
  # Query the aggregate landings from StockEff:
  comm.land.qry <- paste0("select * ",
                          "from stockeff.mv_cf_stock_caa_land_block_o ",
                          "where species_itis in ", species_itis, " and year <= ", lyr, sep="")
  comm.land.res <- fetch(dbSendQuery(connection, comm.land.qry))
  # Query the landings by age and length from StockEff:
  comm.land.length.age.qry <- paste("select * from stockeff.v_cf_stock_caa_num_len_age_o where SPECIES_ITIS='",species_itis,"'",sep='')
  comm.land.length.age.res <- fetch(dbSendQuery(connection, comm.land.length.age.qry))
  dbDisconnect(connection)
  
  # Adjust the apportionment file to match what's expected in stockeff files
  out_of_sample_predictions <- out_of_sample_predictions %>% 
    ungroup() %>%
    mutate(YEAR = as.numeric(as.character(year)),
           BLOCK_ID=as.numeric(as.character(semester)),
           STOCK_ABBREV = toupper(stockarea),
           MARKET_DESC = toupper(Market.Comb),
           MARKET_DESC = case_when (MARKET_DESC == 'MEDIUM' ~ "MEDIUM OR SELECT",
                                    MARKET_DESC != 'MEDIUM' ~ MARKET_DESC),
           MARKET_DESC_ORIG = toupper(original_market_category),
           LANDINGS_KG_CATEGORY_APPORTION = live_metric_tons*1000) %>% 
    select(YEAR,BLOCK_ID, STOCK_ABBREV,MARKET_DESC_ORIG, species_itis,MARKET_DESC,LANDINGS_KG_CATEGORY_APPORTION) 
 
  ## Combine the stockeff files and apportionment file
  comm.land.length.age <- comm.land.res  %>% 
    left_join(comm.land.length.age.res) %>% 
    left_join(mkt.res) %>% 
    left_join(out_of_sample_predictions)
  
  # Where there isn't any new landings (for some years) use the old landings
  # Where the old market category is unclassified, make that the new apportion value
  # Where the old market category isn't unclassified, add apportion value to old landings
  comm.land.length.age <- comm.land.length.age %>% 
    mutate(LANDINGS_KG_ADJUSTED = case_when(
      MARKET_DESC_ORIG == MARKET_DESC ~ LANDINGS_KG_CATEGORY_APPORTION,
      MARKET_DESC_ORIG != MARKET_DESC ~ LANDINGS_KG+LANDINGS_KG_CATEGORY_APPORTION,
      is.na(MARKET_DESC_ORIG) ~ LANDINGS_KG)
    ) 
  
  ################################################################################
  # Calculate weight at age and length
  ################################################################################
  
  ##### !! Change the LANDINGS_KG to whatever new one came out of the apportionment process!
  comm.land.length.age <- comm.land.length.age %>% mutate(SCALING_FACTOR_NEW = LANDINGS_KG_ADJUSTED/AVG_FISH_WT)
  comm.land.length.age <- comm.land.length.age %>% mutate(WT_AT_LENGTH_NEW = PROP_WT_LENGTH*SCALING_FACTOR_NEW)
  comm.land.length.age <- comm.land.length.age %>% mutate(WT_AT_AGE_LENGTH_NEW = WT_AT_LENGTH_NEW*PROP_AT_AGE)
  comm.land.length.age <- comm.land.length.age %>% mutate(NO_AT_AGE_LENGTH_NEW = WT_AT_AGE_LENGTH_NEW/IND_AVG_WT_KG)
  
  ################################################################################
  # RETURN
  ################################################################################
  
  land.CAA.OLD <- comm.land.length.age %>%
    group_by(STOCK_ABBREV, YEAR, AGE) %>%
    summarize(CAA_OLD = sum(NO_AT_AGE_LENGTH)) %>%
    ungroup()
  
  land.CAA.NEW <- comm.land.length.age %>%
    group_by(STOCK_ABBREV, YEAR, AGE) %>%
    summarize(CAA_NEW = sum(NO_AT_AGE_LENGTH_NEW)) %>%
    ungroup()
  
  land.CAA <- land.CAA.OLD %>% full_join(land.CAA.NEW)
  
  return(land.CAA)
  }
}
