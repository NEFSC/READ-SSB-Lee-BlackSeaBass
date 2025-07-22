################################################################################
# Small R script to render lots of variations of the reading_ranger_results.Rmd file.   
# Inputs: These three can be adjusted by changing the "modeltype"
#   - Data file
#   - tuning results file
#   - final results file

# Outputs:
  #   - Graphs of tuning quality and final model fit
  #   - Aggregate predictions for the testing (validation) dataset and the entire dataset (train+test)
################################################################################
  

# Borrowed heavily from https://bookdown.org/yihui/rmarkdown/params-knit.html

library("here")
library("rmarkdown")
library("glue")

here::i_am("writing/knit_ranger_results_in_loop.R")

#create a directory in main for the casestudy data to go
dir.create(here::here("results","ranger","reports"), showWarnings="FALSE")

#List of inputs that we are looping over.
#input_model_vec<-c("standard","fiveclass","noc5class","nocluster", "South_NOC","North_NOC")

input_model_vec<-c("South_NOC", "nocluster")


##################################################################################
#Define a function that passes parameters into the rmarkdown::render function
render_tiny_report = function(input_model) {
  rmarkdown::render(here::here("writing", "reading_ranger_results.Rmd"), params = list(
    modeltype=input_model
  ),
  output_file = here::here("results","ranger","reports",glue("ranger_results", {input_model}, ".html")
  ))
}
################################################################################## 


# Run lots of tiny scallop analysis reports.
    for (in_model in input_model_vec)  {
      render_tiny_report(in_model)
    }





  
