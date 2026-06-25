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
library("butcher")
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

# Set these two to control the size of the dataset. Useful for making sure code 
# works.
#Set up model type
modeltype<-"nocluster"
# OR "nocluster", or "fiveclass", or "noc5class" OR "standard"

search_type<-"Advanced"
# search_type in "Initial", "Prototype","Advanced")


source(here("R_code","analysis","helpers","modeltype_patterns.R"))
source(here("R_code","analysis","helpers","predict_byhand.R"))


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
  my.ranger.sequential.threads<-24
  
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

prepped_recipe_file_name<-glue("{prepped_recipe}{tuning_vintage}.Rds")
calib_dataset_name<-glue("{calib_data_pattern}{tuning_vintage}.Rds")

# Read in best parameters.  Do a training on the full training dataset, predict on the calibration dataset. 

#tune_res<-read_rds(file=here("results","ranger", tune_file_name))
best_params<-read_rds(file=here("results","ranger", best_param_file_name))

fold_results<-read_rds(file=here("results","ranger", glue("tuning_metrics_by_fold{tuning_vintage}.Rds")))
tm<-fold_results  %>%
  filter(.metric == "brier_class") %>%
  group_by(mtry, min_n, .config) %>%
  summarise(mt=mean(.estimate), .groups="drop_last")%>%
  arrange(mt)

selected_params<-tm[2,] %>%
  select(-mt)
rm(fold_results)




data_split<-readr::read_rds(file=here("results","ranger",data_save_name))
# do not read in the test data

train_data <- training(data_split)
#calibration_data <- validation(data_split)
rm(data_split)

# train_data$rand<-runif(nrow(train_data))
# train_data<-train_data %>%
#  dplyr::filter(rand<=.05)%>%
#  select(-rand)


train_raw_rows<-nrow(train_data)

train_data<-train_data %>%
  select(-c(price,priceR_CPI, dlrid, myl_id))





# # Recipe definition
# 
# The recipe simply defines the dataset, outcome (reponse, y) variable, id variables,
# and predictor variables.
source(here("R_code","analysis","fit_random_forest","BSB.Classification.Recipe.R"))

# I need to handle the prep and bake the recipe manually, instead of using a workflow.

prepped_recipe <- prep(
  BSB.Classification.Recipe,
  training = train_data,
  retain   = FALSE        # <--save memory 
)

write_rds(prepped_recipe, file=here("results","ranger",prepped_recipe_file_name))

# I need to do the workflow manually to save memory
# Set up the tuning workflow
# source(here("R_code","analysis","fit_random_forest","BSB.Workflow.Setup.R"))


# configure the final_spec
final_spec <- rand_forest(
  trees = 500,
  mtry = tune(),
  min_n = tune(),
) %>%
  set_mode("classification") %>%
  set_engine("ranger",
             num.threads=!!my.ranger.sequential.threads, 
             na.action="na.learn", 
             respect.unordered.factors="order",
             importance="none", # default, but I don't need importance for tuning.
             oob.error = FALSE, # not used.
             keep.inbag=FALSE, # default, but explicit 
             probability = TRUE, # set to a probability model
             write.forest=TRUE,
             save.memory=TRUE,
             verbose=TRUE,  # default, but explicit 
             seed= 132564) %>% 
  finalize_model(selected_params) 

#Print the ranger call
translate(final_spec)

#Not currently used for training, but keeping it around
class_and_probs_metrics <- metric_set(brier_class,mn_log_loss, roc_auc)


#expand by landed pounds 
train_expanded<-train_data %>% 
  mutate(lndlb2=lndlb) %>%
  uncount(lndlb2)

train_raw_rows<-nrow(train_data)
train_expand_rows<-nrow(train_expanded)

message("Original training dataset :", train_raw_rows )
message("Training dataset rows (expanded):", train_expand_rows )

# Apply 
train_baked <- bake(
  prepped_recipe,
  new_data = train_expanded)


rm(train_data, train_expanded)
gc()
############################################

# Final model fitting on the baked dataset
message("Fitting final model:...")
final_ranger_fit <- ranger(
  market_desc ~ .,                              # outcome ~ all remaining columns
  data                      = train_baked,
  num.trees                 = 500,              # full 500 trees (memory budget allows)
  mtry                      = selected_params$mtry,
  min.node.size             = selected_params$min_n,
  probability               = TRUE,            # required: returns class probabilities
  num.threads              =  my.ranger.sequential.threads, 
  respect.unordered.factors = "order",
  na.action                 = "na.learn",
  importance                = "none",           # VI handled in a separate lighter fit
  save.memory               = FALSE,
  verbose                   = TRUE,
  seed                      = 132564
)

message("Final model fit finished.", Sys.time())
write_rds(final_ranger_fit, file=here("results","ranger",final_fit_file_name))

