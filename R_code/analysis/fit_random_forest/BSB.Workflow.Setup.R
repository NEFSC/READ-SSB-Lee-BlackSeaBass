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
#' trees=300. For tuning, it's fine to tune fewer trees.  The "rank order" of parameter combinations
#' stabiliizes pretty quickly, so cutting this down saves computation time.
#' 
#  respect.unordered.factors="order",

# configure the tuning part of the model.
tune_spec <- rand_forest(
  trees = 200,
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
             write.forest=TRUE) # default, but explicit


# Use a workflow that combines the data processing recipe, assigns weights, and the model configuation
BSB.Ranger.tuning.Workflow <-
  workflow() %>%
  add_model(tune_spec) %>% 
  add_recipe(BSB.Classification.Recipe) 


hardhat::extract_parameter_set_dials(BSB.Ranger.tuning.Workflow)

finalized_params <- BSB.Ranger.tuning.Workflow %>%
  extract_parameter_set_dials() %>%
  finalize(train_data) 

# pass in a bunch of metrics
# if the recipe/workflow is case_weight aware, the metrics are also case-weight aware
class_and_probs_metrics <- metric_set(brier_class,mn_log_loss, roc_auc)


## Tuning
# With uncounted() data, the min_n becomes "pounds" allocated to a grid. This is because  
# the replicated data will always end up in the same leaf/node.
# Set up a set of mtry to search over. 

if (search_type == "Initial") {
  
  finalized_params<-finalized_params %>%
    update(
    #  mtry = mtry(range = c(2L, 35L)),   # For the Initial, we can leave the upper bound as is.
      min_n=min_n(range = c(500L, 50000L))  # minimum points in a leaf node
    )
  
  rf_grid <- grid_space_filling(
    finalized_params,   
    size = 24                    # number of grid points for initial exploration
  )
}

# If the optimal is near the boundary, you need to expand the bounds (of mtry or min_n).   
# If some sections of the initial grid are clearly worse, you can tighten it up here.
# Note: The original grid was mtry (10-35) and min_n 500-50,000.
#    Both Brier class and mn_log_loss are not too sensitive to over a large portion of that mtry range
#      the bottom is probably in the 12-30 range.
# However, the optimal min_n was 500, suggesting that that was a bad grid.
# I will tighted up the grid
if (search_type == "Advanced") {
  finalized_params<-finalized_params %>%
    update(
      mtry = mtry(range = c(10L, 35L)),   # override upper bound after finalization
      min_n=min_n(range = c(50, 2000L))  # minimum points in a leaf/node
    )
  
  rf_grid <- grid_space_filling(
    finalized_params,   
    size = 60                    # number of grid points for initial exploration
  )
}


# Overwite mtry rf_grid for testing=true to speed prototyping


if (search_type == "Prototype") {
  finalized_params<-finalized_params %>%
    update(
      mtry = mtry(range = c(2L, 8L)),   # override upper bound after finalization
      min_n=min_n(range = c(500L, 10000L))  # minimum points in a leaf node
    )
  
  rf_grid <- grid_space_filling(
    finalized_params,   
    size = 4                    # number of grid points for initial exploration
  )    
}