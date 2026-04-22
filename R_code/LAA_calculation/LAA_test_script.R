library(here)
library(glue)
library("conflicted")
conflicts_prefer(dplyr::filter())


here::i_am("R_code/LAA_calculation/LAA_test_script.R")
source(here("R_code/LAA_calculation/LAA_calculation.R"))

drv<-dbDriver("Oracle")
connection <- eval(nefscdb_con)

predictions_vintage<-list.files(here("data_folder","predictions"), pattern=glob2rx("out_of_sample_predictions_YRS_nocluster*.Rds"))
predictions_vintage<-gsub("out_of_sample_predictions_YRS_nocluster","",predictions_vintage)
predictions_vintage<-gsub(".Rds","",predictions_vintage)
predictions_vintage<-max(predictions_vintage)

predictions_full_location1<-here("data_folder","predictions", glue("out_of_sample_predictions_YRS_nocluster{predictions_vintage}.Rds"))
predictions_full_location2<-here("data_folder","predictions", glue("ambitious_out_of_sample_predictions_YRS_nocluster{predictions_vintage}.Rds"))


out_of_sample_predictions1<-readRDS(predictions_full_location1)
out_of_sample_predictions2<-readRDS(predictions_full_location2)


CAA<- LAA_calculation(species_itis = 167687,
                             out_of_sample_predictions = readRDS(predictions_full_location1),
                           fyr = 1989,
                           lyr = 2024,
                             connection = connection)

CAA2<- LAA_calculation(species_itis = 167687,
                      out_of_sample_predictions = readRDS(predictions_full_location2),
                      fyr = 1989,
                      lyr = 2024,
                      connection = connection)
dbDisconnect(connection)


# kind of trivial, since they are the same query.
table(CAA$CAA_OLD==CAA2$CAA_OLD)

test1<-CAA %>%
  group_by(STOCK_ABBREV, YEAR) %>%
  summarise(CAA_NEW=sum(CAA_NEW))

test2<-CAA2 %>%
  group_by(STOCK_ABBREV, YEAR) %>%
  summarise(CAA2_NEW=sum(CAA_NEW))

# these do not match and I don't know why.
verify<-test1 %>%
  left_join(test2, by=join_by(STOCK_ABBREV, YEAR)) %>%
  mutate(diff=CAA2_NEW-CAA_NEW)


table(abs(test1$CAA_NEW-test2$CAA2_NEW)<=10)

View(verify)

v2<-verify %>%
  filter(YEAR>=2013)

View(v2)



#total landings matches

oos_test1<-out_of_sample_predictions1 %>%
  summarise(landings=sum(LANDINGS_KG_CATEGORY_APPORTION))
oos_test1

oos_test2<-out_of_sample_predictions2 %>%
  summarise(landings=sum(LANDINGS_KG_CATEGORY_APPORTION))
oos_test2

# so does landings at the year-semester-STOCKABBREV to eps()
oos_test1<-out_of_sample_predictions1 %>%
  group_by(YEAR, SEMESTER, STOCK_ABBREV)%>%
  summarise(landings1=sum(LANDINGS_KG_CATEGORY_APPORTION))

oos_test2<-out_of_sample_predictions2 %>%
  group_by(YEAR, SEMESTER, STOCK_ABBREV)%>%
  summarise(landings2=sum(LANDINGS_KG_CATEGORY_APPORTION))

verify<-oos_test1 %>%
  left_join(oos_test2, by=join_by(YEAR, SEMESTER, STOCK_ABBREV)) %>%
  mutate(diff=landings1-landings2)
table(verify$diff<1e-6)


# I've got a bad join/merge going on somewhere, right?
# unpack the

species_itis = 167687
out_of_sample_predictions = readRDS(predictions_full_location1)
fyr = 1989
lyr = 2024


drv<-dbDriver("Oracle")
connection <- eval(nefscdb_con)
################################################################################
# Query StockEff
################################################################################

