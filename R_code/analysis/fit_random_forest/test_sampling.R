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


bayes_tune<-"FALSE"

search_type<-"Initial"
# search_type in "Initial", "Prototype","Advanced")

# Only used with search_type<-"Prototype" -- how much data do you want in the dataset to prototype the code
testing_fraction<-1			  
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
library("vip")
library("gtsummary")
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
here::i_am("R_code/analysis/fit_random_forest/test_sampling.R")

message("Start Time is :       ", Sys.time())


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
  
  
}
my.ranger.threads<-5
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
  data_save_name<-glue("nocluster_data_split_TEST{estimation_vintage}.Rds")
  tune_file_name<-glue("BSB_ranger_nocluster_tune_TEST{estimation_vintage}.Rds")
  final_fit_file_name<-glue("BSB_ranger_nocluster_results_TEST{estimation_vintage}.Rds")
  vi_file_name<-glue("BSB_ranger_nocluster_VI_TEST{estimation_vintage}.Rds")
  
  
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
estimation_dataset<-readr::read_rds(file=here("data_folder","main","commercial",glue("BSB_estimation_dataset{vintage_string}.Rds")))


# for reproducibility
set.seed(4587315)


# construct the "case weights" variable here and trim out the extra factor levels from market_desc.
estimation_dataset<-estimation_dataset %>%
     mutate(weighting = as.integer(weighting),
            market_desc=fct_drop(market_desc))

# When testing, take a subset of the data. This is just to test how my code is working   
if  (search_type=="Prototype"){
  estimation_dataset$rand<-runif(nrow(estimation_dataset))
  estimation_dataset<-estimation_dataset %>%
    dplyr::filter(rand<=testing_fraction)
}


keep_cols<-c("market_desc","myl_id","dlrid", "mygear","price","priceR_CPI", "stockarea","state", "year","month", "semester","lndlb", "grade_desc", "trip_level_BSB", "catch_share")
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
df_train <- training(data_split)
df_val <- validation(data_split)
df_test <- testing(data_split)

nrow(df_train)
nrow(df_test)
nrow(df_val)

# Now, I want to subsample the training set. Part 1 will be for tuning, then I will use the entire dataset to fit the model
# tuning isn't very sensitive, but I still want to make sure my dataset is representative.

tune_split_prop<-0.05
data_split2<-initial_split(
  data=df_train,
  prop= tune_split_prop)

df_tune1 <- training(data_split2)
df_held_out <- testing(data_split2)


df_combined <- bind_rows(
  df_tune1 %>% mutate(split_group = "Train"),
  df_held_out %>% mutate(split_group = "HeldOut")
)
library(dplyr)
library(tidyr)

# Assume your dataset is 'df_combined' and your weights are in 'my_weights'
# Continuous: income, age
# Categorical: industry_code

# ---------------------------------------------------------
# 1. Process Continuous Variables (Weighted Means)
# ---------------------------------------------------------
cont_vars<-c("price","priceR_CPI", "trip_level_BSB","Price_Diff_J", "LagSharePoundsLarge")
cont_summary <- df_combined %>%
  group_by(split_group) %>%
  summarize(
    # across() applies the weighted mean to your specified continuous columns
    across(
      any_of(cont_vars), 
      ~ weighted.mean(.x, w = lndlb, na.rm = TRUE)
    ),
    .groups = "drop"
  ) %>%
  # Reshape data so variables are in rows, and split groups are columns
  pivot_longer(cols = -split_group, names_to = "Variable", values_to = "Value") %>%
  mutate(Metric = "Weighted Mean") %>%
  pivot_wider(names_from = split_group, values_from = Value)

cont_summary<-cont_summary %>%
  mutate(pct_diff=(HeldOut-Train)/Train)

# ---------------------------------------------------------
# 2. Process Categorical Variables (Weighted Counts)
# ---------------------------------------------------------
cat_vars<-c("market_desc", "state", "year","month", "semester", "mygear","catch_share")

cat_summary <- df_combined %>%
  
  select(split_group, lndlb, any_of(cat_vars)) %>%
  
  mutate(across(any_of(cat_vars), as.character)) %>%
  # Collapse all categorical variables into a 'long' format
  pivot_longer(
    cols = any_of(cat_vars),
    names_to = "Variable_Name",
    values_to = "Level"
  ) %>%
  
  # Group by the split, the variable name, and the specific level, then sum the weights
  group_by(split_group, Variable_Name, Level) %>%
  summarize(Value = sum(lndlb, na.rm = TRUE), .groups = "drop") %>%
  
  # Format the text to match the continuous table architecture exactly
  mutate(
    Variable = paste0(Variable_Name, ": ", Level),
    Metric = "Weighted Count"
  ) %>%
  select(split_group, Variable, Metric, Value) %>%
  
  
  pivot_wider(names_from = split_group, values_from = Value, values_fill = 0)

# fraction train should be close to the proportion from data_split2 (5%)

cat_summary<-cat_summary %>%
  mutate(fraction_train=Train/(Train+HeldOut)) %>%
  mutate(problems=abs(fraction_train-tune_split_prop))  %>%
  arrange(-problems)
  
# View the result
print(cat_summary)

print(cont_summary)



# look at pounds




ggplot(data = df_combined %>% filter(lndlb<=1000), aes(x = lndlb)) + 
       geom_histogram(aes(y = after_stat(density),fill=split_group))


uncounted<-df_combined %>%
  mutate(lnd2=lndlb) %>%
  uncount(weights=lnd2)


ggplot(data = uncounted %>% filter(lndlb<=1000), aes(x = lndlb)) + 
  geom_histogram(aes(y = after_stat(density),fill=split_group))



ks_result <- ks.test(
  x = df_tune1$lndlb,
  y = df_held_out$lndlb
)
print(ks_result)



# 1. Construct the Adversarial Dataset
uncounted<-uncounted%>%
  # CRITICAL: drop your original target variable
  select(-market_desc)

# Create 5-fold cross-validation specifically for the adversarial test
adv_folds <- vfold_cv(uncounted, v = 5)

# 2. Define the Models (Logistic and Default Ranger RF)
# log_spec <- logistic_reg() %>%
#   set_engine("glm") %>%
#   set_mode("classification")

rf_spec <- rand_forest() %>% # Default trees, mtry, and min_n
  set_engine("ranger",
             num.threads=20, 
             na.action="na.learn", 
             respect.unordered.factors="order",
             importance="none", # default, but I don't need importance for tuning.
             oob.error = FALSE, # not used.
             keep.inbag=FALSE, # default, but explicit 
             probability = TRUE, # set to a probability model
             write.forest=FALSE) %>%# default, but explicit
set_mode("classification")

# 3. Create the Processing Recipe
# Logistic regression requires dummy variables; trees technically don't, 
# but it's easier to use one recipe for both here.
adv_rec <- recipe(split_group ~ ., data = uncounted) %>%
  step_unknown() %>%
  step_novel() %>%
  step_zv(all_predictors()) # Strips out constants (zero-variance)


# 5. Fit and Evaluate Random Forest
 rf_res <- fit_resamples(
   workflow(adv_rec, rf_spec),
   resamples = adv_folds,
   metrics = metric_set(roc_auc)
 )
# 
# # 6. Check the Results
# #log_auc <- collect_metrics(log_res)$mean
# rf_auc <- collect_metrics(rf_res)$mean
# 
# #cat("Adversarial Logistic Regression AUC: ", log_auc, "\n")
# cat("Adversarial Random Forest AUC (should be ~0.5):       ", rf_auc, "\n")
# 
# message("End Time is :       ", Sys.time() )
# 
# 




