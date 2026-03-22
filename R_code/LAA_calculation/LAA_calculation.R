###############################################################################
# Purpose: 	Code to apportion the unclassified market category into other MK and calculate landings at age


# Inputs:
#  - out of sample predictions from random forest
# Outputs:
#  - landings at age 

###############################################################################  

# How are the aggregate catches being divided out in stock eff right now?
# Agg to catch at length
# Catch at length to catch at age?

################################################################################
# I think I figured it out. I just need to take the comland.length.orig file,
# Replace the WT_AT_LENGTH with my "actual" values of WT_AT_LENGTH from re-apportionment
# by market category, and calculate WT_AT_AGE_LENGTH re-organize by age and do the sums to get catch-at-age

# I'm assuming the sampling data are the same, just the portions of the landings
# that should go in each market category are different

# Actually, I can just change the SCALING_FACTOR because it is the total landings for that market/region/semester
# divided by the average fish weight (AVG_FISH_WT)

# SCALING_FACTOR = TOTAL_LANDINGS / AVG_FISH_WT
# WT_AT_LENGTH = PROP_WT_LENGTH * SCALING_FACTOR
# WT_AT_AGE_LENGTH = WT_AT_LENGTH * PROP_AT_AGE
# NO_AT_AGE_LENGTH = WT_AT_AGE_LENGTH/IND_AVG_WT_KG
################################################################################

# Remove any values from the Environment
rm(list=ls())

# Library and Source Code/Functions
library(ROracle)
library(tidyverse)

fyr <- 1989
lyr <- 2024

species_itis <- c("167687")

# Enter in SQL access information to query stockeff databases
connection <- dbConnect(drv = dbDriver("Oracle"),
                        username = rstudioapi::askForPassword("Oracle user name"),
                        password = rstudioapi::askForPassword("Oracle password"),
                        dbname = rstudioapi::askForPassword("Oracle database name"))

################################################################################
# Query StockEff Aggregate Landings in MV_CF_STOCK_CAA_LAND_BLOCK_O and names of Market Categories for simplicity
################################################################################

mkt.qry <- paste0("select NESPP4, market_desc ",
                        "from stockeff.e_cf_market_c ",
                        "where species_itis in ", species_itis, sep="")
mkt.res <- fetch(dbSendQuery(connection, mkt.qry))

# THIS OBJECT HAS THE CORRECT LANDINGS BY MARKET CATEGORY
comm.land.block.qry <- paste0("select * ",
                        "from stockeff.mv_cf_stock_caa_land_block_o ",
                        "where species_itis in ", species_itis, " and year <= ", lyr, sep="")
comm.land.block.res <- fetch(dbSendQuery(connection, comm.land.block.qry))


################################################################################
# Query StockEff Landings at Length in V_CF_STOCK_CAA_NUM_LEN_AGE_O
################################################################################

land.length.qry <- paste("select * from stockeff.v_cf_stock_caa_num_len_age_o where SPECIES_ITIS='",species_itis,"'",sep='')
comland.length.orig <- fetch(dbSendQuery(connection, land.length.qry))

################################################################################
# Reapportion the aggregate landings and combine with length and age info
################################################################################

apportion <- readRDS("R_code/LAA_calculation/mockup_predictions_nocluster2026-02-11.Rds")
## Insert code here to take the results from this apportionment and put those in comland.length.orig.totals with LANDINGS_KG_NOADJ_NEW

comland.length.orig.totals <- comland.length.orig %>% left_join(comm.land.block.res)

################################################################################
# Calculate weight at age length
################################################################################

##### !! Change the LANDINGS_KG to whatever new one came out of the apportionment process!
comland.length.orig.totals <- comland.length.orig.totals %>% mutate(SCALING_FACTOR_NEW = LANDINGS_KG/AVG_FISH_WT)
comland.length.orig.totals <- comland.length.orig.totals %>% mutate(SCALING_FACTOR_DIFF = SCALING_FACTOR_NEW-SCALING_FACTOR)

comland.length.orig.totals <- comland.length.orig.totals %>% mutate(WT_AT_LENGTH_NEW = PROP_WT_LENGTH*SCALING_FACTOR_NEW)
comland.length.orig.totals <- comland.length.orig.totals %>% mutate(WT_AT_LENGTH_DIFF = WT_AT_LENGTH_NEW-WT_AT_LENGTH)

comland.length.orig.totals <- comland.length.orig.totals %>% mutate(WT_AT_AGE_LENGTH_NEW = WT_AT_LENGTH_NEW*PROP_AT_AGE)
comland.length.orig.totals <- comland.length.orig.totals %>% mutate(WT_AT_AGE_LENGTH_DIFF = WT_AT_AGE_LENGTH_NEW-WT_AT_AGE_LENGTH)

comland.length.orig.totals <- comland.length.orig.totals %>% mutate(NO_AT_AGE_LENGTH_NEW = WT_AT_AGE_LENGTH_NEW/IND_AVG_WT_KG)
comland.length.orig.totals <- comland.length.orig.totals %>% mutate(NO_AT_AGE_LENGTH_DIFF = NO_AT_AGE_LENGTH_NEW-NO_AT_AGE_LENGTH)

################################################################################
# Assemble into Landings at age 
################################################################################

land.CAA.OLD <- comland.length.orig.totals %>%
  group_by(STOCK_ABBREV, YEAR, AGE) %>%
  summarize(CAA_OLD = sum(NO_AT_AGE_LENGTH)) %>%
  ungroup()

land.CAA.NEW <- comland.length.orig.totals %>%
  group_by(STOCK_ABBREV, YEAR, AGE) %>%
  summarize(CAA_NEW = sum(NO_AT_AGE_LENGTH_NEW)) %>%
  ungroup()

land.CAA <- land.CAA.OLD %>% full_join(land.CAA.NEW)
