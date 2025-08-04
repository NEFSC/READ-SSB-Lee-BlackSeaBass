###############################################################################
# Purpose: 	Script to setup the BSB classification Recipe. This is reused across many estimation scripts

# I'm using the tidymodels framework to train and test the classification trees and
# random forest.  The main advantage is that switching models or estimation packages
# (partykit::ctree vs ranger vs randomForest for example) is easier. Writing the model 
# uses tidy syntax.  Tuning the model is made easier by using tune and yardstick.
# Fitting ranger requires bonsai.
# Tiny bit of code to set up the BSB Classification Recipe. 

# I use this many times when I run different models, so it's good to have it in 1 place 
###############################################################################  

# assign roles to predictors, outcome, groups, and weights
BSB.Classification.Recipe <- recipe(train_data) %>%
  update_role(market_desc, new_role = "outcome")%>%
  update_role(c(dlrid,camsid, hullid, permit), new_role = "ID variable") %>%
  update_role(c(mygear,priceR_CPI,stockarea, state, year, month, semester, lndlb, grade_desc, trip_level_BSB, shore, nofederal), new_role = "predictor")

# State-level daily Landings on "other" trips, by market category  
BSB.Classification.Recipe <-BSB.Classification.Recipe %>%
  update_role(c(StateOtherQJumbo, StateOtherQLarge, StateOtherQMedium, StateOtherQSmall), new_role = "predictor") 

# stockarea-level daily Landings on "other" trips, by market category  
BSB.Classification.Recipe <-BSB.Classification.Recipe %>%
  update_role(c(StockareaOtherQJumbo, StockareaOtherQLarge, StockareaOtherQMedium, StockareaOtherQSmall), new_role = "predictor") 

# Trailing 7 days landings, by stockarea and market category   
BSB.Classification.Recipe <-BSB.Classification.Recipe %>%
  update_role(c(MA7_StockareaQJumbo, MA7_StockareaQLarge, MA7_StockareaQMedium, MA7_StockareaQSmall), new_role = "predictor")

# Trailing 7 days landings, by state and market category   
BSB.Classification.Recipe <-BSB.Classification.Recipe %>%
  update_role(c(MA7_StateQJumbo, MA7_StateQLarge, MA7_StateQMedium, MA7_StateQSmall), new_role = "predictor") 

# Trailing 7 day trips, by state and stock area.   
BSB.Classification.Recipe <-BSB.Classification.Recipe %>%
  update_role(c(MA7_stockarea_trips, MA7_state_trips), new_role = "predictor") 

# Trailing 7 day landing, by gear and market category    
BSB.Classification.Recipe <-BSB.Classification.Recipe %>%
  update_role(c(MA7_gearQJumbo, MA7_gearQLarge,MA7_gearQMedium, MA7_gearQSmall), new_role = "predictor") 



# Dealer share of landings by market category from 2013-2017   
BSB.Classification.Recipe <-BSB.Classification.Recipe %>%
  update_role(c(LagSharePoundsJumbo, LagSharePoundsLarge, LagSharePoundsMedium,LagSharePoundsSmall, LagSharePoundsUnclassified), new_role = "predictor") 

# Dealer transaction count of landings by market category from 2013-2017   

BSB.Classification.Recipe <-BSB.Classification.Recipe %>%
  update_role(c(LagShareTransJumbo, LagShareTransLarge, LagShareTransMedium,LagShareTransSmall, LagShareTransUnclassified), new_role = "predictor") 

# You can't center the factor variables
# rescale and recenter 
BSB.Classification.Recipe <- BSB.Classification.Recipe %>% 
#  step_impute_knn(all_predictors()) %>%
  step_center(all_numeric_predictors()) %>%
  step_scale(all_numeric_predictors())

recipe_summary<-BSB.Classification.Recipe %>%
  summary() %>%
  arrange(source,role, variable)

recipe_summary

#How many predictors
npredict<-nrow(recipe_summary %>% dplyr::filter(role=="predictor"))


