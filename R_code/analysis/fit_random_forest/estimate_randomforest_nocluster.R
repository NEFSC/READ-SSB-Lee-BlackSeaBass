###############################################################################
# Purpose: 	Estimate a Random Forest classification model on 4 classes WITHOUT Clustering
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
#  - final_fit results
###############################################################################  
# Set these two to control the size of the dataset. Useful for making sure code 
# works.
testing<-FALSE
testing_fraction<-0.30

# how much of the data to hold out for final validation
training_fraction<-0.90
start_time<-Sys.time()
modeltype<-"nocluster"
# OR "nocluster", or "fiveclass", or "noc5class" OR "standard"


library("here")

# load tidyverse and related
library("tidyverse")
library("scales")

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

here::i_am("R_code/analysis/fit_random_forest/estimate_randomforest_nocluster.R")


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
  my.ranger.threads<-6
} else if (runClass %in% c('Container')){ 
  my.ranger.threads<-8
}else if (runClass %in% c('DynamicContainer')){ 
  my.ranger.threads<-8
  
}


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


data_save_name<-paste0("nocluster_data_split",estimation_vintage,".Rds")
tune_file_name<-paste0("BSB_ranger_nocluster_tune",estimation_vintage,".Rds")
final_fit_file_name<-paste0("BSB_ranger_nocluster_results",estimation_vintage,".Rds")

if(testing==TRUE){
  data_save_name<-paste0("nocluster_data_split_TEST",estimation_vintage,".Rds")
  tune_file_name<-paste0("BSB_ranger_nocluster_tune_TEST",estimation_vintage,".Rds")
  final_fit_file_name<-paste0("BSB_ranger_nocluster_results_TEST",estimation_vintage,".Rds")
  
}

# 
# Most of my data cleaning code is in stata. There's no reason to port it to R and risk mistakes now.  In brief, I:
# 
# 1. Extract transaction level commercial landings of black sea bass at the camisd+subtrip level (cams_land.rec=0). Any column in CAMS_LAND is available, but sales transactions are tied to a "trip", not a "subtrip". This means there is some uncomfortableness for any transactions corresponding to multi-area (and multi-gear) trips. 
# 2. I do some "joins" to keyfiles (market category, market grade, gear, and economic deflators).
# 3. I do some tidying-up (converting datetime variables to date variables)
# 4. I rebin status=DLR_ORPHAN_SPECIES into status=MATCH
# 
# 5. There is a little data dropping
#   1. landed pounds=0
#   2. Some landings from VA and DE that look like aggregates. 
# 6. I do some binning of gears, loosely into
#   1. Line or Hand gear
#   2. Trawls
#   3. Gillnets
#   4. Pot and Trap
#   5. Misc=Dredge, Seine, and Unknown.
#   
# 7.  I do some binning of market categories
#   1. Unclassified and "Mixed or Unsized" are combined
#   2. Small, Extra Small, and Pee Wee (Rats) are combined
#   3. Medium and "Medium or Select" are combined.
# 8.  Ungraded is combined with Round
# 9. I construct a stockunit indicator
#   1. south is 621 and greater, plus 614 and 615 
#   2. North is 613 and smaller, plus 616
# 10. I create a semester indicator (=1 if Jan to June and =2 if July to Dec)
# 11. I SHOULD scale landed pounds, nominal value, and deflated value to "thousands". Prices
# are in both real and nominal dollars per landed pound. 
# 12. I have day-marketcategory landings (pounds) by "other vessels". I also have day-state-marketcategory and day-stockarea-marketcategory. 

# Load data from data_prep_ml.Rmd
estimation_dataset<-readr::read_rds(file=here("data_folder","main","commercial",paste0("BSB_estimation_dataset",vintage_string,".Rds")))


# for reproducibility
set.seed(4587315)


# When testing, take a subset of the data. This is just to test how my code is working   
if(testing==TRUE){
  estimation_dataset$rand<-runif(nrow(estimation_dataset))
  estimation_dataset<-estimation_dataset %>%
    dplyr::filter(rand<=testing_fraction)
}

# construct the "case weights" variable here and trim out the extra factor levels from market_desc.
estimation_dataset<-estimation_dataset %>%
  mutate(weighting = frequency_weights(weighting),
         market_desc=fct_drop(market_desc))

