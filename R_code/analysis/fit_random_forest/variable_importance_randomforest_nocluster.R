###############################################################################
# Purpose: 	Train the RF with the impurity_correction option to get VI metrics.   
# on DLRID for the validation. Unclassified are excluded.
# this assumes you have already trined a model using 
# tune_randomforest_nocluster.R

# Inputs:
#  - data_split (from tune_randomforest_nocluster.R)
#  - BSB.Classification.Recipe.R
#  - BSB.Workflow.Setup.R

# Outputs:
#  - final_fit results
#  - variable importance
###############################################################################  

library("here")

# load tidyverse and related
library("tidyverse")
library("scales")
library("glue")

# load tidyverse and related
library("tidymodels")
library("butcher")

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
library("vip")
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
here::i_am("R_code/analysis/fit_random_forest/variable_importance_randomforest_nocluster.R")

# Set these two to control the size of the dataset. Useful for making sure code 
# works.
#Set up model type
modeltype<-"nocluster"
# OR "nocluster", or "fiveclass", or "noc5class" OR "standard"

search_type<-"Advanced"
# search_type in "Initial", "Prototype","Advanced")


source(here("R_code","analysis","helpers","modeltype_patterns.R"))


# Only used with search_type<-"Prototype" -- how much data do you want in the dataset to prototype the code
testing_fraction<-1			  
start_time<-Sys.time()

#Turn bayesian tuning on or off.
bayes_tune<-"FALSE"

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
  my.ranger.sequential.threads<-24
  
  # Kill background logger if it is on
  system("pkill -f 'while true.*top'", ignore.stdout = TRUE, ignore.stderr = TRUE)
  message("CPU logger stopped")
  
  # start background logger
  source(here("R_code","analysis","helpers","background_logger.R"))
  
}
lbs_per_mt<-2204.62

lbs_per_mt<-2204.62
#############################################################################
my_images<-here("images")
descriptive_images<-here("images","descriptive")
exploratory_images<-here("images","exploratory")

#############################################################################
# Read in data and tuning results.
#############################################################################

# data vintage
vintage_string<-list.files(here("data_folder","main","commercial"), pattern=glob2rx("BSB_estimation_dataset*Rds"))
vintage_string<-gsub("BSB_estimation_dataset","",vintage_string)
vintage_string<-gsub(".Rds","",vintage_string)
data_vintage<-max(vintage_string)





#data_vintage<-as.character(Sys.Date())
################################################################################
# Read in data and tuning results.
################################################################################


# Pick up the most recent tuning
tuning_vintage<-list.files(here("results","ranger"), pattern=glob2rx(glue("{tuning_pattern}*.Rds")))
tuning_vintage<-gsub(tuning_pattern,"",tuning_vintage)
tuning_vintage<-gsub(".Rds","",tuning_vintage)
tuning_vintage<-max(tuning_vintage)

# Assemble file names to read in data, tuning results, and best_params.
# Although the source data has a different vintage, I'm loading in "data_split" which has the same vintage as the tuning
# The tuning and best_param already exist.
# the final fit and vi files will be created by this file. I'm choosing to use 
# the tuning date here, since the final fit and tuning go together.
data_save_name<-glue("{data_pattern}{tuning_vintage}.Rds")
tune_file_name<-glue("{tuning_pattern}{tuning_vintage}.Rds")
best_param_file_name<-glue("{best_param_pattern}{tuning_vintage}.Rds")

final_fit_file_name<-glue("{final_pattern}{tuning_vintage}.Rds")
vi_file_name<-glue("{vi_pattern}{tuning_vintage}.Rds")

data_split<-readr::read_rds(file=here("results","ranger",data_save_name))
train_data <- training(data_split)
rm(data_split)

nrow(train_data)
train_raw_rows<-nrow(train_data)


