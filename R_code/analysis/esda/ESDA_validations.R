######  
#  **********************************************************************
#  * Purpose: 	Do some ESDA on my validation data to learn why the "North" isn't doing so great.
#  * Inputs:
#    - final_fit
#    - initial data_split    
#
#
# Outputs:
  
library("here")
# load tidyverse and related
library("tidyverse")
library("scales")
library("glue")
library("haven")
library("forcats")

library("tidymodels")
library("ranger")
library("bonsai")

# load utilities
library("knitr")
library("kableExtra")
library("viridis")

# Load data exploration
library("skimr")
library("DataExplorer")



# load tidyverse and related
#always load conflicted
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

here::i_am("R_code/analysis/esda/ESDA_validations.R")



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
  my.ranger.threads<-16
  
}


modeltype<-"South_NOC"
modeltype<-"North_NOC"



# You've estimated a few difference models, this sets the 
if (modeltype=="standard"){
  data_pattern<-"data_split"
  tuning_pattern<-"BSB_ranger_tune"
  final_pattern<-"BSB_ranger_results"
} else if (modeltype=="nocluster"){
  data_pattern<-"nocluster_data_split"
  tuning_pattern<-"BSB_ranger_nocluster_tune"
  final_pattern<-"BSB_ranger_nocluster_results"
}else if (modeltype=="fiveclass"){
  data_pattern<-"data_split_5_class"
  tuning_pattern<-"BSB_ranger_5class_tune"
  final_pattern<-"BSB_ranger_5class_results"
} else if (modeltype=="noc5class"){
  data_pattern<-"data_split_5_NOC_class"
  tuning_pattern<-"BSB_ranger_5_NOC_class_tune"
  final_pattern<-"BSB_ranger_5_NOC_class_results"
} else if (modeltype=="South_NOC"){
  data_pattern<-"nocluster_South_data_split"
  tuning_pattern<-"BSB_ranger_South_nocluster_tune"
  final_pattern<-"BSB_ranger_South_nocluster_results"
} else if (modeltype=="North_NOC"){
  data_pattern<-"nocluster_North_data_split"
  tuning_pattern<-"BSB_ranger_North_nocluster_tune"
  final_pattern<-"BSB_ranger_North_nocluster_results"
} else if (modeltype=="South_NOC_TEST"){
  data_pattern<-"nocluster_South_data_split_TEST"
  tuning_pattern<-"BSB_ranger_South_nocluster_tune_TEST"
  final_pattern<-"BSB_ranger_South_nocluster_results_TEST"
} else if (modeltype=="North_NOC_TEST"){
  data_pattern<-"nocluster_North_data_split_TEST"
  tuning_pattern<-"BSB_ranger_North_nocluster_tune_TEST"
  final_pattern<-"BSB_ranger_North_nocluster_results_TEST"
}else {
  stop("Unknown modeltype")
}











#traverse over to the DataPull repository
mega_dir<-dirname(here::here())
data_pull_dir<-file.path(mega_dir,"READ-SSB-Lee-BSB-DataPull")

lbs_per_mt<-2204.62
#############################################################################
my_images<-here("images")
descriptive_images<-here("images","descriptive")
exploratory_images<-here("images","exploratory")
#############################################################################

#############################################################################
# Data read in #
#############################################################################

# Load the saved model and data
data_vintage_string<-list.files(here("results","ranger"), pattern=glob2rx(glue("{data_pattern}*Rds")))
data_vintage_string<-gsub(data_pattern,"",data_vintage_string)
data_vintage_string<-gsub(".Rds","",data_vintage_string)
data_vintage_string<-max(data_vintage_string)

finalfit_vintage<-list.files(here("results","ranger"), pattern=glob2rx(glue("{final_pattern}*Rds")))
finalfit_vintage<-gsub(final_pattern,"",finalfit_vintage)
finalfit_vintage<-gsub(".Rds","",finalfit_vintage)
finalfit_vintage<-max(finalfit_vintage)


data_split<-readr::read_rds(file=here("results","ranger",glue("{data_pattern}{data_vintage_string}.Rds")))
final_fit<-read_rds(file=here("results","ranger",glue("{final_pattern}{finalfit_vintage}.Rds")))

#############################################################################
# END  Data read in #
#############################################################################


# Extract the fitted model, test data, training data
rf_model <- extract_fit_engine(final_fit)
test_data <- testing(data_split)
train_data <- training(data_split)


# Extract names of explanatory factors
recipe<-extract_recipe(final_fit)
vars<-recipe$var_info %>%
  filter(role=="predictor") %>%
  select(variable) %>%
  pull(variable)


# Get predictions on test data
test_predictions <- final_fit %>%
  collect_predictions() %>%
  bind_cols(test_data %>% select(-market_desc)) %>%
  mutate(weighting=as.numeric(weighting)) 


##########################################################################
# End Data Processing from data_prep_ml #
#############################################################################

# Skim 
skim_results<-skim(test_predictions)
skim_results

DateTime<-format(Sys.time(), "%Y_%m_%d_%H_%M_%S%Z")


configs<-configure_report(
  add_plot_scatterplot=FALSE,
  add_plot_density = TRUE,
    plot_qq_args = list(sampled_rows = 2000L),
  )

