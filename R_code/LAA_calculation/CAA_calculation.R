#' @title CAA_calculation
#' @description Use Landings-at-age and discards-at-age to calculate catch-at-age
#' @param species_itis A string specifying a single itis code to query stockeff 
#' @param land.LAA The landings at age information from LAA_calculation
#' \itemize{
#'   \item{SPECIES_ITIS}
#'   \item{STOCK_ABBREV}
#'   \item{YEAR} 
#'   \item{AGE}
#'   \item{CAA_OLD}
#'   \item{CAA_NEW}
#' }
#' 
#' 
#' @param fyr first year for which you want LAA data
#' @param lyr last year for which you want LAA data
#' @param connection the connection information to access stockeff using sql 
#'
#' @return A data frame of the catch at age 
#' \itemize{
#'   \item{indices - FILL IN }
#'   \item{strata_means_summary - FILL IN}
#' }
#' @examples
#' CAA<- LAA_calculation(species_itis = '167687',
#'                             land.LAA = readRDS(here("data_folder","intermediate", glue("BSB_CAA_1.Rds"))),
#'                             fyr = 1989,
#'                             lyr = 2024)

# Library and Source Code/Functions
library(ROracle)
library(tidyverse)
library(here)
library(glue)
library("conflicted")
conflicts_prefer(dplyr::filter())


CAA_calculation <- function(species_itis = NULL,
                            LAA = NULL,
                            fyr = NULL,
                            lyr = NULL){

  if(length(species_itis)!=1){stop("Only 1 species_itis code allowed")}
  else{
    
    # Set up a new environment just for the discard-at-age DAA data:
    comdisc.env <- new.env()
    load(here("data_folder","intermediate", glue("Comm.discards.at.age.RDATA")), envir=comdisc.env)
    DAA <- comdisc.env$CAA %>% mutate(REGION = toupper(REGION))
     
    
    # Change the class of some columns of Landings-at-age for consistency
    LAA <- tibble(LAA) %>%
      mutate(
        YEAR = as.character(YEAR),
        AGE = as.character(AGE)
      ) %>% rename(REGION=STOCK_ABBREV)
    
    ## Combine DAA and LAA to obtain total commercial CAA
    DAA.LAA.comb <- DAA %>%
      bind_rows(.,
                LAA %>%
                  select(REGION, YEAR, AGE, CAA_NEW) %>%
                  rename(CAA = CAA_NEW)
      )
    
    CAA <- DAA.LAA.comb %>%
      group_by(REGION, YEAR, AGE) %>%
      summarize(CAA = sum(CAA)) %>%
      ungroup()
    
    return(CAA)
  }
}
