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
Tile.Classification.Recipe <- recipe(train_data) %>%
  update_role(market_desc, new_role = "outcome")%>%
  update_role(c(year, month), new_role = "predictor")

Tile.Classification.Recipe <- Tile.Classification.Recipe %>% 
    update_role(
      priceR_CPI, 
      mygear, 
      lndlb, 
      trip_level_tile,
      `LagSharePoundsExtra Large`,   
      `LagSharePoundsExtra Small`,  
      LagSharePoundsLarge,          
      `LagSharePoundsLarge/Medium`,       
      LagSharePoundsMedium,               
      `LagSharePoundsSmall Kitten`,      
      `LagSharePoundsExtra Small`, new_role = "predictor" )


recipe_summary<-Tile.Classification.Recipe %>%
  summary() %>%
  arrange(source,role, variable)

recipe_summary

#How many predictors
npredict<-nrow(recipe_summary %>% dplyr::filter(role=="predictor"))