#expand by landed pounds 
#replacing "in place" so that there's no chance the recipe fits to the wrong data.
train_data<-train_data %>%
  select(-c(price,priceR_CPI, dlrid, myl_id)) %>%
  mutate(lndlb2=lndlb) %>%
  uncount(lndlb2)

train_expand_rows<-nrow(train_data)



message("Original training dataset :", train_raw_rows )
message("Training dataset rows (expanded):", train_expand_rows )


# # Recipe definition
# 
# The recipe simply defines the dataset, outcome (reponse, y) variable, id variables,
# and predictor variables.
source(here("R_code","analysis","fit_random_forest","BSB.Classification.Recipe.R"))

# Set up the tuning workflow
source(here("R_code","analysis","fit_random_forest","BSB.Workflow.Setup.R"))

# Read in best parameters.  Do a training on the full training dataset

#tune_res<-read_rds(file=here("results","ranger", tune_file_name))
best_params<-read_rds(file=here("results","ranger", best_param_file_name))

fold_results<-read_rds(file=here("results","ranger", glue("tuning_metrics_by_fold{tuning_vintage}.Rds")))
tm<-fold_results  %>%
  filter(.metric == "brier_class") %>%
  group_by(mtry, min_n, .config) %>%
  summarise(mt=mean(.estimate), .groups="drop_last")%>%
  arrange(mt)

selected_params<-tm[2,] %>%
  select(-mt)




############################################
# Final fit spec
# Use update to change trees, 
# finalize the model with best_params
vi_spec <- tune_spec %>%
  update(trees=20)%>%
  finalize_model(selected_params)

# I have to adjust the arguments this way or I have to rewrite the entire workflow
# Verbose=TRUE to monitor what is going on.
# save.memory slows it way down, but writes trees to disk to save on memory. I think I can comment out
vi_spec$eng_args$verbose<-rlang::quo(TRUE)
#vi_spec$eng_args$save.memory<-rlang::quo(TRUE)
vi_spec$eng_args$importance<-rlang::quo("impurity_corrected")
vi_spec$eng_args$write.forest<-rlang::quo(FALSE)




# finalize model by setting best model hyperparameters
vi_wf  <- BSB.Ranger.tuning.Workflow %>%
  update_model(vi_spec)
set.seed(132564)

# clean up
rm(BSB.Ranger.tuning.Workflow)
gc()

fit_control<-control_parsnip(verbosity = 2L, catch = FALSE)

# set.seed(132564)
# 
# Final model fitting on the full training dataset to estimate importance
message("Fitting model to estimate variable importance.", Sys.time())
vi_fit <-
  vi_wf %>%
  fit(train_data)

vi_fit_slim <- butcher(vi_fit)
rm(vi_fit)
gc()

message("Variable Importance Model fit finished", Sys.time())
# 
# 
# Pull the variable importance
 vi_data<-vi_fit_slim%>%
   extract_fit_parsnip() %>%
   vi(method = "model") 
# 
write_rds(vi_data, file=here("results","ranger",vi_file_name))
message("Variable Importance metrics saved", Sys.time())

########################################################################################################
########################################################################################################



system("pkill -f 'while true.*top'", ignore.stdout = TRUE, ignore.stderr = TRUE)
message("CPU logger stopped")





# PLOT




