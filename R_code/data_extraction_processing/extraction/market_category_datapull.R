library("ROracle")
library("glue")
library("tidyverse")

library("here")

here::i_am("R_code/data_extraction_processing/extraction/market_category_datapull.R")

vintage_string<-format(Sys.Date())

year_start<-2020
year_end<-2024

drv<-dbDriver("Oracle")


fmp_query<-glue("select itis_tsn, itis_sci_name, itis_name, dlr_nespp3 as nespp3, fmp, council from cams_garfo.cfg_itis 
                where council is not NULL")

nova_conn<-dbConnect(drv, id, password=novapw, dbname=nefscusers.connect.string)

grade_query<-glue("select distinct species_itis as itis_tsn, grade_code, grade_desc from nefsc_garfo.scbi_species_itis_ne order by itis_tsn, grade_code")

markets_query<-glue("select distinct species_itis as itis_tsn, market_code, market_desc from nefsc_garfo.scbi_species_itis_ne order by itis_tsn, market_code")

landings_query<-glue("select camsid, cl.itis_tsn, dlr_mkt, dlr_grade, lndlb, value,itis.itis_sci_name, itis.fmp, itis.council from cams_land cl
    left join cams_garfo.cfg_itis itis on cl.itis_tsn=itis.itis_tsn
    where year between {year_start} and {year_end} and itis.council is not null
    order by cl.itis_tsn, itis_sci_name, fmp, council, year ")

grade_cats<-dbGetQuery(nova_conn, grade_query)
market_cats<-dbGetQuery(nova_conn, markets_query)

landings<-dbGetQuery(nova_conn, landings_query)

fmp_listing<-dbGetQuery(nova_conn, fmp_query)

dbDisconnect(nova_conn)




# rename to lower
landings <- landings %>%
 rename_with(tolower)
grade_cats <- grade_cats %>%
  rename_with(tolower)%>%
  group_by(itis_tsn, grade_code) %>%
  slice(1)


write_rds(grade_cats, file=here("data_folder","main",glue("grade_cats_{vintage_string}.Rds")))


market_cats <- market_cats %>%
  rename_with(tolower)

#the market description column is a little sketch.
market_cats2<-market_cats %>%
  group_by(itis_tsn, market_code) %>%
  slice(1)

write_rds(market_cats2, file=here("data_folder","main",glue("market_cats_{vintage_string}.Rds")))


# join to market cats
landings<-landings %>%
  left_join(market_cats2, by=join_by(itis_tsn==itis_tsn, dlr_mkt==market_code))
write_rds(landings, file=here("data_folder","main",glue("landings_{vintage_string}.Rds")))
