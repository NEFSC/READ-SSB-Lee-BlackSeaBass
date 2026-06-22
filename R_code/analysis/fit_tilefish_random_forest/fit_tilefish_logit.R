###############################################################################
# Purpose: 	Estimate a multinomial logit for tilefish categories

# I'm using the tidymodels framework to train and test the classification trees
# we can run a simple model with a logit and then easily switch to more sophisticaed models
# 
# Inputs:
#  - tile_estimation_dataset (from data_prep_ml.Rmd)
#  - tile_unclassified_dataset (from data_prep_ml.Rmd)
#  - Tilefish.Classification.Recipe.R
#  - Tilefish.Workflow.Setup.R

# Outputs:
#  - estimating dataset 
#  - tuning results 
###############################################################################  

library("here")

# load tidyverse and related
library("tidyverse")
library("scales")
library("glue")

# load tidyverse and related
library("tidymodels")

library("nnet")

# load utilities
library("knitr")
library("kableExtra")
library("viridis")
library("conflicted")
library("plotly")
library("htmlwidgets")

#deal with conflicts
conflicts_prefer(dplyr::filter())
conflicts_prefer(dplyr::summary())
conflicts_prefer(dplyr::lag())
conflicts_prefer(purrr::discard())
conflicts_prefer(dplyr::group_rows())
conflicts_prefer(yardstick::spec())
conflicts_prefer(recipes::fixed())
conflicts_prefer(recipes::step())
conflicts_prefer(viridis::viridis_pal())
conflicts_prefer(vip::vi)
here::i_am("R_code/analysis/fit_tilefish_random_forest/fit_tilefish_logit.R")

# Set these two to control the size of the dataset. Useful for making sure code 
# works.
#Set up model type
modeltype<-"nocluster"
# OR "nocluster", or "fiveclass", or "noc5class" OR "standard"

search_type<-"Prototype"
# search_type in "Initial", "Prototype","Advanced")

# Only used with search_type<-"Prototype" -- how much data do you want in the dataset to prototype the code
testing_fraction<-0.2		  
start_time<-Sys.time()

# Determine what platform the code is running on and set the number of threads for ranger
platform <- Sys.info()['sysname']
# check the name of the effective_user
if(platform == 'Linux'){
  if (grep("PREEMPT_DYNAMIC",Sys.info()['version'])==1){
    runClass<-'DynamicContainer'
  } else{ 
    runClass <- 'Container'
  }
}


if(platform == 'Windows'){
  runClass<-'Windows'
}

if (runClass %in% c('Local', 'Windows')){
  my.parallel.threads<-1
  my.ranger.multi.threads<-5
} else if (runClass %in% c('Container','DynamicContainer')){ 
  
  # on the container, you're allocated 24 threads	and 90 (or 96gb of memory)
  # Because the dataset is big, you are much better off doing 2 and 11 (or 1 and 22)
  my.parallel.threads<-2
  my.ranger.multi.threads<-11
  my.ranger.sequential.threads<-23
  
  # Kill background logger if it is on
  system("pkill -f 'while true.*top'", ignore.stdout = TRUE, ignore.stderr = TRUE)
  message("CPU logger stopped")
  
  # start background logger
  source(here("R_code","analysis","helpers","background_logger.R"))
  
  
}
lbs_per_mt<-2204.62

#############################################################################
my_images<-here("images")
descriptive_images<-here("images","descriptive")
exploratory_images<-here("images","exploratory")
vintage_string<-list.files(here("data_folder","main","commercial"), pattern=glob2rx("tilefish_estimation_dataset*Rds"))
vintage_string<-gsub("tilefish_estimation_dataset","",vintage_string)
vintage_string<-gsub(".Rds","",vintage_string)
vintage_string<-max(vintage_string)

#Tuning vintage is purposely set as "today"
tuning_vintage<-as.character(Sys.Date())

data_save_name<-glue("tilefish_data_split{tuning_vintage}.Rds")
tune_file_name<-glue("tilefish_tuning{tuning_vintage}.Rds")
best_param_file_name<-glue("tilefish_best_parameters{tuning_vintage}.Rds")
 
