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
