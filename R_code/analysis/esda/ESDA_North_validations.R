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
vintage_string <- "2025-08-07"  
final_fit <- read_rds(here("results", "ranger", glue("BSB_ranger_North_nocluster_results{vintage_string}.Rds")))
data_split <- read_rds(here("results", "ranger",glue("nocluster_North_data_split{vintage_string}.Rds")))
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


test_predictions %>%
  DataExplorer::create_report(
    output_file = here("R_code","analysis","esda",glue("North_ESDA_by_predclass_{DateTime}")),
    report_title = "EDA Report - North EDA by predicted class",
    y = ".pred_class",
    config=configs
  )


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



datacheck2 %>%
  DataExplorer::create_report(
    output_file = here("R_code","analysis","esda",glue("North_ESDA_by_misclassifcation_{DateTime}")),
    report_title = "EDA Report - North EDA by mis-classification",
    y = "investigate",
    config=configs
  )

# For all these sctter plots, we want observations at the corners (1,0) or (0,1) or (0,0)
# Next best is on the horizontal axis, vertical axis, or on the line with slope -1 that goes through
# the corners.


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


combined<-rbind(test_data, train_data)

ggplot(combined %>% filter(year==2024), aes(x=priceR_CPI,color=state)) + 
  geom_density() + 
  facet_wrap(vars(market_desc))

mean_prices<-combined  %>%
  group_by(market_desc, year, state) %>%
  summarise(mp=mean(priceR_CPI)) %>%
  filter(year==2018) %>%
  ungroup() %>%
  arrange(year,mp)




