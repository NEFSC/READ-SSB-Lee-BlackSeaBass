#' @title LAA_calculation
#' @description Use reapportionment information to recalculate Landings-at-age. This function calls get_stockeff()
#' @param species_itis A string specifying a single itis code to query stockeff 
#' @param out_of_sample_predictions A data frame specifying reapportioned metric tons across market categories. This dataframe must be be zero padded.  If there are 3 market categories in every year in the original data, there must be 3 in this dataframe. 
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
#' 
#' @param fyr first year for which you want LAA data
#' @param lyr last year for which you want LAA data
#' @param connection the connection information to access stockeff using sql 
#'
#' @return A data frame of the landings at age 
#' \itemize{
#'   \item{indices - FILL IN }
#'   \item{strata_means_summary - FILL IN}
#' }
#' @examples
#' CAA<- LAA_calculation(species_itis = '167687',
#'                             out_of_sample_predictions = readRDS(here("data_folder","predictions", "out_of_sample_predictions_YRS_nocluster2026-06-15.rds")),
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

source(here("R_code","LAA_calculation","get_stockeff.R"))


LAA_calculation <- function(species_itis = NULL,
                            out_of_sample_predictions = NULL,
                            fyr = NULL,
                            lyr = NULL,
                            connection = NULL){

  if(length(species_itis)!=1){stop("Only 1 species_itis code allowed")}
  else if(unique(out_of_sample_predictions$SPECIES_ITIS) != species_itis){stop("species_itis doesn't match between requested and what provided by apportion file")}
  else{

    
################################################################################
# Query StockEff
################################################################################
bsb_stockeff<-get_stockeff(species_itis=species_itis,
    fyr=fyr,
    lyr=lyr,
    connection=connection)

#unpack
comm.land.length.age.res<-bsb_stockeff$comm.land.length.age.res
mkt.res <- bsb_stockeff$mkt.res
comm.land.res<-bsb_stockeff$comm.land.res

  
  #create a marker flag on in out_of_sample_predictions to make the logic of subsequent case_when a little safer.
  out_of_sample_predictions <- out_of_sample_predictions %>% 
    mutate(has_rf_pred = 1)
  ## Combine the stockeff files and apportionment file
  comm.land.length.age <- comm.land.res  %>% 
    left_join(comm.land.length.age.res, by=join_by(SPECIES_ITIS, NESPP4, YEAR, SEX_TYPE, STOCK_ABBREV, REGION_ID, BLOCK_ID)) %>% 
    left_join(mkt.res, by=join_by(NESPP4)) %>% 
    left_join(out_of_sample_predictions, by=join_by(SPECIES_ITIS, YEAR,STOCK_ABBREV, MARKET_DESC, BLOCK_ID==SEMESTER))
  
  # CONSTRUCT LANDINGS_KG_ADJUSTED
  # is.na(has_rf_pred) Where the isn't an RF prediction, use the original landings from stockeff (LANDINGS_KG)
  # MARKET_DESC=="UNCLASSIFIED" Where the original market category is unclassified, use the new apportion value.  This is correct because 
  ##    1.  The RF model may "decline" to make a classifcation for some unclassified observations and we want to retain them as UNCLASSIFIED here. 
  ##    2.  THe RF model may classify "all" the unclassifeds. When it does, the value of LANDINGS_KG_CATEGORY_APPORTION is zero.
  # MARKET_DESC!="UNCLASSIFIED", add category apportion value to the original landings
  # MARKET_DESC_ORIG refers the original market category and MARKET_DESC is the RF classified new market category.
  
  comm.land.length.age <- comm.land.length.age %>% 
    mutate(LANDINGS_KG_ADJUSTED = case_when(
      is.na(has_rf_pred) ~ LANDINGS_KG,
      MARKET_DESC=="UNCLASSIFIED" ~ LANDINGS_KG_CATEGORY_APPORTION,
      MARKET_DESC!="UNCLASSIFIED" ~ LANDINGS_KG+LANDINGS_KG_CATEGORY_APPORTION)
    ) 
  
  ################################################################################
  # Calculate weight at age and length using LANDINGS_KG_ADJUSTED
  ################################################################################
  

  # --- Scaling chain ----------------------------------------------------
  # Disaggregate adjusted landings into numbers at age via the proportions
  # stored in the length-age view.
  #
  # SCALING_FACTOR_NEW:    total number of fish implied by landings
  #                        (LANDINGS_KG_ADJUSTED / AVG_FISH_WT) or (LANDINGS_KG / AVG_FISH_WT) 
  # WT_AT_LENGTH_NEW:      weight allocated to each length bin
  #                        (PROP_WT_LENGTH * SCALING_FACTOR_NEW)
  # WT_AT_AGE_LENGTH_NEW:  weight allocated to each age within each length bin
  #                        (WT_AT_LENGTH_NEW * PROP_AT_AGE)
  # NO_AT_AGE_LENGTH_NEW:  numbers at age within each length bin
  #                        (WT_AT_AGE_LENGTH_NEW / IND_AVG_WT_KG)
  comm.land.length.age <- comm.land.length.age %>%
	mutate(SCALING_FACTOR_NEW = LANDINGS_KG_ADJUSTED/AVG_FISH_WT,
      WT_AT_LENGTH_NEW      = PROP_WT_LENGTH * SCALING_FACTOR_NEW,
      WT_AT_AGE_LENGTH_NEW  = WT_AT_LENGTH_NEW * PROP_AT_AGE,
      NO_AT_AGE_LENGTH_NEW  = WT_AT_AGE_LENGTH_NEW / IND_AVG_WT_KG
	)
  
  ################################################################################
  # RETURN
  ################################################################################

  #################
  # Landings at Age
  #################
  land.CAA.OLD <- comm.land.length.age %>%
    group_by(SPECIES_ITIS, STOCK_ABBREV, YEAR, AGE) %>%
    summarize(CAA = sum(NO_AT_AGE_LENGTH)) %>%
    mutate(CAA_TYPE = 'Original') %>%
    ungroup()
  
  land.CAA.NEW <- comm.land.length.age %>%
    group_by(SPECIES_ITIS,STOCK_ABBREV, YEAR, AGE) %>%
    summarize(CAA = sum(NO_AT_AGE_LENGTH_NEW)) %>%
    mutate(CAA_TYPE = 'Apportioned') %>%
    ungroup()
  
  ################################################################################
  # PLOT
  ################################################################################

  
  land.CAA <- land.CAA.OLD %>% full_join(land.CAA.NEW)
  
  fyr.plot <- 2020
  land.CAA.yrs <- land.CAA %>% filter(YEAR>=fyr.plot)
  
  CAA_PLOT <- ggplot(data=land.CAA.yrs %>% 
                       mutate(CAA=CAA/1000) %>% 
                       filter(YEAR>=fyr.plot),
                     aes(x=AGE,y=CAA,col=CAA_TYPE,fill = CAA_TYPE)) + 
    geom_col(position = "identity", alpha = 0.5, linewidth=0.1) + 
    theme_bw(base_size = 9) +
    theme(
      axis.text.x      = element_text(size = 7, colour = "grey20",
                                      angle = 45, hjust = 1),
      axis.text.y      = element_text(size = 7, colour = "grey20"),
      axis.title       = element_text(size = 8),
      legend.title     = element_text(size = 7),
      legend.text      = element_text(size = 8),
      legend.key.height = unit(0.4, "cm"),
      legend.key.width  = unit(0.3, "cm"),
      legend.position  =  "bottom",
      panel.grid       = element_blank(),
      panel.border     = element_rect(colour = "grey40", linewidth = 0.5),
      plot.margin      = margin(4, 4, 4, 4, "pt")
    ) + 
  labs(
      x = "Age",
      y = "Catch-at-Age ('000s)",
      color = NULL, 
      fill = NULL
    ) +
    facet_grid(YEAR ~ STOCK_ABBREV)
  CAA_PLOT
  
  ggsave(
    filename = here("results","CAA_PLOT.pdf"),
    plot = CAA_PLOT,
    width  = 84,
    height = 84,
    units  = "mm",
    device = cairo_pdf
  )
  
  
  #################
  # Landings at Length
  #################
  
  land.CAL.OLD <- comm.land.length.age %>%
    group_by(SPECIES_ITIS, STOCK_ABBREV, YEAR, LENGTH) %>%
    summarize(CAL = sum(NO_AT_AGE_LENGTH,na.rm=T)) %>%
    mutate(CAL_TYPE = 'Original') %>%
    ungroup()
  
  land.CAL.OLD <- land.CAL.OLD %>% 
    group_by(YEAR) %>% 
    summarise(CATCH = sum(CAL)) %>%
    full_join(land.CAL.OLD) %>% 
    mutate(CAL_PROP = CAL/CATCH)
  
  land.CAL.NEW <- comm.land.length.age %>%
    group_by(SPECIES_ITIS,STOCK_ABBREV, YEAR, LENGTH) %>%
    summarize(CAL = sum(NO_AT_AGE_LENGTH_NEW,na.rm=T)) %>%
    mutate(CAL_TYPE = 'Apportioned') %>%
    ungroup()
  
  land.CAL.NEW <- land.CAL.NEW %>% 
    group_by(YEAR) %>% 
    summarise(CATCH = sum(CAL)) %>% 
    full_join(land.CAL.NEW) %>% mutate(CAL_PROP = CAL/CATCH)
  
  
  land.CAL <- land.CAL.OLD %>% 
    full_join(land.CAL.NEW)
  
    
  fyr.plot <- 2020
  land.CAL.yrs <- land.CAL %>% 
    filter(YEAR>=fyr.plot)
  
  CAL_PLOT <- ggplot(data=land.CAL %>%
                       filter(YEAR>=fyr.plot),
                     aes(x=LENGTH,y=CAL_PROP,col=CAL_TYPE,fill = CAL_TYPE)) + 
    geom_col(position = "identity", alpha = 0.5, linewidth=0.1) + 
    theme_bw(base_size = 9) +
    theme(
      axis.text.x      = element_text(size = 7, colour = "grey20",
                                      angle = 45, hjust = 1),
      axis.text.y      = element_text(size = 7, colour = "grey20"),
      axis.title       = element_text(size = 8),
      legend.title     = element_text(size = 7),
      legend.text      = element_text(size = 8),
      legend.key.height = unit(0.4, "cm"),
      legend.key.width  = unit(0.3, "cm"),
      legend.position  =  "bottom",
      panel.grid       = element_blank(),
      panel.border     = element_rect(colour = "grey40", linewidth = 0.5),
      plot.margin      = margin(4, 4, 4, 4, "pt")
    ) + 
    labs(
      x = "Length (cm)",
      y = "Catch-at-Length (proportion)",
      color = NULL, 
      fill = NULL
      ) +
    facet_grid(YEAR ~ STOCK_ABBREV)
  CAL_PLOT
  
  ggsave(
    filename = here("results","CAL_PLOT.pdf"),
    plot = CAL_PLOT,
    width  = 84,
    height = 84,
    units  = "mm",
    device = cairo_pdf
  )
#########################################
# Compute Differences in Ages and Lengths
#########################################
  
land.CAA_DIFF <- land.CAA.OLD %>% 
    rename(ORIGINAL=CAA) %>%
    select(-c(CAA_TYPE)) %>%
    full_join(land.CAA.NEW %>%
                rename(APPORTION=CAA) %>%
                select(-CAA_TYPE),
              by=c("YEAR", "STOCK_ABBREV", "SPECIES_ITIS", "AGE")) %>%
    mutate(DIFF_CAA=ORIGINAL-APPORTION)
  
  
    land.CAL_DIFF <- land.CAL.OLD %>% 
    rename(ORIGINAL=CAL,
           ORIGINAL_PROP=CAL_PROP, 
           ORGINAL_CATCH=CATCH) %>%
    select(-c(CAL_TYPE)) %>%
    full_join(land.CAL.NEW %>%
                rename(APPORTION=CAL,
                       APPORTION_PROP=CAL_PROP,
                       APPORTION_CATCH=CATCH) %>%
                select(-CAL_TYPE),
              by=c("YEAR", "STOCK_ABBREV", "SPECIES_ITIS", "LENGTH")) %>%
    mutate(Diff_Prop=ORIGINAL_PROP-APPORTION_PROP,
           DIFF_CAL=ORIGINAL-APPORTION)
  
    
    
    DIFF_AGE_PLOT <- ggplot(data=land.CAA_DIFF %>%
                                 filter(YEAR>=fyr.plot),
                               aes(x=AGE,y=DIFF_CAA/1000)) + 
      geom_col(position = "identity", alpha = 0.5, linewidth=0.1) + 
      theme_bw(base_size = 9) +
      theme(
        axis.text.x      = element_text(size = 7, colour = "grey20",
                                        angle = 45, hjust = 1),
        axis.text.y      = element_text(size = 7, colour = "grey20"),
        axis.title       = element_text(size = 8),
        legend.title     = element_text(size = 7),
        legend.text      = element_text(size = 8),
        legend.key.height = unit(0.4, "cm"),
        legend.key.width  = unit(0.3, "cm"),
        legend.position  =  "bottom",
        panel.grid       = element_blank(),
        panel.border     = element_rect(colour = "grey40", linewidth = 0.5),
        plot.margin      = margin(4, 4, 4, 4, "pt")
      ) + 
      labs(
        x = "Age Class",
        y = "Change in Catch-at-Age (000s of fish)",
        color = NULL, 
        fill = NULL
      ) +
    facet_grid(YEAR ~ STOCK_ABBREV)
    DIFF_AGE_PLOT
    
    ggsave(
      filename = here("results","DIFF_AGE_PLOT.pdf"),
      plot = DIFF_AGE_PLOT,
      width  = 84,
      height = 84,
      units  = "mm",
      device = cairo_pdf
    )
    
    
  
  DIFF_LENGTH_PLOT <- ggplot(data=land.CAL_DIFF %>%
                       filter(YEAR>=fyr.plot),
                     aes(x=LENGTH,y=DIFF_CAL/1000)) + 
    geom_col(position = "identity", alpha = 0.5, linewidth=0.1) + 
    theme_bw(base_size = 9) +
    theme(
      axis.text.x      = element_text(size = 7, colour = "grey20",
                                      angle = 45, hjust = 1),
      axis.text.y      = element_text(size = 7, colour = "grey20"),
      axis.title       = element_text(size = 8),
      legend.title     = element_text(size = 7),
      legend.text      = element_text(size = 8),
      legend.key.height = unit(0.4, "cm"),
      legend.key.width  = unit(0.3, "cm"),
      legend.position  =  "bottom",
      panel.grid       = element_blank(),
      panel.border     = element_rect(colour = "grey40", linewidth = 0.5),
      plot.margin      = margin(4, 4, 4, 4, "pt")
    ) + 
    labs(
      x = "Length (cm)",
      y = "Change in Catch-at-Length (000s of fish)",
      color = NULL, 
      fill = NULL
    ) +
    facet_grid(YEAR ~ STOCK_ABBREV)
  DIFF_LENGTH_PLOT
  
  ggsave(
    filename = here("results","DIFF_LENGTH_PLOT.pdf"),
    plot = DIFF_LENGTH_PLOT,
    width  = 84,
    height = 84,
    units  = "mm",
    device = cairo_pdf
  )
  
  # SOUTH ONLY
  S_AGE_PLOT <- ggplot(data=land.CAA_DIFF %>%
                            filter(YEAR>=2013 & STOCK_ABBREV=="SOUTH"),
                          aes(x=AGE,y=DIFF_CAA/1000)) + 
    geom_col(position = "identity", alpha = 0.5, linewidth=0.1) + 
    theme_bw(base_size = 9) +
    theme(
      axis.text.x      = element_text(size = 7, colour = "grey20",
                                      angle = 45, hjust = 1),
      axis.text.y      = element_text(size = 7, colour = "grey20"),
      axis.title       = element_text(size = 8),
      legend.title     = element_text(size = 7),
      legend.text      = element_text(size = 8),
      legend.key.height = unit(0.4, "cm"),
      legend.key.width  = unit(0.3, "cm"),
      legend.position  =  "bottom",
      panel.grid       = element_blank(),
      panel.border     = element_rect(colour = "grey40", linewidth = 0.5),
      plot.margin      = margin(4, 4, 4, 4, "pt")
    ) + 
    labs(
      x = "Age Class",
      y = "Change in Catch-at-Age (000s of fish)",
      color = NULL, 
      fill = NULL
    ) +
    facet_wrap(~YEAR)
  S_AGE_PLOT
  
  ggsave(
    filename = here("results","S_AGE_PLOT.pdf"),
    plot = S_AGE_PLOT,
    width  = 84,
    height = 84,
    units  = "mm",
    device = cairo_pdf
  )
  
  
  
  
    
  return(land.CAA)
  }
}