rm(train_baked)
gc()
# Augment by hand. Since final_ranger_fit is a ranger object, not a workflow, I have to 
# predict by hand and then bind into the original data
data_split<-readr::read_rds(file=here("results","ranger",data_save_name))

train_data <- training(data_split)
calibration_data <- validation(data_split)


train_preds<-predict_byhand(new_data=train_data,
                            prepped_recipe = prepped_recipe,
                            ranger_fitted_model  = final_ranger_fit)

#get the hard class prediction by picking the largest value
class <- colnames(train_preds)[max.col(train_preds, ties.method = "first")]
class<-as_tibble(class) %>%
  rename(.pred_class=value)

# Rename and bind columns
train_preds<-train_preds %>%
  rename_with(~ paste0(".pred_", .))

train_preds<-bind_cols(train_preds,train_data)


train_preds<-train_preds%>%
  mutate(weighting=hardhat::frequency_weights(lndlb)) 


# compute training metrics with yardstick
train_metrics <-  bind_rows(
  roc_auc(train_preds, truth = market_desc,
          starts_with(".pred_"),
          case_weights = weighting),
  mn_log_loss(train_preds, truth = market_desc,
              starts_with(".pred_"),
              case_weights = weighting),
  brier_class(train_preds, truth = market_desc,
              starts_with(".pred_"),
              case_weights = weighting)
)

message("Fit metrics on the training data:")
train_metrics
message("End Fit metrics")

train_preds<-bind_cols(class,train_preds)

################################################################################
# calibration predictions
 
# prediction using the validation data, bake with the prepped recipe
#prepped_recipe<-read_rds(file=here("results","ranger",prepped_recipe_file_name))


calib_preds<-predict_byhand(new_data=calibration_data,
                            prepped_recipe = prepped_recipe,
                            ranger_fitted_model  = final_ranger_fit)



#get the hard class prediction
calib_class <- colnames(calib_preds)[max.col(calib_preds, ties.method = "first")]
calib_class<-as.tibble(calib_class) %>%
  rename(.pred_class=value)


calib_preds<-calib_preds %>%
  rename_with(~ paste0(".pred_", .))

calib_preds<-bind_cols(calib_preds,calibration_data)


# print out the metrics

calib_preds <- calib_preds %>%
  mutate(weighting=hardhat::frequency_weights(lndlb)) 

calib_test_metrics <- bind_rows(
  roc_auc(calib_preds, truth = market_desc,
          starts_with(".pred_"),
          case_weights = weighting),
  mn_log_loss(calib_preds, truth = market_desc,
              starts_with(".pred_"),
              case_weights = weighting),
  brier_class(calib_preds, truth = market_desc,
              starts_with(".pred_"),
              case_weights = weighting)

)

message("Fit metrics on the calibration data")
calib_test_metrics

message("End Fit metrics")

# Save the calibration dataset 

calib_preds<-bind_cols(calib_class,calib_preds)

write_rds(calib_preds, file=here("results","ranger",calib_dataset_name))


message("End Training of Random Forest")
message("Next steps: Fit the variable importance model")
message("Next steps: Run the calibration routine.")





########################################################################################################
# Final fit with impurity_correction.  Permutation is better, but an uncount() handling of weighted observations makes the 
# OOB not truly "out of the bag".  Impurity corrected is the next best alternative, however it is not appropriate for predictions.
# Therefore, we fit the model once to get the proper variable importance, then we refit to get the true 'last model' for predictions.
########################################################################################################
# variable importance spec

# A threading note 
# here I'm fitting an RF on a single set of params (there's 1 mtry and 1 num_trees). I could run a multisession, but just allocating alot of threads to ranger will work fine too.
# 
# vi_spec <- final_spec
# # patch in impurity corrected
# vi_spec$eng_args$importance<-rlang::quo("impurity_corrected")
# 
#   
# # Update the workflow
# vi_wf  <- BSB.Ranger.tuning.Workflow %>%
#   update_model(vi_spec)
# 
# set.seed(132564)
# 
# # Final model fitting on the full training dataset to estimate importance
# message("Fitting model to estimate variable importance.", Sys.time())
# vi_fit <- 
#   vi_wf %>%
#   fit(train_data) 
# 
# message("Variable Importance Model fit finished", Sys.time())
# 
# 
# # Pull the variable importance
# vi_data<-vi_fit%>%
#   extract_fit_parsnip() %>%
#   vi(method = "model") 
# 
# write_rds(vi_data, file=here("results","ranger",vi_file_name))
# message("Variable Importance metrics saved", Sys.time())

########################################################################################################
########################################################################################################



system("pkill -f 'while true.*top'", ignore.stdout = TRUE, ignore.stderr = TRUE)
message("CPU logger stopped")

cat("All done")


end_time<-Sys.time()
end_time

sessionInfo()
