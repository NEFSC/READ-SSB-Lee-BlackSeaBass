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



ranger_model<-rand_forest(mode="classification", trees = 500, min_n=5, mtry=3) %>%
  set_engine("ranger",
             num.threads=!!my.ranger.threads, 
             na.action="na.learn", 
             respect.unordered.factors="order",
             importance="impurity",
             oob.error = TRUE,
             keep.inbag=TRUE,
             write.forest=TRUE,
             proximity = TRUE,
             probability = TRUE) 


case_weights_allowed(ranger_model)


# Use a workflow that combines the data processing recipe, assigns weights, and the model configuation
BSB.Ranger.Workflow <-
  workflow() %>%
  add_model(ranger_model) %>% 
  add_recipe(BSB.Classification.Recipe)


# BSB.cf.Workflow <-
#   workflow() %>%
#   add_model(cf_model) %>% 
#   add_recipe(BSB.Classification.Recipe)




## Tuning
# 
# Set up a set of mtry to search over. 

# I have about 40 predictors, so I'll specify a coarse initial grid, 
if  (search_type=="Initial"){
  mtry<-round(seq(1,npredict,length.out=15))
  rf_grid<-as.data.frame(mtry)
}

if  (search_type=="Final"){
  
  # Custom Grid 
  if (modeltype=="standard"){
    mtry<-seq(26,41)
    rf_grid<-as.data.frame(mtry)
    
  } else if (modeltype=="nocluster"){
    mtry<-seq(25,npredict)
    rf_grid<-as.data.frame(mtry)
    
  }else if (modeltype=="fiveclass"){
  } else if (modeltype=="noc5class"){
  } else if (modeltype=="South_NOC"){
    mtry<-seq(25,npredict)
    rf_grid<-as.data.frame(mtry)
  } else if (modeltype=="North_NOC"){
    mtry<-seq(26,npredict)
    rf_grid<-as.data.frame(mtry)
    }else {
    stop("Unknown modeltype")
  }
}


# Overwite mtry rf_grid for testing=true to speed prototyping
if  (search_type=="Prototype"){
  mtry<-c(2,5,15,npredict)
  rf_grid<-as.data.frame(mtry)
}
  
  






# configure the tuning part of the model.
tune_spec <- rand_forest(
  mtry = tune(),
  trees = 500,
  min_n = 5,
) %>%
  set_mode("classification") %>%
  set_engine("ranger",
             num.threads=!!my.ranger.threads, 
             na.action="na.learn", 
             respect.unordered.factors="order",
             importance="impurity",
             oob.error = TRUE,
             keep.inbag=TRUE,
             proximity = TRUE,
             probability = TRUE,
             write.forest=TRUE)





# make a turning workflow. This combines the BSB.Classification.Recipe "data declaration" steps and new "tuning"
# steps as the model.
tune_wf <- workflow() %>%
  add_recipe(BSB.Classification.Recipe) %>%
  add_model(tune_spec)

hardhat::extract_parameter_set_dials(tune_wf)

# pass in a bunch of metrics
# if the recipe/workflow is case_weight aware, the metrics are also case-weight aware
class_and_probs_metrics <- metric_set(sensitivity, specificity, precision, bal_accuracy, mn_log_loss,average_precision, accuracy, brier_class, roc_auc)

