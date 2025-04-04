# Run this from terminal with:
# > Rscript knit_script.R
# But it's better to run the batch_RF_run.sh file, because that logs individual scripts

library("here")
library("rmarkdown")

here::i_am("writing/knit_script.R")

source(here("writing","estimate_randomforest_nocluster.R")

       
source(here("writing","estimate_randomforest.R")

##################################################################################
rmarkdown::render(here::here("writing","estimate_randomforest.Rmd"),
                  output_file = here::here("writing","estimate_randomforest.html"))
##################################################################################



##################################################################################
# rmarkdown::render(here::here("writing","reading_ranger_results.Rmd"),
#                   output_file = here::here("writing","reading_ranger_results.html"))
##################################################################################