###########################################

# ESDA, grouped by predicted class 

# 
# test_predictions %>%
#   DataExplorer::create_report(
# output_file = here("R_code","analysis","esda",glue("{modeltype}_ESDA_by_predclass_{DateTime}")),
# report_title = glue("EDA Report - {modeltype} EDA by predicted class"),
#     y = ".pred_class",
#     config=configs
#   )

# output_file = here("R_code","analysis","esda",glue("{modeltype}_ESDA_by_predclass_{DateTime}")),
# report_title = glue("EDA Report - {modeltype} EDA by predicted class"),

#####################################
# This report looks decent.
# Bivariate distributions shows that there's some Larges that have moderately high predicted Medium and predicted Large.




######################################



# Correctly predicted Mediums
# Each case is evaluated sequentially and the first match for each element determines the corresponding value in the output vector
datacheck2<-test_predictions %>%
  mutate(investigate=case_when(
    .pred_class == "Medium" & market_desc == "Large" ~ "LasM",
    .pred_class == "Medium" & market_desc == "Jumbo" ~ "JasM",
    .pred_class == "Medium" & market_desc == "Medium" ~ "CMASM",
    .pred_class == "Large" & market_desc == "Jumbo" ~ "JasL",
    .pred_class == "Large" & market_desc == "Large" ~ "CLASL",
    .pred_class == "Jumbo" & market_desc == "Jumbo" ~ "CJASJ",
    .pred_class == market_desc ~ "OtherCorrect",
    .pred_class != market_desc ~ "OtherWrong",
    .default = "Unknown"
    )
  )


datacheck2<-datacheck2 %>%
  mutate(investigate=fct_relevel(investigate,c("CJASJ", "JasL","JasM","CLASL","LasM", "CMASM", "OtherCorrect", "OtherWrong","Unknown")) ) 



# datacheck2 %>%
#   DataExplorer::create_report(
# output_file = here("R_code","analysis","esda",glue("{modeltype}_ESDA_by_misclassifcation_{DateTime}")),
# report_title = glue("EDA Report - {modeltype} EDA by mis-classification"),
#     y = "investigate",
#     config=configs
#   )


# My Jumbo as Medium in the South is probably coming from 1 dealer. 


# Look at the scatterplot of .pred_Jumbo vs .pred_Large faceted by state
# In this plot, ideally all the Jumbo points are in the upper left, All the Large
# points are in the lower right, and all the Medium and Small points are at the origin.


ggplot(datacheck2, aes(x=.pred_Large, y=.pred_Jumbo, color=market_desc)) + 
  geom_jitter() + 
  facet_wrap(vars(state))


# In this plot, ideally all the Medium points are in the upper left, All the Large
# points are in the lower right, the Small points are at the origin or on the vertical axis.
# And all the Jumbos are on the origin/horizontal axis


ggplot(datacheck2, aes(x=.pred_Large, y=.pred_Medium, color=market_desc)) + 
  geom_jitter() + 
  facet_wrap(vars(state))


ggplot(datacheck2, aes(x=.pred_Small, y=.pred_Medium, color=market_desc)) + 
  geom_jitter() + 
  facet_wrap(vars(state))




# SOUTH
# a handful of DE Jumbos are predicted as Medium/Large.
# CT, MA, RI, NY has too few to say anything.
# This means my "South stockarea model" is basically a "DE, MD, NJ, NC, VA" model.
# RI is too thin.
# NC, NJ, have clouds in the center
# The Small graph isn't super informative.

# I should look at the "training" or complete data and do a kdensity of priceR_CPI by state and market_desc.
# 

datacheck3<-test_predictions %>%
  mutate(investigate=case_when(
    .pred_class == "Large" & market_desc == "Large" & .pred_Large<=0.6 ~ "LC_Large",
    .pred_class == "Jumbo" & market_desc == "Jumbo" & .pred_Jumbo<=0.6 ~ "LC_Jumbo",
    .pred_class == "Medium" & market_desc == "Medium" & .pred_Medium<=0.6 ~ "LC_Medium",
    .pred_class == "Large" & market_desc == "Large" & .pred_Large>0.4 ~ "HC_Large",
    .pred_class == "Jumbo" & market_desc == "Jumbo" & .pred_Jumbo>0.4 ~ "HC_Jumbo",
    .pred_class == "Medium" & market_desc == "Medium" & .pred_Medium>0.4 ~ "HC_Medium",
    .pred_class == market_desc ~ "OtherCorrect",
    .pred_class != market_desc ~ "OtherWrong",
    .default = "Unknown"
  )
  )

datacheck3<-datacheck3 %>%
  mutate(investigate=fct_relevel(investigate,
    c("HC_Jumbo", "LC_Jumbo","HC_Large","LC_Large","HC_Medium", "LC_Medium", "OtherCorrect", "OtherWrong"))
         ) 

datacheck3 %>%
  DataExplorer::create_report(
    output_file = here("R_code","analysis","esda",glue("{modeltype}_ESDA_by_Confidence_{DateTime}")),
    report_title = glue("EDA Report - {modeltype} EDA by classification confidence"),
    y = "investigate",
    config=configs
  )

