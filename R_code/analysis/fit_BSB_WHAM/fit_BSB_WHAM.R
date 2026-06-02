###############################################################################
# Purpose: 	Fit a Black Sea Bass WHAM assessment akin to that from the 2023RT, 2024MT, 2025MT assessments

# I'm taking the output from a random forest model that predicts market category
# from the unclassified market category, using LAA_calculation and CAA_calculation
# to find the total catch at age, replacing those in the 
# 

# Inputs:
#  - BSB_2025MT_Input.rds (data file to run WHAM model)
#  - Reapportioned catch-at-age (from LAA_calculation.R and CAA_calculation.R)

# Outputs:
#  - Fitted BSB WHAM Assessment Model
#  - Comparison of Fitted BSB WHAM Assessment Model against actual assessment model
###############################################################################  


###############################################################################  
###############################################################################  
# Model setup
###############################################################################  
###############################################################################  

# How best to install this particular version of WHAM (you need to replace the path with your local path)
# remotes::install_github("timjmiller/wham@e7bd16e", dependencies=TRUE, ref = "lab", lib = "C:/Users/emily.liljestrand/AppData/Local/R/win-library/4.4/wham_2.1.0.9005", INSTALL_opts=c("--no-multiarch"))

# Remove all other variables:
rm(list=ls())

# Load necessary libraries and functions:
library(wham, lib.loc = "C:/Users/emily.liljestrand/AppData/Local/R/win-library/4.4/wham_2.1.0.9005")
library(ROracle)
library(DBI)
library(here)
library(glue)
# Source all the functions in LAA_calculation file:
r_files <- list.files(path = "R_code/LAA_calculation/", pattern = "\\.[rR]$", full.names = TRUE)
lapply(r_files, source)

# Read in the true BSB data:
BSB_2025MT_Input <- readRDS("data_folder/assessment/BSB_2025MT_Input.rds")
#BSB_2025MT_Input$data$catch_paa[1,,] # Proportions at age commercial catch in North
#BSB_2025MT_Input$data$catch_paa[3,,] # Proportions at age commercial catch in South

###############################################################################  
###############################################################################  
# Reapportion catch data for Black Sea Bass
###############################################################################  
###############################################################################  

# Establish connection to Oracle, necessary for querying BSB landings:
connection <- dbConnect(drv = dbDriver("Oracle"),
                        username = rstudioapi::askForPassword("Oracle user name"),
                        password = rstudioapi::askForPassword("Oracle password"),
                        dbname = rstudioapi::askForPassword("Oracle database name"))

# Finds the name of the correct "out of sample prediction" file and finds their location:
predictions_vintage<-list.files(here("data_folder","predictions"), pattern=glob2rx("out_of_sample_predictions_YRS_nocluster*.Rds"))
predictions_vintage<-gsub("out_of_sample_predictions_YRS_nocluster","",predictions_vintage)
predictions_vintage<-gsub(".Rds","",predictions_vintage)

# reallocate_market_categories, first querying stock efficiency data then getting the landings at age
stockeff_data <- get_stockeff(
  species_itis = "167687",
  fyr          = 1989,
  lyr          = 2024,
  connection   = connection
)

LAA <- reallocate_market_categories(
  species_itis             = "167687",
  mkt.res                  = stockeff_data$mkt.res,
  comm.land.res            = stockeff_data$comm.land.res,
  comm.land.length.age.res = stockeff_data$comm.land.length.age.res,
  out_of_sample_predictions = readRDS(here("data_folder", "predictions",
                                           glue("out_of_sample_predictions_YRS_nocluster{predictions_vintage}.Rds")))
)

# Pull the discard data and combine with landings. Catch = Landings + Discards
CAA <- CAA_calculation(species_itis = 167687,
                        LAA=LAA,
                        fyr = 1989,
                        lyr = 2024)

# Turn the current output into proportions at age:
CAA.wide <- CAA %>%
  pivot_wider(names_from=AGE, values_from=CAA, values_fill=0)

CAA.prop <- CAA.wide %>% select(REGION,YEAR,c(as.character(1:8))) %>%
  rowwise() %>%
  mutate(across(c(as.character(1:8)), ~ .x / sum(c_across(c(as.character(1:8)))))) %>%
  ungroup()

###############################################################################  
###############################################################################  
# Fit the BSB WHAM model
###############################################################################  
###############################################################################
# Fit the baseline model from the baseline input file if there isn't a model fit file already:
# fit <- fit_wham(BSB_2025MT_Input, do.sdrep = T, do.osa = T, do.retro = T, do.brps = T)
# saveRDS(fit,file="data_folder/assessment/BSB_2025MT_Fit.rds")

# Replace the catch proportions data:
BSB_2025MT_Input$data$catch_paa[1,,] <- CAA1.prop %>% filter(REGION=='NORTH') %>% select(3:last_col()) %>% as.matrix()
BSB_2025MT_Input$data$catch_paa[3,,] <- CAA1.prop %>% filter(REGION=='SOUTH') %>% select(3:last_col()) %>% as.matrix()

# Try to fit without any bells and whistles:
# tfit <- fit_wham(BSB_2025MT_Input, do.sdrep = T, do.osa = F, do.retro = T, do.brps = FALSE)

fit <- fit_wham(BSB_2025MT_Input, do.sdrep = T, do.osa = T, do.retro = T, do.brps = T)
saveRDS(fit,file="data_folder/assessment/BSB_Apportion_Fit.rds")

###############################################################################  
###############################################################################  
# Compare against current BSB model
###############################################################################  
############################################################################### 

BSB_2025MT <- readRDS("data_folder/assessment/BSB_2025MT_Fit.rds")
BSB_Reapportio1 <- readRDS("data_folder/assessment/BSB_Apportion_Fit.rds")

mods <- list(BSB_2025MT=BSB_2025MT,BSB_Reapportion = BSB_Reapportion)
compare_wham_models(mods,fdir = file.path("R_code/analysis/fit_BSB_WHAM"),calc.aic = FALSE, do.table=F)
