library(ROracle)
library(glue)
library(conflicted)
conflicts_prefer(dplyr::filter())

#' @title get_intermediate_stockeff
#' @description Query three intermediate StockEff tables needed for landings-at-age calculation:
#'   market category lookup, aggregate landings by block, and landings by length and age.
#'
#' @param species_itis A single character string specifying the ITIS code to query.
#' @param fyr Integer. First year of the query range (inclusive).
#' @param lyr Integer. Last year of the query range (inclusive).
#' @param connection A database connection object created by ROracle::dbConnect().
#'   The caller is responsible for opening and closing the connection.
#'
#' @return A named list of three data frames:
#' \itemize{
#'   \item{mkt.res — Market category lookup: NESPP4, MARKET_DESC}
#'   \item{comm.land.res — Aggregate landings by block: all columns from
#'     stockeff.mv_cf_stock_caa_land_block_o, filtered to fyr–lyr, non-null LANDINGS_KG}
#'   \item{comm.land.length.age.res — Landings by length and age: all columns from
#'     stockeff.v_cf_stock_caa_num_len_age_o, filtered to fyr–lyr}
#' }
#'
#' @examples
#' stockeff_data <- get_stockeff(
#'   species_itis = "167687",
#'   fyr          = 1989,
#'   lyr          = 2024,
#'   connection   = connection
#' )
#' mkt.res                <- stockeff_data$mkt.res
#' comm.land.res          <- stockeff_data$comm.land.res
#' comm.land.length.age.res <- stockeff_data$comm.land.length.age.res

get_intermediate_stockeff <- function(species_itis = NULL,
                         fyr          = NULL,
                         lyr          = NULL,
                         connection   = NULL) {
  
  if (length(species_itis) != 1) stop("Only 1 species_itis code allowed")
  
  # --- Market category lookup -------------------------------------------
  # Returns NESPP4-to-MARKET_DESC mapping for the species.
  mkt.qry <- glue("select NESPP4, market_desc
                   from stockeff.e_cf_market_c
                   where species_itis in ({species_itis})")
  
  mkt.res <- fetch(dbSendQuery(connection, mkt.qry))
  
  # --- Aggregate landings by block --------------------------------------
  # mv_cf_stock_caa_land_block_o: one row per stock/year/semester/market category.
  # Filtered to the requested year range; rows with null LANDINGS_KG excluded.
  comm.land.qry <- glue("select * 
                          from stockeff.mv_cf_stock_caa_land_block_o 
                          where species_itis in ({species_itis}) 
                          and year between {fyr} and {lyr}
                          and LANDINGS_KG IS NOT NULL")
  
  comm.land.res <- fetch(dbSendQuery(connection, comm.land.qry))
  
    # If there's nothing there, then its likely the stock is in PREproduction, not production in stockeff:
  if(dim(comm.land.res)[1]==0){
    comm.land.qry <- glue("select * 
                          from stockeff_pre_prod.mv_cf_stock_caa_land_block_o 
                          where species_itis in ({species_itis}) and year between {fyr} and {lyr}
                          and LANDINGS_KG IS NOT NULL")
    
    
    
    comm.land.res <- fetch(dbSendQuery(connection, comm.land.qry))
  }

  
  
  # --- Query Landings by length and age from StockEff---------------------------------------
  # v_cf_stock_caa_num_len_age_o: proportions at length and age used to
  # convert landings into numbers at age.
  comm.land.length.age.qry <- glue("select *
                                    from stockeff.v_cf_stock_caa_num_len_age_o
                                    where SPECIES_ITIS in ({species_itis})
                                      and year between {fyr} and {lyr}")
  
  comm.land.length.age.res <- fetch(dbSendQuery(connection, comm.land.length.age.qry))
 
# If there's nothing there, then its likely the stock is in PREproduction, not production in stockeff:
 
    if(dim(comm.land.length.age.res)[1]==0){
    comm.land.length.age.qry <- glue("select * from stockeff_pre_prod.v_cf_stock_caa_num_len_age_o 
                                   where SPECIES_ITIS in ({species_itis})  and year between {fyr} and {lyr}")
    comm.land.length.age.res <- fetch(dbSendQuery(connection, comm.land.length.age.qry))
  }

  
  # Return all three frames as a named list.
  # The caller manages dbDisconnect().
  return(list(
    mkt.res                  = mkt.res,
    comm.land.res            = comm.land.res,
    comm.land.length.age.res = comm.land.length.age.res
  ))
}
