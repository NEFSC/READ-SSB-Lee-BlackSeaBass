###############################################################################
# Purpose: 	Tune the mtry and min_n parameters in a  Random Forest classification model
# on 4 classes WITHOUT Clustering
# on DLRID for the validation. Unclassified are excluded.

# I'm using the tidymodels framework to train and test the classification trees and
# random forest.  The main advantage is that switching models or estimation packages
# (partykit::ctree vs ranger vs randomForest for example) is easier. Writing the model 
# uses tidy syntax.  Tuning the model is made easier by using tune and yardstick.
# Fitting ranger requires bonsai.
# 
# The canonical way to do this is to declare a recipe and a workflow.  Ideally,
# everything would be part of the workflow, but my data processing skills in R are
# note good enough to want to do this.  Therefore, I'm basically passing the
# recipe into the workflow. C'est la guerre.

# Inputs:
#  - BSB_estimation_dataset (from data_prep_ml.Rmd)
#  - BSB_unclassified_dataset (from data_prep_ml.Rmd)
#  - BSB.Classification.Recipe.R
#  - BSB.Workflow.Setup.R

# Outputs:
#  - estimating dataset 
#  - tuning results 
###############################################################################  
# Set these two to control the size of the dataset. Useful for making sure code 
# works.


bayes_tune<-"FALSE"

search_type<-"Initial"
# search_type in "Initial", "Prototype","Advanced")

# Only used with search_type<-"Prototype" -- how much data do you want in the dataset to prototype the code
# testing_fraction<-.05			  
#  
start_time<-Sys.time()
modeltype<-"nocluster"
# OR "nocluster", or "fiveclass", or "noc5class" OR "standard"


library("here")

# load tidyverse and related
library("tidyverse")
library("scales")
library("glue")

# load tidyverse and related
library("tidymodels")

# load machine learning and estimation tools
# ranger imports RcppEigen and Rcpp, all 3 need to be compiled on unix.
# you might want to install Rcpp, then RcppEigen, then ranger

library("nnet")
library("ranger")

library("partykit")
library("bonsai")
# load utilities
library("knitr")
library("kableExtra")
library("viridis")
library("future")
library("conflicted")

#deal with conflicts
conflicts_prefer(dplyr::filter())
conflicts_prefer(dplyr::lag())
conflicts_prefer(purrr::discard())
conflicts_prefer(dplyr::group_rows())
conflicts_prefer(yardstick::spec())
conflicts_prefer(recipes::fixed())
conflicts_prefer(recipes::step())
conflicts_prefer(viridis::viridis_pal())
conflicts_prefer(vip::vi)
here::i_am("R_code/analysis/fit_random_forest/tune_randomforest_nocluster.R")




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
  my.ranger.sequential.threads<-20
  
  
  # Kill background logger if it is on
  system("pkill -f 'while true.*top'", ignore.stdout = TRUE, ignore.stderr = TRUE)
  message("CPU logger stopped")
  
  # start background logger
  source(here("R_code","analysis","helpers","background_logger.R"))
  
  
}
lbs_per_mt<-2204.62
# my.parallel.threads =4 and my.ranger.multi.threads=5  about 30 GB of RAM on the "full" dataset (~381,542 in the training set).

options(future.globals.maxSize = 8 * 1024^3)

lbs_per_mt<-2204.62
#############################################################################
my_images<-here("images")
descriptive_images<-here("images","descriptive")
exploratory_images<-here("images","exploratory")
vintage_string<-list.files(here("data_folder","main","commercial"), pattern=glob2rx("BSB_estimation_dataset*Rds"))
vintage_string<-gsub("BSB_estimation_dataset","",vintage_string)
vintage_string<-gsub(".Rds","",vintage_string)
vintage_string<-max(vintage_string)
estimation_vintage<-as.character(Sys.Date())


