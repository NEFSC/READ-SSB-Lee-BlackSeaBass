
# I'm using the tidymodels framework to train and test the classification trees and
# Tiny bit of code to set up the BSB Workflow Recipe. 

# I use this many times when I run different models, so it's good to have it in 1 place 




#' # Model Definition and Baseline Fit
#' 
#' The model definition step declares the type of model (classification), engine (ranger), 
#' and any options.  For this section, I'm setting 500 trees in the RF, no fewer than 5
#' observations at the end of a branch, and 3 randomly selected variables.
#' 
#' I have left most of these options at their defaults. I'm noting things here 
#' 
#' Missing values are handled with the "na.learn" option (default). 
#' 
#' >With na.action = "na.learn", missing values are ignored for calculating an 
#' initial split criterion value (i.e., decrease of impurity). Then for the best 
#' split, all missings are tried in both child nodes and the choice is made based 
#' again on the split criterion value.
#' 
#' @Hastie2009: The first is applicable to categorical predictors: we simply make a new category for “missing.”
#' Second is construction of surrogate variables. When considering a predictor for a split, we use only the observations for which that predictor is not missing. Having chosen the best (primary) predictor and split point, we form a list of surrogate predictors and split points. The first surrogate is the predictor and corresponding split point that best mimics the split of the training data achieved by the primary split.  This is basically na.learn.
#' 
#' probability=FALSE. A probability forest (Malley et al 2012) might be a good idea
#' 
#' importance=NULL and splitrule=NULL.  This uses the Gini index as the impurity measure.
#' 
#' Geurts et al(2006)'s extremely random trees can be set with splitrule="extratrees".
#' 
#' trees=500. I don't have a good rationale for choose this.
#' 
#' Need to investigate the handling of the unordered factor covariates (@Hastie2009; Coppersmith et al 1999)
#' 
#' For an unordered predictor with $q$ levels, there are $2^{q-1}-1$ different ways to partition into two groups. This is not great.  For One way to handle this is to order the predictor levels in decreasing order of frequency and treat as if the factor was ordered.  This is proven to be the optimal way to handle unordered predictors for binary and quantitative (numeric) dependent variables.  It is not for multicategory outcomes @Hastie2009.
#' 
#' The partitioning algorithm tends to favor categorical predictors with many levels q; the number of partitions grows exponentially in q, and the more choices we have, the more likely we can find a good one for the data at hand. This can lead to severe overfitting if q is large, and such variables should be avoided @Hastie2009.
#' 
#'   * Coppersmith D., Hong S. J., Hosking J. R. (1999). Partitioning nominal attributes in decision
#' trees. Data Min Knowl Discov 3:197-217. doi:10.1023/A:1009869804967.



ranger_model<-rand_forest(mode="classification", trees = 500, min_n=5, mtry=3) %>%
  set_engine("ranger",num.threads=!!my.ranger.threads, na.action="na.learn", respect.unordered.factors="order", importance="impurity")


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
# Set up a set of mtry to search over. The nocluster grid needs to be a little bigger.

if (modeltype %in%c("standard","fiveclass")){
    mtry<-1:20
    mtry<-c(mtry,25,npredict)
    rf_grid<-as.data.frame(mtry)
  } else if  (modeltype %in%c("nocluster","noc5class")){
    mtry<-5:npredict
    rf_grid<-as.data.frame(mtry)
} else {
 stop("Unrecognized modeltype") 
}

# Overwite mtry rf_grid for testing=true to speed prototyping
if (testing==TRUE){
  mtry<-1:3
  rf_grid<-as.data.frame(mtry)
}
  
  






# configure the tuning part of the model.
tune_spec <- rand_forest(
  mtry = tune(),
  trees = 500,
  min_n = 5,
) %>%
  set_mode("classification") %>%
  set_engine("ranger",num.threads=!!my.ranger.threads, na.action="na.learn", respect.unordered.factors="order", importance="impurity")





# make a turning workflow. This combines the BSB.Classification.Recipe "data declaration" steps and new "tuning"
# steps as the model.
tune_wf <- workflow() %>%
  add_recipe(BSB.Classification.Recipe) %>%
  add_model(tune_spec)

hardhat::extract_parameter_set_dials(tune_wf)

# pass in a bunch of metrics
# if the recipe/workflow is case_weight aware, the metrics are also case-weight aware
class_and_probs_metrics <- metric_set(sensitivity, specificity, precision, bal_accuracy, mn_log_loss,average_precision, accuracy, brier_class, roc_auc)

