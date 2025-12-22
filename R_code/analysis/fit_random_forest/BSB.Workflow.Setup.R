###############################################################################
# Purpose: 	Script to setup the BSB Workflow  This is reused across many estimation scripts

# I'm using the tidymodels framework to train and test the classification trees and
# random forest.  The main advantage is that switching models or estimation packages
# (partykit::ctree vs ranger vs randomForest for example) is easier. Writing the model 
# uses tidy syntax.  Tuning the model is made easier by using tune and yardstick.
# Fitting ranger requires bonsai.

# I use this many times when I run different models, so it's good to have it in 1 place 
###############################################################################  

 
#' Missing values are handled with the "na.learn" option (default). 
#' 
#' missing values are ignored for calculating an 
#' initial split criterion value (i.e., decrease of impurity). Then for the best 
#' split, all missings are tried in both child nodes and the choice is made based 
#' again on the split criterion value.
#' 
#' probability=FALSE. A probability forest (Malley et al 2012) might be a good idea
#' 
#' importance=NULL and splitrule=NULL.  This uses the Gini index as the impurity measure.
#' 
#' Geurts et al(2006)'s extremely random trees can be set with splitrule="extratrees".
#' 
#' trees=500. I don't have a good rationale for choose this.
#' 
#  respect.unordered.factors="order",

# configure the tuning part of the model.
tune_spec <- rand_forest(
  trees = 500,
  mtry = tune(),
  min_n = tune(),
) %>%
  set_mode("classification") %>%
  set_engine("ranger",
             num.threads=!!my.ranger.threads, 
             na.action="na.learn", 
             respect.unordered.factors="order",
             importance="permutation",
             oob.error = TRUE,
             keep.inbag=TRUE,
             probability = TRUE,
             write.forest=TRUE)
case_weights_allowed(tune_spec)


# Use a workflow that combines the data processing recipe, assigns weights, and the model configuation
BSB.Ranger.Workflow <-
  workflow() %>%
  add_model(tune_spec) %>% 
  add_recipe(BSB.Classification.Recipe) %>%
  add_case_weights(weighting)


hardhat::extract_parameter_set_dials(BSB.Ranger.Workflow)

# pass in a bunch of metrics
# if the recipe/workflow is case_weight aware, the metrics are also case-weight aware
class_and_probs_metrics <- metric_set(brier_class,mn_log_loss, roc_auc)


## Tuning
# 
# Set up a set of mtry to search over. 

# I have about 40 predictors, so I'll specify a coarse initial grid with 25 points, 
if  (search_type=="Initial"){
  rf_grid<-  param_grid <- grid_space_filling(
    mtry(range = c(1L, 30L)),           # Number of variables per split
    min_n(range = c(5L, 30L)),         # Minimum observations per node
    size = 12                          # Grid size for initial exploration
  )
  
}

# Overwite mtry rf_grid for testing=true to speed prototyping
if  (search_type=="Prototype"){
  rf_grid<-  param_grid <- grid_space_filling(
    mtry(range = c(2L, 10L)),           # Number of variables per split
    min_n(range = c(5L, 10L)),         # Minimum observations per node
    size = 4                          # Grid size for initial exploration
  )
}

