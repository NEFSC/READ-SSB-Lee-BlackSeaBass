# This is code that uses Roracle to connect to oracle databases. 
# ROracle can be tricky to set up. See this document for instructions https://docs.google.com/document/d/1Qsv_Jfc8CsoG49-qK-2RHdSJzR7v48W7ehZbG9k3RUQ/edit

# your oracle id is stored in the R object "id"
# your oracle password is stored in the the object "oracle_pw"


if(!require(ROracle)) {  
  install.packages("ROracle")
  require(ROracle)}


#### Set things up
here::i_am("R_code/data_extraction_processing/extraction/r_oracle_connection.R")

my_projdir<-here()

#this reads in paths and libraries
source(file.path(my_projdir,"R_code","project_logistics","R_paths_libraries.R"))




# DBI and ROracle Connection
# This code assumes that
# your oracle id is stored in the R object "id"
# your oracle password is stored in the the object "novapw"


 ############################################################################################
 #First, set up Oracle Connection
 ############################################################################################

# The following are details needed to connect using ROracle. 
drv<-dbDriver("Oracle")
shost <- "<nefsc_users.full.path.to.server.gov>"
port <- port_number_here
ssid <- "<ssid_here>"

nefscusers.connect.string<-paste(
  "(DESCRIPTION=",
  "(ADDRESS=(PROTOCOL=tcp)(HOST=", shost, ")(PORT=", port, "))",
  "(CONNECT_DATA=(SERVICE_NAME=", ssid, ")))", sep="")





START.YEAR= 2015
END.YEAR=2018

#First, pull in permits and tripids into a list.
permit_tripids<-list()
i<-1


for (years in START.YEAR:END.YEAR){
  users_conn<-ROracle::dbConnect(drv, id, password=novapw, dbname=nefscusers.connect.string)
  querystring<-paste0("select permit, tripid from vtr.veslog",years,"t")
  permit_tripids[[i]]<-dbGetQuery(users_conn, querystring)
  dbDisconnect(users_conn)
  i<-i+1
}
#flatten the list into a dataframe

permit_tripids<-do.call(rbind.data.frame, permit_tripids)
colnames(permit_tripids)[which(names(permit_tripids) == "PERMIT")] <- "permit"



# Pull in gearcode data frame from sole
users_conn<-ROracle::dbConnect(drv, id, password=novapw, dbname=nefscusers.connect.string)

querystring2<-paste0("select gearcode, negear, negear2, gearnm from vtr.vlgear")
VTRgear<-dbGetQuery(users_conn, querystring2)

dbDisconnect(users_conn)











  