final_fit_file_name<-glue("tilefish_final{tuning_vintage}.Rds")
vi_file_name<-glue("tilefish_vi{tuning_vintage}.Rds")

# Load data from data_prep_ml.Rmd
estimation_dataset<-readr::read_rds(file=here("data_folder","main","commercial",glue("tilefish_estimation_dataset{vintage_string}.Rds")))


# for reproducibility
set.seed(4587315)


# trim out the extra factor levels from market_desc.
estimation_dataset<-estimation_dataset %>%
  mutate(market_desc=fct_drop(market_desc))%>%
  select(-weighting)

# When testing, take a subset of the data. This is just to test how my code is working   
if  (search_type=="Prototype"){
  estimation_dataset$rand<-runif(nrow(estimation_dataset))
  estimation_dataset<-estimation_dataset %>%
    dplyr::filter(rand<=testing_fraction)
}

# 
# keep_cols<-c("market_desc","myl_id","dlrid","mygear","price","priceR_CPI", "stockarea","state", "year","month", "semester","lndlb", "grade_desc", "trip_level_BSB", "catch_share")
# keep_cols<-c(keep_cols,"shore","nofederal")
# keep_cols<-c(keep_cols,"StateOtherQJumbo", "StateOtherQLarge", "StateOtherQMedium", "StateOtherQSmall" )
# keep_cols<-c(keep_cols,"StockareaOtherQJumbo", "StockareaOtherQLarge", "StockareaOtherQMedium", "StockareaOtherQSmall" )
# keep_cols<-c(keep_cols,"MA7_StockareaQJumbo", "MA7_StockareaQLarge", "MA7_StockareaQMedium", "MA7_StockareaQSmall" )
# keep_cols<-c(keep_cols,"MA7_StateQJumbo", "MA7_StateQLarge","MA7_StateQMedium", "MA7_StateQSmall")
# keep_cols<-c(keep_cols,"MA7_gearQJumbo", "MA7_gearQLarge","MA7_gearQMedium", "MA7_gearQSmall")
# keep_cols<-c(keep_cols,"MA7_stockarea_trips", "MA7_state_trips" )
# 
# 
# estimation_dataset<- estimation_dataset %>%
#   select(all_of(keep_cols))

set.seed(2824)
# 80% of the data in the training, 5% in the calibration sample, 15% in the validation sample
# consider splitting on strata=market_desc, although I don't think this is strictly necessary. 
data_split <- initial_validation_split(
  data=estimation_dataset,
  prop = c(0.8, 0.05)
)
train_data <- training(data_split)
test_data <- testing(data_split)
validation_data <- validation(data_split)

readr::write_rds(data_split, file=here("results","ranger",data_save_name))

nrow(train_data)
nrow(test_data)
nrow(validation_data)

# Pick a subset of my training data to do my tuning.

set.seed(95976)


# Do some checks. How big are these datasets?
train_full_rows<-nrow(train_data)


# # Recipe definition
# 
# The recipe simply defines the dataset, outcome (reponse, y) variable, id variables,
# and predictor variables.
source(here("R_code","analysis","fit_random_forest","Tilefish.Classification.Recipe.R"))

# Set up the workflow
source(here("R_code","analysis","fit_random_forest","Tilefish.Workflow.Setup.R"))

set.seed(123)
# split the training data group wise into 10 folds with the same number of observations, 

myfolds<-vfold_cv(train_data, 
                        strata=market_desc, 
                        v = 10)

vfold_cv_results <- fit_resamples(
  tilefish.multi.tuning.Workflow,
  resamples = myfolds,
  metrics=class_and_probs_metrics
)



metrics_by_fold <- collect_metrics(vfold_cv_results, summarize = FALSE)  # fold-level
saveRDS(metrics_by_fold,  "tilefish_metrics_by_fold.rds")
write_rds(metrics_by_fold, file=here("results","ranger", glue("Tilefish_folding_metrics_by_fold{tuning_vintage}.Rds")))

#rm(metrics_by_fold)


#Kill the logger, I'm done with the heavy lifting.
system("pkill -f 'while true.*top'", ignore.stdout = TRUE, ignore.stderr = TRUE)
message("CPU logger stopped")


cat("Tuning done")
