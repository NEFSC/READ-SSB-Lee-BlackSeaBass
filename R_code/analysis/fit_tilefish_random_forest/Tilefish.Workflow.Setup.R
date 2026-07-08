###############################################################################
# Purpose: 	Script to setup the Tilefish multinomimal regression Workflow  This can be is reused across many estimation scripts

# I'm using the tidymodels framework to train and test the classification trees and
# random forest.  The main advantage is that switching models or estimation packages
# (partykit::ctree vs ranger vs randomForest for example) is easier. Writing the model 
# uses tidy syntax.  Tuning the model is made easier by using tune and yardstick.
# Fitting ranger requires bonsai.

# I use this many times when I run different models, so it's good to have it in 1 place 
###############################################################################  

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
case_weights_allowed(tune_spec) 




# Use a workflow that combines the data processing recipe, assigns weights, and the model configuation
tilefish.multi.tuning.Workflow <-
  workflow() %>%
  add_model(tune_spec) %>% 
  add_recipe(Tile.Classification.Recipe) 


hardhat::extract_parameter_set_dials(tilefish.multi.tuning.Workflow)

finalized_params <- tilefish.multi.tuning.Workflow %>%
  extract_parameter_set_dials() %>%
  finalize(train_data) 

# pass in a bunch of metrics
# if the recipe/workflow is case_weight aware, the metrics are also case-weight aware
class_and_probs_metrics <- metric_set(brier_class,mn_log_loss, roc_auc)

# 
# 
# 
# if (search_type == "Initial") {
#   
#   finalized_params<-finalized_params %>%
#     update(
#     #  mtry = mtry(range = c(2L, 35L)),   # For the Initial, we can leave the upper bound as is.
#       min_n=min_n(range = c(50L, 50000L))  # minimum points in a leaf node
#     )
#   
#   rf_grid <- grid_space_filling(
#     finalized_params,   
#     size = 24                    # number of grid points for initial exploration
#   )
# }
# 
# # If the optimal is near the boundary, you need to expand the bounds (of mtry or min_n).   
# # If some sections of the initial grid are clearly worse, you can tighten it up here.
# if (search_type == "Advanced") {
#   finalized_params<-finalized_params %>%
#     update(
#       mtry = mtry(range = c(8L, 32L)),   # override upper bound after finalization
#       min_n=min_n(range = c(10L, 2500L))  # minimum points in a leaf/node
#     )
#   
#   rf_grid <- grid_space_filling(
#     finalized_params,   
#     size = 60                    # number of grid points for initial exploration
#   )
# }
# 
# 
# # Overwite mtry rf_grid for testing=true to speed prototyping
# 
# 
# if (search_type == "Prototype") {
#   finalized_params<-finalized_params %>%
#     update(
#       mtry = mtry(range = c(2L, 8L)),   # override upper bound after finalization
#       min_n=min_n(range = c(50L, 5000L))  # minimum points in a leaf node
#     )
#   
#   rf_grid <- grid_space_filling(
#     finalized_params,   
#     size = 4                    # number of grid points for initial exploration
#   )    
# }



# I have about 40 predictors, so I'll specify a coarse initial grid with 25 points, 
if (search_type == "Initial") {
  
  finalized_params<-finalized_params %>%
    update(
      mtry = mtry(range = c(5L, 35L)),   # override upper bound after finalization
      min_n=min_n(range = c(5L, 100))  # minimum points in a leaf node
    )
  
  rf_grid <- grid_space_filling(
    finalized_params,   
    size = 24                    # number of grid points for initial exploration
  )
}

# The initial grid search found an optimal min_n parameter on the boundary of my grid (min_n=100). 
# Very small mtry and min_n did poorly, so did mtry approaching the number of factors, so I've tightened up the boundaries of the grid a bit.
# And I've added 
if (search_type == "Advanced") {
  finalized_params<-finalized_params %>%
    update(
#     mtry = mtry(range = c(10L, 35L)),   # override upper bound after finalization
      min_n=min_n(range = c(10L, 300L))  # minimum points in a leaf nodee
    )
  
  rf_grid <- grid_space_filling(
    finalized_params,   
    size = 120                    # number of grid points for initial exploration
  )
}


# Overwite mtry rf_grid for testing=true to speed prototyping


if (search_type == "Prototype") {
  finalized_params<-finalized_params %>%
    update(
      mtry = mtry(range = c(2L, 8L)),   # override upper bound after finalization
      min_n=min_n(range = c(5L, 50L))  # minimum points in a leaf node
    )
  
  rf_grid <- grid_space_filling(
    finalized_params,   
    size = 4                    # number of grid points for initial exploration
  )    
}