vi_data <- vi_data %>%
  #slice_max(Importance, n = 20) %>% # top 20 only at single-column width
  mutate(
    Variable = forcats::fct_reorder(Variable, Importance),
    Variable = forcats::fct_recode(Variable,
                                   "Price Difference Jumbo" = "Price_Diff_J",
                                   "Price Difference Large" = "Price_Diff_L",
                                   "Price Difference Medium" = "Price_Diff_M",
                                   "Dealer Propensity Small" = "LagSharePoundsSmall",
                                   "Dealer Propensity Medium" = "LagSharePoundsMedium",
                                   "Dealer Propensity Large" = "LagSharePoundsLarge",
                                   "Dealer Propensity Jumbo" = "LagSharePoundsJumbo",
                                   "Year" = "year",
                                   "Stockarea Catch Jumbo" = "MA7_StockareaQJumbo",
                                   "Stockarea Catch Large" = "MA7_StockareaQLarge",
                                   "Stockarea Catch Medium" = "MA7_StockareaQMedium",
                                   "Stockarea Catch Small" = "MA7_StockareaQSmall",
                                   "State Catch Jumbo" = "MA7_StateQJumbo",
                                   "State Catch Large" = "MA7_StateQLarge",
                                   "State Catch Medium" = "MA7_StateQMedium",
                                   "State Catch Small" = "MA7_StateQSmall",
                                   "Gear Catch Jumbo" = "MA7_gearQJumbo",
                                   "Gear Catch Large" = "MA7_gearQLarge",
                                   "Gear Catch Medium" = "MA7_gearQMedium",
                                   "Gear Catch Small" = "MA7_gearQSmall",
                                   "Transaction Weight" = "lndlb",
                                   "Stockarea Trips" = "MA7_stockarea_trips",
                                   "State Trips" = "MA7_state_trips"
    )
  )



p_vip <- ggplot(vi_data %>% slice_max(Importance, n=20), aes(x = Importance, y = Variable)) +
  geom_col(fill = "#1B6CA8", width = 0.7) +
  geom_vline(xintercept = 0, colour = "grey20", linewidth = 0.3) +
  scale_x_continuous(
    name   = "Mean Decrease Impurity (Corrected)",
    expand = expansion(mult = c(0, 0.05))
  ) +
  scale_y_discrete(name = NULL) +
  theme_bw(base_size = 9) +
  theme(
    panel.grid.major.y = element_blank(),
    panel.grid.minor   = element_blank(),
    panel.grid.major.x = element_line(colour = "grey88", linewidth = 0.3),
    axis.text.y        = element_text(size = 7, colour = "grey20"),
    axis.text.x        = element_text(size = 7, colour = "grey20"),
    axis.title.x       = element_text(size = 8),
    plot.margin        = margin(4, 6, 4, 4, "pt")
  )
p_vip
# --- 3. Save at ICES JMS single-column specification ---
ggsave(
  here("results", "ranger", "final",
       glue("vip{modeltype}{tuning_vintage}.pdf")),
  plot   = p_vip,
  width  = 84,
  height = 110,    # 20 bars fit cleanly; adjust in 5mm increments if needed
  units  = "mm",
  device = cairo_pdf
)



p_vip <- ggplot(vi_data,  aes(x = Importance, y = Variable)) +
  geom_col(fill = "#1B6CA8", width = 0.7) +
  geom_vline(xintercept = 0, colour = "grey20", linewidth = 0.3) +
  scale_x_continuous(
    name   = "Mean Decrease Impurity (Corrected)",
    expand = expansion(mult = c(0, 0.05))
  ) +
  scale_y_discrete(name = NULL) +
  theme_bw(base_size = 9) +
  theme(
    panel.grid.major.y = element_blank(),
    panel.grid.minor   = element_blank(),
    panel.grid.major.x = element_line(colour = "grey88", linewidth = 0.3),
    axis.text.y        = element_text(size = 7, colour = "grey20"),
    axis.text.x        = element_text(size = 7, colour = "grey20"),
    axis.title.x       = element_text(size = 8),
    plot.margin        = margin(4, 6, 4, 4, "pt")
  )

# --- 3. Save at ICES JMS single-column specification ---
ggsave(
  here("results", "ranger", "final",
       glue("vipFULL{modeltype}{tuning_vintage}.pdf")),
  plot   = p_vip,
  width  = 84,
  height = 110,    # 20 bars fit cleanly; adjust in 5mm increments if needed
  units  = "mm",
  device = cairo_pdf
)




cat("All done")


end_time<-Sys.time()
end_time

end_time-start_time
sessionInfo()