# Query the market categories from StockEff:
mkt.qry <- glue("select NESPP4, market_desc 
                          from stockeff.e_cf_market_c 
                          where species_itis in ({species_itis})" )
mkt.res <- fetch(dbSendQuery(connection, mkt.qry))
# Query the aggregate landings from StockEff:

comm.land.qry <- glue("select * 
                          from stockeff.mv_cf_stock_caa_land_block_o 
                          where species_itis in ({species_itis}) and year between {fyr} and {lyr}
                          and LANDINGS_KG IS NOT NULL")


comm.land.res <- fetch(dbSendQuery(connection, comm.land.qry))
# Query the landings by age and length from StockEff:
comm.land.length.age.qry <- glue("select * from stockeff.v_cf_stock_caa_num_len_age_o 
                                   where SPECIES_ITIS in ({species_itis})  and year between {fyr} and {lyr}")
comm.land.length.age.res <- fetch(dbSendQuery(connection, comm.land.length.age.qry))


out_of_sample_predictions1 <- out_of_sample_predictions1 %>% 
  mutate(has_rf_pred = 1)
## Combine the stockeff files and apportionment file


comm.land.length.age1 <- comm.land.res  %>% 
  left_join(comm.land.length.age.res, by=join_by(SPECIES_ITIS, NESPP4, YEAR, SEX_TYPE, STOCK_ABBREV, REGION_ID, BLOCK_ID)) %>% 
  left_join(mkt.res, by=join_by(NESPP4)) %>% 
  left_join(out_of_sample_predictions1, by=join_by(SPECIES_ITIS, YEAR,STOCK_ABBREV, MARKET_DESC, BLOCK_ID==SEMESTER))


#bring market desc into land.res. use that to bring in out of sample predictions
# this will break if comm.land.res is not full (zero padded) and I try to merge in something.
comm.land.length.ageAA <- comm.land.res  %>% 
  left_join(mkt.res, by=join_by(NESPP4)) %>% 
  left_join(out_of_sample_predictions1, by=join_by(SPECIES_ITIS, YEAR,STOCK_ABBREV, MARKET_DESC, BLOCK_ID==SEMESTER))


comm.land.length.ageAA2 <- comm.land.length.ageAA%>%
  filter(YEAR>2013) #%>%
  #group_by(YEAR,STOCK_ABBREV, BLOCK_ID, MARKET_DESC) 
  
  
comm.land.length.ageAA2<-comm.land.length.ageAA2 %>%
  mutate(LANDINGS_KG_ADJUSTED = case_when(
    is.na(has_rf_pred) ~ LANDINGS_KG,
    MARKET_DESC=="UNCLASSIFIED" ~ LANDINGS_KG_CATEGORY_APPORTION,
    MARKET_DESC!="UNCLASSIFIED" ~ LANDINGS_KG+LANDINGS_KG_CATEGORY_APPORTION)
  ) %>%
  arrange(YEAR,STOCK_ABBREV, BLOCK_ID, MARKET_DESC) %>%
  relocate(YEAR,STOCK_ABBREV, BLOCK_ID, MARKET_DESC,LANDINGS_KG_ADJUSTED, LANDINGS_KG,LANDINGS_KG_CATEGORY_APPORTION )


# before 2013 check


#after 2013 check
comm.land.length.ageAA2 <-comm.land.length.ageAA2 %>%
  filter(YEAR>2013) %>%
  filter(MARKET_DESC !="UNCLASSIFIED") %>%
  mutate(check=LANDINGS_KG+LANDINGS_KG_CATEGORY_APPORTION) %>%
  mutate(diff=LANDINGS_KG_ADJUSTED-check)

 
testAA2<-comm.land.length.ageAA2 %>%
  group_by(YEAR, BLOCK_ID, STOCK_ABBREV) %>%
  summarise(landings_kg_adjusted=sum(LANDINGS_KG_ADJUSTED),
            landings_kg=sum(LANDINGS_KG)) %>%
  mutate(diff=(landings_kg-landings_kg_adjusted)/1000)


#for the non-unclassifieds, landings_kg +landings_kg_category_apportion



View(comm.land.length.ageAA2)


comm.land.length.age2 <- comm.land.res  %>% 
  left_join(comm.land.length.age.res, by=join_by(SPECIES_ITIS, NESPP4, YEAR, SEX_TYPE, STOCK_ABBREV, REGION_ID, BLOCK_ID)) %>% 
  left_join(mkt.res, by=join_by(NESPP4)) %>% 
  left_join(out_of_sample_predictions2, by=join_by(SPECIES_ITIS, YEAR,STOCK_ABBREV, MARKET_DESC, BLOCK_ID==SEMESTER))


# does the 'merge' work?

TM1 <- comm.land.res  %>% 
  left_join(comm.land.length.age.res, by=join_by(SPECIES_ITIS, NESPP4, YEAR, SEX_TYPE, STOCK_ABBREV, REGION_ID, BLOCK_ID))

TM2 <- comm.land.res  %>% 
  left_join(comm.land.length.age.res, by=join_by(SPECIES_ITIS, NESPP4, YEAR, SEX_TYPE, STOCK_ABBREV, REGION_ID, BLOCK_ID)) %>%
left_join(mkt.res, by=join_by(NESPP4)) 
  
# Couple of odd things here
View(comm.land.res %>% filter(YEAR==2020 & STOCK_ABBREV=="NORTH"))

View(comm.land.res %>% filter(is.na(LANDINGS_KG)))

     