data_save_name<-glue("nocluster_data_split{estimation_vintage}.Rds")
tune_file_name<-glue("BSB_ranger_nocluster_tune{estimation_vintage}.Rds")
final_fit_file_name<-glue("BSB_ranger_nocluster_results{estimation_vintage}.Rds")
vi_file_name<-glue("BSB_ranger_nocluster_VI{estimation_vintage}.Rds")
best_param_file_name<-glue("BSB_ranger_nocluster_best_params{estimation_vintage}.Rds")

if  (search_type=="Prototype"){
  data_save_name<-glue("TEST_nocluster_data_split_{estimation_vintage}.Rds")
  tune_file_name<-glue("TEST_BSB_ranger_nocluster_tune{estimation_vintage}.Rds")
  final_fit_file_name<-glue("TEST_BSB_ranger_nocluster_results{estimation_vintage}.Rds")
  vi_file_name<-glue("TEST_BSB_ranger_nocluster_VI{estimation_vintage}.Rds")
  best_param_file_name<-glue("TEST_BSB_ranger_nocluster_best_params{estimation_vintage}.Rds")
  
  
}

# Load data from data_prep_ml.Rmd
estimation_dataset<-readr::read_rds(file=here("data_folder","main","commercial",glue("BSB_estimation_dataset{vintage_string}.Rds")))


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


keep_cols<-c("market_desc","myl_id","dlrid","mygear","price","priceR_CPI", "stockarea","state", "year","month", "semester","lndlb", "grade_desc", "trip_level_BSB", "catch_share")
keep_cols<-c(keep_cols,"shore","nofederal")
keep_cols<-c(keep_cols,"StateOtherQJumbo", "StateOtherQLarge", "StateOtherQMedium", "StateOtherQSmall" )
keep_cols<-c(keep_cols,"StockareaOtherQJumbo", "StockareaOtherQLarge", "StockareaOtherQMedium", "StockareaOtherQSmall" )
keep_cols<-c(keep_cols,"MA7_StockareaQJumbo", "MA7_StockareaQLarge", "MA7_StockareaQMedium", "MA7_StockareaQSmall" )
keep_cols<-c(keep_cols,"MA7_StateQJumbo", "MA7_StateQLarge","MA7_StateQMedium", "MA7_StateQSmall")
keep_cols<-c(keep_cols,"MA7_gearQJumbo", "MA7_gearQLarge","MA7_gearQMedium", "MA7_gearQSmall")
keep_cols<-c(keep_cols,"MA7_stockarea_trips", "MA7_state_trips" )
# keep_cols<-c(keep_cols,"Share2014Jumbo", "Share2014Large", "Share2014Medium","Share2014Small", "Share2014Unclassified" )
# keep_cols<-c(keep_cols,"TransactionCountJumbo", "TransactionCountLarge", "TransactionCountMedium", "TransactionCountSmall", "TransactionCountUnclassified" )
keep_cols<-c(keep_cols,"LagSharePoundsJumbo","LagSharePoundsLarge", "LagSharePoundsMedium","LagSharePoundsSmall", "first_dlr_year")
#keep_cols<-c(keep_cols,"LagShareTransJumbo", "LagShareTransLarge", "LagShareTransMedium","LagShareTransSmall", "LagShareTransUnclassified")
keep_cols<-c(keep_cols, "Price_Diff_J","Price_Diff_L", "Price_Diff_M") 


estimation_dataset<- estimation_dataset %>%
  select(all_of(keep_cols))

set.seed(2824)
# 70% of the data in the training, 15% in the calibration sample, 15% in the validation sample
# consider splitting on strata=market_desc, although I don't think this is strictly necessary. 
data_split <- initial_validation_split(
  data=estimation_dataset,
  prop = c(0.7, 0.15)
)
train_full_data <- training(data_split)
test_data <- testing(data_split)
validation_data <- validation(data_split)

readr::write_rds(data_split, file=here("results","ranger",data_save_name))

