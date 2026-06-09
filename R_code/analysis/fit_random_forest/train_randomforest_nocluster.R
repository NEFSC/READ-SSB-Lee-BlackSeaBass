###############################################################################
# Purpose: 	Train a Random Forest classification model on 4 classes WITHOUT Clustering
# on DLRID for the validation. Unclassified are excluded.
# this assumes you have already trined a model using 
# tune_randomforest_nocluster.R

# Inputs:
#  - data_split (from tune_randomforest_nocluster.R)
#  - BSB.Classification.Recipe.R
#  - BSB.Workflow.Setup.R

# Outputs:
#  - final_fit results
#  - variable importance
###############################################################################  

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
here::i_am("R_code/analysis/fit_random_forest/train_randomforest_nocluster.R")

# Set these two to control the size of the dataset. Useful for making sure code 
# works.
#Set up model type
modeltype<-"nocluster"
# OR "nocluster", or "fiveclass", or "noc5class" OR "standard"

search_type<-"Advanced"
# search_type in "Initial", "Prototype","Advanced")


source(here("R_code","analysis","helpers","modeltype_patterns.R"))


# Only used with search_type<-"Prototype" -- how much data do you want in the dataset to prototype the code
testing_fraction<-1			  
start_time<-Sys.time()

#Turn bayesian tuning on or off.
bayes_tune<-"FALSE"

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
  my.ranger.sequential.threads<-22
  
  # Kill background logger if it is on
  system("pkill -f 'while true.*top'", ignore.stdout = TRUE, ignore.stderr = TRUE)
  message("CPU logger stopped")
  
  # start background logger
  source(here("R_code","analysis","helpers","background_logger.R"))
  
}
lbs_per_mt<-2204.62

lbs_per_mt<-2204.62
#############################################################################
my_images<-here("images")
descriptive_images<-here("images","descriptive")
exploratory_images<-here("images","exploratory")

#############################################################################
# Read in data and tuning results.
#############################################################################

# data vintage
vintage_string<-list.files(here("data_folder","main","commercial"), pattern=glob2rx("BSB_estimation_dataset*Rds"))
vintage_string<-gsub("BSB_estimation_dataset","",vintage_string)
vintage_string<-gsub(".Rds","",vintage_string)
data_vintage<-max(vintage_string)





#data_vintage<-as.character(Sys.Date())
################################################################################
# Read in data and tuning results.
################################################################################


# Pick up the most recent tuning
tuning_vintage<-list.files(here("results","ranger"), pattern=glob2rx(glue("{tuning_pattern}*.Rds")))
tuning_vintage<-gsub(tuning_pattern,"",tuning_vintage)
tuning_vintage<-gsub(".Rds","",tuning_vintage)
tuning_vintage<-max(tuning_vintage)

# Assemble file names to read in data, tuning results, and best_params.
# Although the source data has a different vintage, I'm loading in "data_split" which has the same vintage as the tuning
# The tuning and best_param already exist.
# the final fit and vi files will be created by this file. I'm choosing to use 
# the tuning date here, since the final fit and tuning go together.
data_save_name<-glue("{data_pattern}{tuning_vintage}.Rds")
tune_file_name<-glue("{tuning_pattern}{tuning_vintage}.Rds")
best_param_file_name<-glue("{best_param_pattern}{tuning_vintage}.Rds")

final_fit_file_name<-glue("{final_pattern}{tuning_vintage}.Rds")
vi_file_name<-glue("{vi_pattern}{tuning_vintage}.Rds")


data_split<-readr::read_rds(file=here("results","ranger",data_save_name))
train_data <- training(data_split)
test_data <- testing(data_split)
validation_data <- validation(data_split)

nrow(train_data)
nrow(test_data)
nrow(validation_data)





# # Recipe definition
# 
# The recipe simply defines the dataset, outcome (reponse, y) variable, id variables,
# and predictor variables.
source(here("R_code","analysis","fit_random_forest","BSB.Classification.Recipe.R"))

# Set up the tuning workflow
source(here("R_code","analysis","fit_random_forest","BSB.Workflow.Setup.R"))

# Read in best parameters.  Do a training on the full training dataset, predict on the validation dataset. Save the data

tune_res<-read_rds(file=here("results","ranger", tune_file_name))
best_params<-read_rds(file=here("results","ranger", best_param_file_name))





############################################
# Final fit spec
# I could use update to change trees, but I also need to change the engine options
# and that's a little dicey.
final_spec <- tune_spec %>%
  update(trees=500)
  
  
# finalize model by setting best model hyperparameters
final_wf  <- BSB.Ranger.tuning.Workflow %>%
  update_model(final_spec)
set.seed(132564)

# Final model fitting on the full training dataset 
message("Fitting final model:...")
final_fit <- 
  final_wf %>%
  last_fit(data_split, metrics=class_and_probs_metrics) 


message("Final model fit finished.", Sys.time())


write_rds(final_fit, file=here("results","ranger",final_fit_file_name))


# print out the metrics
final_fit %>%
  collect_metrics()


########################################################################################################
# Final fit with impurity_correction.  Permutation is better, but an uncount() handling of weighted observations makes the 
# OOB not truly "out of the bag".  Impurity corrected is the next best alternative, however it is not appropriate for predictions.
# Therefore, we fit the model once to get the proper variable importance, then we refit to get the true 'last model' for predictions.
########################################################################################################
# variable importance spec

# A threading note 
# here I'm fitting an RF on a single set of params (there's 1 mtry and 1 num_trees). I could run a multisession, but just allocating alot of threads to ranger will work fine too.

vi_spec <-  rand_forest(
  trees = 500,
  mtry = tune(),
  min_n = tune()
) %>%
  finalize_model(best_params) %>%
  set_mode("classification") %>%
  set_engine("ranger",
             num.threads = !!my.ranger.sequential.threads, 
             na.action = "na.learn", 
             respect.unordered.factors = "order",
             importance = "impurity_corrected", # While I'd prefer permutation, that relies on OOB. Impurity corrected is better.  
             oob.error = FALSE,          # Kept OFF 
             keep.inbag = FALSE,         # Kept OFF to save memory
             probability = TRUE, 
             write.forest = TRUE)

# finalize model by picking the best model hyperparameters
vi_wf  <- BSB.Ranger.tuning.Workflow %>%
  update_model(vi_spec)

set.seed(132564)

# Final model fitting on the full training dataset 
message("Fitting model to estimate variable importance.", Sys.time())
vi_fit <- 
  vi_wf %>%
  last_fit(data_split, metrics=class_and_probs_metrics) 




vi_data<-vi_fit%>%
  extract_fit_parsnip() %>%
  vi(method = "model") 
message("Variable Importance Model fit finished", Sys.time())

write_rds(vi_data, file=here("results","ranger",vi_file_name))
########################################################################################################
########################################################################################################



system("pkill -f 'while true.*top'", ignore.stdout = TRUE, ignore.stderr = TRUE)
message("CPU logger stopped")

cat("All done")


end_time<-Sys.time()
end_time

end_time-start_time
sessionInfo()
