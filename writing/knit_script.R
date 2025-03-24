# Run this from terminal with:
# > Rscript knit_script.R
library("here")
library("rmarkdown")

here::i_am("writing/knit_script.R")



##################################################################################
rmarkdown::render(here::here("writing","estimate_randomforest.Rmd"),
                  output_file = here::here("writing","estimate_randomforest.html"))
##################################################################################



##################################################################################
rmarkdown::render(here::here("writing","reading_ranger_results.Rmd"),
                  output_file = here::here("writing","reading_ranger_results.html"))
##################################################################################