keep_cols<-c("market_desc","dlrid","camsid","weighting", "mygear","price","priceR_CPI", "stockarea","state", "year","month", "semester","lndlb", "grade_desc", "trip_level_BSB")
keep_cols<-c(keep_cols,"shore","nofederal","permit", "hullid")
keep_cols<-c(keep_cols,"StateOtherQJumbo", "StateOtherQLarge", "StateOtherQMedium", "StateOtherQSmall" )
keep_cols<-c(keep_cols,"StockareaOtherQJumbo", "StockareaOtherQLarge", "StockareaOtherQMedium", "StockareaOtherQSmall" )
keep_cols<-c(keep_cols,"MA7_StockareaQJumbo", "MA7_StockareaQLarge", "MA7_StockareaQMedium", "MA7_StockareaQSmall" )
keep_cols<-c(keep_cols,"MA7_StateQJumbo", "MA7_StateQLarge","MA7_StateQMedium", "MA7_StateQSmall")
keep_cols<-c(keep_cols,"MA7_gearQJumbo", "MA7_gearQLarge","MA7_gearQMedium", "MA7_gearQSmall")
keep_cols<-c(keep_cols,"MA7_stockarea_trips", "MA7_state_trips" )
# keep_cols<-c(keep_cols,"Share2014Jumbo", "Share2014Large", "Share2014Medium","Share2014Small", "Share2014Unclassified" )
# keep_cols<-c(keep_cols,"TransactionCountJumbo", "TransactionCountLarge", "TransactionCountMedium", "TransactionCountSmall", "TransactionCountUnclassified" )
keep_cols<-c(keep_cols,"LagSharePoundsJumbo","LagSharePoundsLarge", "LagSharePoundsMedium","LagSharePoundsSmall","LagSharePoundsUnclassified")
keep_cols<-c(keep_cols,"LagShareTransJumbo", "LagShareTransLarge", "LagShareTransMedium","LagShareTransSmall", "LagShareTransUnclassified")


estimation_dataset<- estimation_dataset %>%
  select(all_of(keep_cols))

set.seed(2824)
# 80% of the data in the training, and 20% in the holdout sample, not weighted.
# split on strata=market_desc, although I don't think this is strictly necessary. 
data_split <- initial_split(data=estimation_dataset, prop=training_fraction) 
train_data <- training(data_split)
test_data <- testing(data_split)

readr::write_rds(data_split, file=here("results","ranger",data_save_name))

nrow(train_data)
nrow(test_data)





# # Recipe definition
# 
# The recipe simply defines the dataset, outcome (reponse, y) variable, id variables,
# and predictor variables.
source(here("R_code","analysis","fit_random_forest","BSB.Classification.Recipe.R"))


source(here("R_code","analysis","fit_random_forest","BSB.Workflow.Setup.R"))

set.seed(457)
# split the training data group wise into 10 folds with the same number of observations, but grouped by dlrid, so that each dlrid is wholly contained in a single fold.
myfolds<-rsample::vfold_cv(train_data, strata=market_desc, v = 10)

rf_control_grid<-control_grid(save_pred = TRUE, parallel_over="everything")
start_time_tune<-Sys.time()

tune_res <- tune_grid(
  tune_wf,
  resamples = myfolds,
  grid = rf_grid,
  control=rf_control_grid,
  metrics=class_and_probs_metrics
)


# Search over 2 sets of parameters
# #Search over mtry and trees
# rf_grid2 <-  grid_regular(
#     mtry(range = c(1, 20)), levels=10)
#      trees(range=c(100,1000), levels=5)
#     )
# 
# 
# # configure the tuning part of the model.
# tune_spec2 <- rand_forest(
#   mtry = tune(),
#   trees = tune(),
#   min_n = 5,
# ) %>%
#   set_mode("classification") %>%
#   set_engine("ranger",num.threads=!!my.ranger.threads, na.action="na.learn", respect.unordered.factors="order", importance="impurity")
# 
# 
# 
# 
# # make a turning workflow. This combines the BSB.Classification.Recipe "data declaration" steps and new "tuning"
# # steps as the model.
# tune_wf2 <- workflow() %>%
#   add_recipe(BSB.Classification.Recipe) %>%
#   add_model(tune_spec2)
# # search over mtry and trees
# 
# 
# hardhat::extract_parameter_set_dials(tune_wf2)
# 
# 
# start_time_tune<-Sys.time()
# 
# tune_res <- tune_grid(
#   tune_wf2,
#   resamples = myfolds,
#   grid = rf_grid2,
#   control=rf_control_grid,
#   metrics=class_and_probs_metrics
# )
# 
# 
# 

write_rds(tune_res, file=here("results","ranger", tune_file_name))
end_time_tune<-Sys.time()
end_time_tune-start_time_tune


# Select the best Rforest based on log loss from the 10 folds.  Do a final fit on the full training dataset, predict on the validation dataset. Save the data

best_tree <- tune_res %>%
  select_best(metric = "brier_class")

best_tree

# finalize model by picking the best model hyperparameters
final_wf <- 
  tune_wf %>% 
  finalize_workflow(best_tree)


# Final model fitting on the full training dataset 
final_fit <- 
  final_wf %>%
  last_fit(data_split, metrics=class_and_probs_metrics) 



write_rds(final_fit, file=here("results","ranger",final_fit_file_name))


# print out the metrics
final_fit %>%
  collect_metrics()

end_time<-Sys.time()
end_time

end_time-start_time
sessionInfo()