nrow(train_full_data)
nrow(test_data)
nrow(validation_data)

# Pick a subset of my training data to do my tuning.

set.seed(95976)
# 70% of the data in the training, 15% in the calibration sample, 15% in the validation sample
# consider splitting on strata=market_desc, although I don't think this is strictly necessary. 
train_data <- initial_split(
  data=train_full_data,
  prop = c(0.05)
)

#expand by landed pounds 
train_data<-training(train_data) %>%
  mutate(lndlb2=lndlb) %>%
  uncount(lndlb2)


# # Recipe definition
# 
# The recipe simply defines the dataset, outcome (reponse, y) variable, id variables,
# and predictor variables.
source(here("R_code","analysis","fit_random_forest","BSB.Classification.Recipe.R"))

# Set up the tuning workflow
source(here("R_code","analysis","fit_random_forest","BSB.Workflow.Setup.R"))

set.seed(123)
# split the training data group wise into 10 folds with the same number of observations, 
# grouped by myl_id (original observation), so that that each original records is wholly contained in a single fold.
myfolds<-group_vfold_cv(train_data, 
                        group=myl_id,
                        strata=market_desc, 
                        v = 10)

plan("multisession", workers=my.parallel.threads)
set.seed(8675309)					  

rf_control_grid<-control_grid(save_pred = TRUE, parallel_over="everything")
start_time_tune<-Sys.time()

message("Tuning model hyperparameters", Sys.time())

tune_res <- tune_grid(
  BSB.Ranger.tuning.Workflow,
  resamples = myfolds,
  grid = rf_grid,
  control=rf_control_grid,
  metrics=class_and_probs_metrics
)
plan("sequential")
message("Grid Tuning Finished. Saving tuning results", Sys.time())


write_rds(tune_res, file=here("results","ranger", tune_file_name))
end_time_tune<-Sys.time()
end_time_tune-start_time_tune

bayes_param <- BSB.Ranger.tuning.Workflow %>% 
  extract_parameter_set_dials() %>% 
  update(mtry = finalize(mtry(), train_data))

if(bayes_tune==TRUE){
message("Performing Bayesian Tuning", Sys.time())
  
  # Do a tune_bayes
  plan("multisession", workers=my.parallel.threads)
  set.seed(9035768)
  
  start_time_bt<-Sys.time()
  
  tune_res2 <- tune_bayes(
    object=BSB.Ranger.tuning.Workflow,
    resamples = myfolds,
    initial = tune_res,
    param_info=bayes_param,
    iter = 30,                     # 
    control = control_bayes(
      verbose = TRUE,
      no_improve=10,
      save_pred = TRUE,             # Save predictions for analysis
      save_workflow = FALSE,        # Save memory
      extract = NULL,              # Don't extract additional info
      parallel_over = "everything" # Parallelize over resamples to save memory
      ),
      metrics=metric_set(brier_class)
  )
  end_time_bt<-Sys.time()
  end_time_bt-start_time_bt
  
  plan("sequential")
  write_rds(tune_res2, file=here("results","ranger", tune_file_name))
  message("Bayesian Tuning Finished", Sys.time())
  
  autoplot(tune_res2, type = "performance") +
    labs(title = "Did Bayesian optimization converge?")
}else if (bayes_tune==FALSE){
  message("Bayesian Tuning Skipped")
  
  tune_res2<-tune_res
}
message ("errors")
tune_res2 %>%
  tune::collect_notes() %>%
  dplyr::filter(type == "error") %>%
  dplyr::select(location, note) %>%
  print(width = 200)

system("pkill -f 'while true.*top'", ignore.stdout = TRUE, ignore.stderr = TRUE)
message("CPU logger stopped")

# Select the best Rforest based on log loss from the 10 folds. Just print them for now.

best_params <- tune_res2 %>%
  select_best(metric = "brier_class")

write_rds(best_params, file=here("results","ranger", best_param_file_name))



cat("Tuning done")
