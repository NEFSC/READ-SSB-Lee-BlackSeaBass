

library(ROracle)
library(tidyverse)
library(here)
library(glue)
library("conflicted")
conflicts_prefer(dplyr::filter())



species_itis = '167687'
out_of_sample_predictions = readRDS(here("data_folder","predictions", "out_of_sample_predictions_YRS_nocluster2026-06-15.rds"))
fyr=1989
lyr=2024
#connection=db1

drv<-dbDriver("Oracle")
connection<-eval(nefscdb_con)


# Testing procedure for refactor:
#   #
source(here("R_code","LAA_calculation","LAA_calculation_BSB_old.R"))
# 
# 
# 
 CAA_OLD<- LAA_calculation_old(species_itis = '167687',
                       out_of_sample_predictions = out_of_sample_predictions,
                       fyr = 2013,
                       lyr = 2024,
                       connection = connection)
 

source(here("R_code","LAA_calculation","get_intermediate_stockeff.R"))
source(here("R_code","LAA_calculation","LAA_calculation_BSB.R"))


CAA_SOLO_NEW<- LAA_calculation(species_itis = '167687',
                          out_of_sample_predictions = out_of_sample_predictions,
                          fyr = 2013,
                          lyr = 2024,
                          connection = connection,
                          sumflag="solo",
                          plotstub="new")

CAA_NEW<- LAA_calculation(species_itis = '167687',
                               out_of_sample_predictions = out_of_sample_predictions,
                               fyr = 2013,
                               lyr = 2024,
                               connection = connection,
                               sumflag="sum",
                               plotstub="new")



#CAA_OLD and CAA_NEW should be the same thing

identical(CAA_NEW, CAA_OLD)
