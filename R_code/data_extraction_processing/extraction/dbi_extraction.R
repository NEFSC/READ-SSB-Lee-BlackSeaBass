library("dplyr")
library("DBI")
library("ROracle")
library("dbplyr")



# DBI and ODBC Connection
# This code assumes that
# An approriate DSN is stored in the R object "nefsc_users"
# your oracle id is stored in the R object "id"
# your oracle password is stored in the the object "novapw"
# star_dbi_odbc <- DBI::dbConnect(odbc::odbc(), 
#                            nefsc_users, 
#                            UID = id, 
#                            PWD = novapw)




# DBI and ROracle Connection
# This code assumes that
# A connection string (nefscusers.connect.string) has been assembled
# your oracle id is stored in the R object "id"
# your oracle password is stored in the the object "novapw"


star_dbi_ROracle <- DBI::dbConnect(dbDriver("Oracle"),id, password=novapw, dbname=nefscusers.connect.string)



# SOME Sample queries, not run
# #This takes a little while, because there are about 1.6M rows
# cams_cfdets<-paste0("select Year, camsid, permit, itis_tsn, lndlb, nvl(value,0) as value, state, subtrip 
#                      from CAMS_GARFO.CAMS_LAND
#                      where (Year>=2020 and Year <= 2021)and permit not in ('000000', '190998','390998')
#                      and DLR_UTILCD in (0,7)")
# 
# # This just pulls 1 month and is much faster (~113k rows)
# cams_cfdets<-paste0("select Year, camsid, permit, itis_tsn, lndlb, nvl(value,0) as value, state, subtrip 
#                      from CAMS_GARFO.CAMS_LAND
#                      where Year=2021 and  MONTH= 8 and permit not in ('000000', '190998','390998')
#                      and DLR_UTILCD in (0,7)")
# 
# 
 permit_query<-paste0("select * from NEFSC_GARFO.PERMIT_VPS_VESSEL WHERE
              AP_YEAR>=2018 
             order by vp_num, ap_year")


# Get data using DBI and ODBC 
# permit_data<-dplyr::tbl(star_dbi_odbc,sql(permit_query)) %>%
#   collect()
# 
# dbDisconnect(star_dbi_odbc)


# Get data using DBI and ROracle 
permit_data2<-dplyr::tbl(star_dbi_ROracle,sql(permit_query)) %>%
  collect()


#cams_spec<-dplyr::tbl(star_dbi,sql(cams_cfdets)) %>%
#  collect()


# Some People like to get the entire table using DBPLYR's in_schema and then do tidy operations on it.
VPS_VESSEL <- tbl(star_dbi_ROracle, in_schema("NEFSC_GARFO", "PERMIT_VPS_VESSEL")) 


VPS_VESSEL <- VPS_VESSEL %>%
  filter(AP_YEAR>=2018) %>%
  collect()


dbDisconnect(star_dbi_ROracle)

