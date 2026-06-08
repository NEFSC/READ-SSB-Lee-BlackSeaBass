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
library("vip")		   
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


search_type<-"Prototype"
# search_type in "Initial", "Prototype","Advanced")


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
  my.ranger.sequential.threads<-22
  
  # Kill background logger if it is on
  system("pkill -f 'while true.*top'", ignore.stdout = TRUE, ignore.stderr = TRUE)
  message("CPU logger stopped")
  
  # start background logger
  source(here("R_code","analysis","helpers","background_logger.R"))
  
}
lbs_per_mt<-2204.62
# my.parallel.threads =4 and my.ranger.multi.threads=5  about 30 GB of RAM on the "full" dataset (~381,542 in the training set).

options(future.globals.maxSize = 2 * 1024^3)

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
if  (search_type=="Prototype"){
  data_save_name<-glue("TEST_nocluster_data_split{estimation_vintage}.Rds")
  tune_file_name<-glue("TEST_BSB_ranger_nocluster_tune{estimation_vintage}.Rds")
  final_fit_file_name<-glue("TEST_BSB_ranger_nocluster_results{estimation_vintage}.Rds")
  vi_file_name<-glue("TEST_BSB_ranger_nocluster_VI{estimation_vintage}.Rds")
  
  
}

data_split<-readr::read_rds(, file=here("results","ranger",data_save_name))
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


tune_res<-read_rds(file=here("results","ranger", tune_file_name))


tune_res %>%
  tune::collect_notes() %>%
  dplyr::filter(type == "error") %>%
  dplyr::select(location, note) %>%
  print(width = 200)


# Select the best Rforest based on log loss from the 10 folds.  Do a final fit on the full training dataset, predict on the validation dataset. Save the data

best_params <- tune_res %>%
  select_best(metric = "brier_class")

best_params



############################################
# Final fit spec
final_spec <- tune_spec %>%
  finalize_model(best_params) %>%
  set_engine("ranger",
             num.threads = !!my.ranger.sequential.threads, 
             na.action = "na.learn", 
             respect.unordered.factors = "order",
             importance = "none", # While I'd prefer permutation, that relies on OOB. Impurity corrected is better.  
             oob.error = FALSE,          # Kept OFF 
             keep.inbag = FALSE,         # Kept OFF to save memory
             probability = TRUE, 
             write.forest = TRUE)



# finalize model by picking the best model hyperparameters
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

vi_spec <- tune_spec %>%
  finalize_model(best_params) %>%
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
