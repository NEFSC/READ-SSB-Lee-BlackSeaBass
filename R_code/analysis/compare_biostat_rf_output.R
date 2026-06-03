species_itis = '167687'
fyr = 1989
lyr = 2025
connection = db1

comm.land.qry <- glue("select * 
                          from stockeff.mv_cf_stock_caa_land_block_o 
                          where species_itis in ({species_itis}) and year between {fyr} and {lyr}
                          and LANDINGS_KG IS NOT NULL")



comm.land.res <- fetch(dbSendQuery(connection, comm.land.qry))
out_of_sample <- readRDS("data_folder/predictions/ambitious_out_of_sample_predictions_YRS_nocluster2026-03-16.RDS")


comm.land.res.clean <- comm.land.res %>% left_join(mkt.res) %>% select(YEAR,STOCK_ABBREV,MARKET_DESC,BLOCK_ID,LANDINGS_PROP) %>% rename(LANDINGS_KG_PROP_BIO = LANDINGS_PROP) %>% rename(SEMESTER=BLOCK_ID) 
out_of_sample.clean <- out_of_sample %>% select(YEAR,SEMESTER,STOCK_ABBREV,MARKET_DESC,LANDINGS_KG_PROP_RF)

compare_BIOSTAT_RF <- comm.land.res.clean %>% 
                      full_join(out_of_sample.clean) %>% 
                      filter(MARKET_DESC != "UNCLASSIFIED") %>% 
                      mutate(DIFF = LANDINGS_KG_PROP_RF-LANDINGS_KG_PROP_BIO) %>% 
                      arrange(STOCK_ABBREV,YEAR) %>% 
                      filter(!is.na(DIFF)) 

compare_BIOSTAT_RF$YEAR <- as.factor(compare_BIOSTAT_RF$YEAR)

(compare_BIOSTAT_RF_points <- ggplot(compare_BIOSTAT_RF,aes(x=YEAR,y=DIFF,color=MARKET_DESC)) + geom_point() + facet_grid(STOCK_ABBREV~SEMESTER) + theme_light())

write.csv(compare_BIOSTAT_RF,'C:/Users/emily.liljestrand/Downloads/compare_BIOSTAT_RF.csv')


