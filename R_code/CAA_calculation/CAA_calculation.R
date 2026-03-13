###############################################################################
# Purpose: 	Code to apportion the unclassified market category into other MK and calculate catch at age


# Inputs:
#  - out of sample predictions from random forest
# Outputs:
#  - catch at age 

###############################################################################  

# How are the aggregate catches being divided out in stock eff right now?
# Agg to catch at length
# Catch at length to catch at age?

# Remove any values from the Environment
rm(list=ls())

# Library and Source Code/Functions
library(ROracle)
library(tidyverse)
source("C:/Users/emily.liljestrand/Documents/GitHub/BSB.2025.MT/User.Specification.Files/Oracle_User_Data.R")

fyr <- 1989
lyr <- 2024

species <- c('335')
species_itis <- c("167687")
names(species) <- c('BSB')

# Query StockEff Landings in I_CF_STOCK_DATA_ADJ_LAND_O

mkt.qry <- paste0("select NESPP4, market_desc ",
                        "from stockeff_pre_prod.e_cf_market_c ",
                        "where species_itis in ", species_itis, sep="")

mkt.res <- fetch(dbSendQuery(db1, mkt.qry))

comm.land.qry <- paste0("select year, stock_abbrev, area, month_group, nespp4, month, state_postal, port_name, gear_group, negear, gearnm, data_source, landings_kg_orig, landings_kg_adj ",
                        "from stockeff_pre_prod.i_cf_stock_data_adj_land_o ",
                        "where species_itis in ", species_itis, " and year <= ", lyr,
                        " order by year, stock_abbrev, month_group", sep="")

comm.land.res <- fetch(dbSendQuery(db1, comm.land.qry))

agg.landings.north.MK <- comm.land.res %>% group_by(YEAR,STOCK_ABBREV,NESPP4) %>% summarise(totcatch = sum(LANDINGS_KG_ADJ,na.rm = T)) %>% filter(STOCK_ABBREV=='NORTH') %>% left_join(mkt.res)
agg.landings.south.MK <- comm.land.res %>% group_by(YEAR,STOCK_ABBREV,NESPP4) %>% summarise(totcatch = sum(LANDINGS_KG_ADJ,na.rm = T)) %>% filter(STOCK_ABBREV=='SOUTH') %>% left_join(mkt.res)
