###############################################################################
# Purpose: 	Estimate a multinomial logit for tilefish categories

# I'm using the tidymodels framework to train and test the classification trees
# we can run a simple model with a logit and then easily switch to more sophisticaed models
# 
# Inputs:
#  - tile_estimation_dataset (from data_prep_ml.Rmd)
#  - tile_unclassified_dataset (from data_prep_ml.Rmd)
#  - Tilefish.Classification.Recipe.R
#  - Tilefish.Workflow.Setup.R

# Outputs:
#  - estimating dataset 
#  - tuning results 
###############################################################################  

library("here")

# load tidyverse and related
library("tidyverse")
library("scales")
library("glue")

# load tidyverse and related
library("tidymodels")

library("nnet")

# load utilities
library("knitr")
library("kableExtra")
library("viridis")
library("conflicted")
library("plotly")
library("htmlwidgets")
library("nnet")
library("ranger")
library("partykit")
library("bonsai")
library("vip")
library("probably")
library("discrim")
library("betacal")
library("janitor")


#3d plots
library("plotly")


#deal with conflicts
conflicts_prefer(dplyr::filter())
conflicts_prefer(dplyr::summary())
conflicts_prefer(dplyr::lag())
conflicts_prefer(purrr::discard())
conflicts_prefer(dplyr::group_rows())
conflicts_prefer(yardstick::spec())
conflicts_prefer(recipes::fixed())
conflicts_prefer(recipes::step())
conflicts_prefer(viridis::viridis_pal())
conflicts_prefer(vip::vi)
here::i_am("R_code/analysis/fit_tilefish_random_forest/fit_tilefish_classification.R")

# Set these two to control the size of the dataset. Useful for making sure code 
# works.
#Set up model type
modeltype<-"nocluster"
# OR "nocluster", or "fiveclass", or "noc5class" OR "standard"

search_type<-"Prototype"
# search_type in "Initial", "Prototype","Advanced")

# Only used with search_type<-"Prototype" -- how much data do you want in the dataset to prototype the code
testing_fraction<-1.0  
start_time<-Sys.time()

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
  my.ranger.sequential.threads<-23
  
  # Kill background logger if it is on
  system("pkill -f 'while true.*top'", ignore.stdout = TRUE, ignore.stderr = TRUE)
  message("CPU logger stopped")
  
  # start background logger
  source(here("R_code","analysis","helpers","background_logger.R"))
  
  
}
lbs_per_mt<-2204.62


# for reproducibility
#############################################################################
my_images<-here("images")
descriptive_images<-here("images","descriptive")
exploratory_images<-here("images","exploratory")
vintage_string<-list.files(here("data_folder","main","tilefish"), pattern=glob2rx("tilefish_estimation_dataset*Rds"))
vintage_string<-gsub("tilefish_estimation_dataset","",vintage_string)
vintage_string<-gsub(".Rds","",vintage_string)
vintage_string<-max(vintage_string)

#Tuning vintage is purposely set as "today"
tuning_vintage<-as.character(Sys.Date())

data_save_name<-glue("tilefish_data_split{tuning_vintage}.Rds")
tune_file_name<-glue("tilefish_tuning{tuning_vintage}.Rds")
best_param_file_name<-glue("tilefish_best_parameters{tuning_vintage}.Rds")
 
final_fit_file_name<-glue("tilefish_final{tuning_vintage}.Rds")
vi_file_name<-glue("tilefish_vi{tuning_vintage}.Rds")

# Load data from data_prep_ml.Rmd
estimation_dataset<-readr::read_rds(file=here("data_folder","main","tilefish",glue("tilefish_estimation_dataset{vintage_string}.Rds")))

set.seed(4587315)


# trim out the extra factor levels from market_desc.
estimation_dataset<-estimation_dataset %>%
  mutate(market_desc=fct_drop(market_desc))%>%
  select(-weighting)

estimation_dataset<-estimation_dataset %>%
  mutate(year=factor(year),
         month=factor(month))


# When testing, take a subset of the data. This is just to test how my code is working   
if  (search_type=="Prototype"){
  estimation_dataset$rand<-runif(nrow(estimation_dataset))
  estimation_dataset<-estimation_dataset %>%
    dplyr::filter(rand<=testing_fraction)
}

# 
# keep_cols<-c("market_desc","myl_id","dlrid","mygear","price","priceR_CPI", "stockarea","state", "year","month", "semester","lndlb", "grade_desc", "trip_level_BSB", "catch_share")
# keep_cols<-c(keep_cols,"shore","nofederal")
# keep_cols<-c(keep_cols,"StateOtherQJumbo", "StateOtherQLarge", "StateOtherQMedium", "StateOtherQSmall" )
# keep_cols<-c(keep_cols,"StockareaOtherQJumbo", "StockareaOtherQLarge", "StockareaOtherQMedium", "StockareaOtherQSmall" )
# keep_cols<-c(keep_cols,"MA7_StockareaQJumbo", "MA7_StockareaQLarge", "MA7_StockareaQMedium", "MA7_StockareaQSmall" )
# keep_cols<-c(keep_cols,"MA7_StateQJumbo", "MA7_StateQLarge","MA7_StateQMedium", "MA7_StateQSmall")
# keep_cols<-c(keep_cols,"MA7_gearQJumbo", "MA7_gearQLarge","MA7_gearQMedium", "MA7_gearQSmall")
# keep_cols<-c(keep_cols,"MA7_stockarea_trips", "MA7_state_trips" )
# 
# 
# estimation_dataset<- estimation_dataset %>%
#   select(all_of(keep_cols))

set.seed(2824)
# 80% of the data in the training, 5% in the calibration sample, 15% in the validation sample
# consider splitting on strata=market_desc, although I don't think this is strictly necessary. 
data_split <- initial_validation_split(
  data=estimation_dataset,
  prop = c(0.8, 0.05)
)
train_data <- training(data_split)
test_data <- testing(data_split)
validation_data <- validation(data_split)

readr::write_rds(data_split, file=here("results","ranger",data_save_name))

nrow(train_data)
nrow(test_data)
nrow(validation_data)

# Pick a subset of my training data to do my tuning.

set.seed(95976)


# Do some checks. How big are these datasets?
train_full_rows<-nrow(train_data)


# # Recipe definition
# 
# The recipe simply defines the dataset, outcome (reponse, y) variable, id variables,
# and predictor variables.
source(here("R_code","analysis","fit_tilefish_random_forest","Tilefish.Classification.Recipe.R"))

# Set up the workflow
source(here("R_code","analysis","fit_tilefish_random_forest","Tilefish.Workflow.Setup.R"))

set.seed(123)
# split the training data group wise into 10 folds with the same number of observations, 

myfolds<-vfold_cv(train_data, 
                        strata=market_desc, 
                        v = 10)

rf_control_grid<-control_grid(save_pred = TRUE, 
                              #verbose = TRUE, 
                              allow_par=FALSE)
start_time_tune<-Sys.time()

message("Tuning model hyperparameters", Sys.time())

tune_res <- tune_grid(
  tilefish.multi.tuning.Workflow,  
  resamples =  myfolds,
  grid = rf_grid,
  control=rf_control_grid,
  metrics=class_and_probs_metrics
)
message("Grid Tuning Finished at", Sys.time())

best_paramsA <- tune_res %>%
  select_best(metric = "brier_class")

best_paramsA

final_spec <- tune_spec %>%
  finalize_model(best_paramsA) %>%
  set_engine("ranger",
             num.threads = !!my.ranger.sequential.threads, 
             na.action = "na.learn", 
             respect.unordered.factors = "order",
             importance = "impurity_corrected", # While I'd prefer permutation, that relies on OOB. Impurity corrected is better.  
             oob.error = FALSE,          # Kept OFF 
             keep.inbag = FALSE,         # Kept OFF to save memory
             probability = TRUE, 
             write.forest = TRUE)




# finalize model by picking the best model hyperparameters
final_wf  <-    tilefish.multi.tuning.Workflow %>%
  update_model(final_spec)
set.seed(132564)

# Final model fitting on the full training dataset 
message("Fitting final model:...")
first_tilefish_model <- 
  final_wf %>%
  last_fit(data_split, metrics=class_and_probs_metrics)

write_rds(first_tilefish_model, file=here("results","ranger",final_fit_file_name))



run_this<-1

if (run_this==1){

  # Pulling the trained model out of the last_fit container
  trained_wf <- extract_workflow(first_tilefish_model)
  
  # using train data
first_train_predictions <- augment(trained_wf, new_data = train_data)

 # validation predictions using the extracted workflow
  first_validation_predictions <- augment(trained_wf, new_data = validation_data)
  
  
  
metrics_by_fold <- collect_metrics(tune_res, summarize = FALSE)  # fold-level
saveRDS(metrics_by_fold,  "tilefish_metrics_by_fold.Rds")
write_rds(metrics_by_fold, file=here("results","ranger", glue("Tilefish_folding_metrics_by_fold{tuning_vintage}.Rds")))

#rm(metrics_by_fold)


#Kill the logger, I'm done with the heavy lifting.
system("pkill -f 'while true.*top'", ignore.stdout = TRUE, ignore.stderr = TRUE)
message("CPU logger stopped")


cat("Tuning done")


# how well the model fits the training data.
# Look at the ROC curve, PR curve, and Confusion Matrix to evaluate model fit on training data.
# 1.probability names from the training predictions- plot the top 20- pending

prob_names <- colnames(first_train_predictions)
prob_names <- grep("^\\.pred_", prob_names, value = TRUE)
prob_names <- grep("^\\.pred_class", prob_names, value = TRUE, invert = TRUE)



# 2. PR Curve
final_pr <- first_train_predictions %>%
  pr_curve(market_desc, any_of(prob_names)) %>%
  autoplot()
print(final_pr)

# 3. ROC Curve
final_roc <- first_train_predictions %>%
  roc_curve(market_desc, any_of(prob_names)) %>%
  autoplot()
print(final_roc)

# 4.  Confusion Matrix
final_cm <- first_train_predictions %>%
  conf_mat(truth = market_desc, estimate = .pred_class) %>%
  autoplot(type = "heatmap")

print(final_cm)


# Validation Dataset


validation_data_preds <- augment(trained_wf, validation_data)


cal_gg <- validation_data_preds %>% 
  cal_plot_windowed(
    truth          = market_desc, 
    estimate       = c(`.pred_Extra Small`, `.pred_Small Kitten`, .pred_Medium, `.pred_Large/Medium`, .pred_Large, `.pred_Extra Large`), 
    step_size      = 0.025, 
    include_points = FALSE
  )


cal_data <- cal_gg$data



# Build publication-ready faceted calibration plot ---
p_cal <- ggplot(cal_data,
                aes(x = predicted_midpoint, y = event_rate)) +
  # perfect calibration reference line
  geom_abline(slope = 1, intercept = 0,
              linetype = "dashed", colour = "grey50", linewidth = 0.4) +
  # confidence band
  geom_ribbon(aes(ymin = lower, ymax = upper),
              fill = "#1B6CA8", alpha = 0.15) +
  # calibration curve
  geom_line(colour = "#1B6CA8", linewidth = 0.8) +
  facet_wrap(~ market_desc, ncol = )+
  scale_x_continuous(
    name   = "Mean Predicted Probability",
    limits = c(0, 1),
    breaks = seq(0, 1, 0.25),
    expand = expansion(mult = 0.01)
  ) +
  scale_y_continuous(
    name   = "Observed Event Rate",
    limits = c(0, 1),
    breaks = seq(0, 1, 0.25),
    expand = expansion(mult = 0.01)
  ) +
  coord_equal() +
  theme_bw(base_size = 9) +
  theme(
    strip.background = element_rect(fill = "grey92", colour = "grey40"),
    strip.text       = element_text(size = 8, face = "bold"),
    panel.grid.major = element_line(colour = "grey88", linewidth = 0.3),
    panel.grid.minor = element_blank(),
    axis.title       = element_text(size = 8),
    axis.text        = element_text(size = 7, colour = "grey20"),
    plot.margin      = margin(4, 6, 4, 4, "pt")
  )
p_cal



#Experiment with different methods of calibration.

validation_clean <- validation_data_preds %>%
  clean_names() %>%
  drop_na(market_desc, pred_extra_large, pred_extra_small)


# Beta
calibrate_beta <- cal_estimate_beta(
  validation_clean, 
  truth = market_desc, 
  estimate=pred_extra_large:pred_extra_small,
  smooth = FALSE
)

#  Isotonic Calibration
calibrate_iso <- cal_estimate_isotonic(
  validation_clean, 
  truth = market_desc, 
  estimate=pred_extra_large:pred_extra_small,
  smooth = FALSE
)

#  Multinomial Calibration
calibrate_multinom <- cal_estimate_multinomial(janitor::clean_names(validation_clean)
, truth=market_desc, estimate=pred_extra_large:pred_extra_small, smooth=FALSE)

# final judging is done on the 'testing' dataset, not here.

validation_data_isocalib_applied <-
  validation_clean %>%
  cal_apply(calibrate_iso)

validation_data_betacalib_applied <-
  validation_clean %>%
  cal_apply(calibrate_beta)

validation_data_multicalib_applied <-
  validation_clean %>%
  cal_apply(calibrate_multinom)




#Isotonic calibration plot
cal_gg <- validation_data_isocalib_applied %>%
  cal_plot_windowed(
    truth          = market_desc,
    estimate       = c(`pred_extra_small`, `pred_small_kitten`, pred_medium, `pred_large_medium`, pred_large, `pred_extra_large`), 
    step_size      = 0.025,
    include_points = FALSE
  )

# Extract data from the ggplot internals
cal_data <- cal_gg$data

# --- 2. Build publication-ready faceted calibration plot ---
iso_applied_window <- ggplot(cal_data,
                             aes(x = predicted_midpoint, y = event_rate)) +
  # perfect calibration reference line
  geom_abline(slope = 1, intercept = 0,
              linetype = "dashed", colour = "grey50", linewidth = 0.4) +
  # confidence band
  geom_ribbon(aes(ymin = lower, ymax = upper),
              fill = "#1B6CA8", alpha = 0.15) +
  # calibration curve
  geom_line(colour = "#1B6CA8", linewidth = 0.8) +
  facet_wrap(~ market_desc, ncol = )+
  scale_x_continuous(
    name   = "Mean Predicted Probability",
    limits = c(0, 1),
    breaks = seq(0, 1, 0.25),
    expand = expansion(mult = 0.01)
  ) +
  scale_y_continuous(
    name   = "Observed Event Rate",
    limits = c(0, 1),
    breaks = seq(0, 1, 0.25),
    expand = expansion(mult = 0.01)
  ) +
  coord_equal() +
  theme_bw(base_size = 9) +
  theme(
    strip.background = element_rect(fill = "grey92", colour = "grey40"),
    strip.text       = element_text(size = 8, face = "bold"),
    panel.grid.major = element_line(colour = "grey88", linewidth = 0.3),
    panel.grid.minor = element_blank(),
    axis.title       = element_text(size = 8),
    axis.text        = element_text(size = 7, colour = "grey20"),
    plot.margin      = margin(4, 6, 4, 4, "pt")
  )
iso_applied_window


# Other calibrations

#Multi
multi_applied_window <- cal_plot_windowed(
  validation_data_multicalib_applied, 
  truth = market_desc, 
  estimate = pred_extra_large:pred_extra_small, 
  step_size = 0.05, 
  include_points = FALSE
)

multi_applied_window


beta_applied_window <- cal_plot_windowed(
  validation_data_betacalib_applied, 
  truth = market_desc, 
  estimate = pred_extra_large:pred_extra_small, 
  step_size = 0.05, 
  include_points = FALSE
)

beta_applied_window


#BETA might look better- extra analysis
roc_dataUW <- validation_data_betacalib_applied %>% roc_curve(truth = market_desc, pred_extra_large:pred_extra_small)

roc_dataUW %>% 
  autoplot()

auc_data <- validation_data_betacalib_applied %>% 
  roc_auc(
    truth = market_desc, 
    pred_extra_large:pred_extra_small,      
    estimator = "macro"
  )

roc_data <- validation_data_betacalib_applied %>% 
  roc_curve(
    truth = market_desc, 
    pred_extra_large:pred_extra_small       
  )

p_facet <- ggplot(roc_data, aes(x = 1 - specificity, y = sensitivity)) + 
  geom_abline(slope = 1, intercept = 0, linetype = "dashed", colour = "grey50", linewidth = 0.4) + 
  geom_path(aes(colour = .level), linewidth = 0.8, show.legend = FALSE) + 
  facet_wrap(~ .level, ncol = 3) +                         # Changed to 3 columns to balance 6 panels nicely
  scale_colour_manual(values = class_colours) + 
  scale_x_continuous( 
    name = "1 \u2212 Specificity (False Positive Rate)", 
    limits = c(0, 1), 
    breaks = seq(0, 1, 0.25), 
    expand = expansion(mult = 0.01) 
  ) + 
  scale_y_continuous( 
    name = "Sensitivity (True Positive Rate)", 
    limits = c(0, 1), 
    breaks = seq(0, 1, 0.25), 
    expand = expansion(mult = 0.01) 
  ) + 
  coord_equal() + 
  theme_bw(base_size = 9) + 
  theme( 
    strip.background = element_rect(fill = "grey92", colour = "grey40"), 
    strip.text = element_text(size = 8, face = "bold"), 
    panel.grid.major = element_line(colour = "grey88", linewidth = 0.3), 
    panel.grid.minor = element_blank(), 
    axis.title = element_text(size = 8), 
    axis.text = element_text(size = 7, colour = "grey20"), 
    plot.margin = margin(4, 6, 4, 4, "pt") 
  )

# Print the plot
print(p_facet)





# Compute the Calibration Loss (from Ferrer and Ramos "Evaluating Posterior Probabilities")
# (ESPR_raw - ESPR_cal)/ESPR_raw

ESPR_raw<-validation_clean %>%
  mn_log_loss(market_desc, pred_extra_large:pred_extra_small) %>%
  pull(.estimate)

ESPR_caliso<-validation_data_isocalib_applied %>%
  mn_log_loss(market_desc, pred_extra_large:pred_extra_small) %>%
  pull(.estimate)

ESPR_calbeta<-validation_data_betacalib_applied %>%
  mn_log_loss(market_desc, pred_extra_large:pred_extra_small) %>%
  pull(.estimate)

ESPR_calmulti<-validation_data_multicalib_applied %>%
  mn_log_loss(market_desc, pred_extra_large:pred_extra_small) %>%
  pull(.estimate)

ESPR_raw
ESPR_caliso
ESPR_calbeta
ESPR_calmulti

CalLoss<-ESPR_raw-ESPR_caliso
rCalLoss<-100*CalLoss/ESPR_raw

CalLoss
rCalLoss

}


# Beta calibration fits better, curves look way nicer and closer to our dotted line. In addition, it is the one with the lower mn log loss value of 0.5690

# training workflow into testing data, does it look good with random forest and probabilities.

test_data_preds <- augment(trained_wf, new_data = test_data)

#Clean names to match lowercase 
test_clean <- test_data_preds %>% 
  janitor::clean_names() %>% 
  drop_na(market_desc, pred_extra_large:pred_extra_small)


# Applied pre-trained beta calibration tool to the test data
test_data_calibration_applied <- test_clean %>% 
  cal_apply(calibrate_beta)

# Extracted calibrated ggplot window metrics
calibrated <- cal_plot_windowed(
  test_data_calibration_applied, 
  truth = market_desc, 
  estimate = pred_extra_large:pred_extra_small,
  step_size = 0.05,
  include_points = FALSE
)

calibrated

cal_data <- calibrated$data

#publication-ready faceted calibration plot
p_cal_test_beta <- ggplot(cal_data, aes(x = predicted_midpoint, y = event_rate)) +
  # Perfect calibration 45-degree reference line
  geom_abline(slope = 1, intercept = 0, linetype = "dashed", colour = "grey50", linewidth = 0.4) +
  # Confidence bands (95% windows)
  geom_ribbon(aes(ymin = lower, ymax = upper), fill = "#1B6CA8", alpha = 0.15) +
  # Actual beta-calibrated performance curve
  geom_line(colour = "#1B6CA8", linewidth = 0.8) +
  # Dynamically facets across your 6 tilefish market categories
  facet_wrap(~ market_desc, ncol = 3) + 
  scale_x_continuous(
    name = "Mean Predicted Probability",
    limits = c(0, 1),
    breaks = seq(0, 1, 0.25),
    expand = expansion(mult = 0.01)
  ) +
  scale_y_continuous(
    name = "Observed Event Rate",
    limits = c(0, 1),
    breaks = seq(0, 1, 0.25),
    expand = expansion(mult = 0.01)
  ) +
  coord_equal() +
  theme_bw(base_size = 9) +
  theme(
    strip.background = element_rect(fill = "grey92", colour = "grey40"),
    strip.text = element_text(size = 8, face = "bold"),
    panel.grid.major = element_line(colour = "grey88", linewidth = 0.3),
    panel.grid.minor = element_blank(),
    axis.title = element_text(size = 8),
    axis.text = element_text(size = 7, colour = "grey20"),
    plot.margin = margin(4, 6, 4, 4, "pt")
  )

# Display
print(p_cal_test_beta)



#publication ready curves on uncalibrated
uncal_data <- uncalibrated$data

# Plot the "raw" uncalibrated predictions for comparison
uncalibrated <- cal_plot_windowed(
  test_clean, 
  truth = market_desc,
  estimate = pred_extra_large:pred_extra_small,
  step_size = 0.05,
  include_points = FALSE
)
uncalibrated


# 2. Build publication-ready faceted calibration plot for raw predictions
p_uncal <- ggplot(uncal_data, aes(x = predicted_midpoint, y = event_rate)) +
  # perfect calibration reference line
  geom_abline(slope = 1, intercept = 0, linetype = "dashed", colour = "grey50", linewidth = 0.4) +
  # confidence band
  geom_ribbon(aes(ymin = lower, ymax = upper), fill = "#1B6CA8", alpha = 0.15) +
  # calibration curve
  geom_line(colour = "#1B6CA8", linewidth = 0.8) + 
  # Set to 3 columns to balance your 6 tilefish market categories cleanly
  facet_wrap(~ market_desc, ncol = 3) + 
  scale_x_continuous(
    name = "Mean Predicted Probability",
    limits = c(0, 1),
    breaks = seq(0, 1, 0.25),
    expand = expansion(mult = 0.01)
  ) +
  scale_y_continuous(
    name = "Observed Event Rate",
    limits = c(0, 1),
    breaks = seq(0, 1, 0.25),
    expand = expansion(mult = 0.01)
  ) +
  coord_equal() +
  theme_bw(base_size = 9) +
  theme(
    strip.background = element_rect(fill = "grey92", colour = "grey40"),
    strip.text = element_text(size = 8, face = "bold"),
    panel.grid.major = element_line(colour = "grey88", linewidth = 0.3),
    panel.grid.minor = element_blank(),
    axis.title = element_text(size = 8),
    axis.text = element_text(size = 7, colour = "grey20"),
    plot.margin = margin(4, 6, 4, 4, "pt")
  )

# Explicitly print the plot to your active viewer session
print(p_uncal)


# ROC CALIBRATED
roc_dataUW <- test_data_calibration_applied %>% 
  roc_curve(
    truth = market_desc, 
    pred_extra_large:pred_extra_small
  )
roc_dataUW %>% autoplot()


# Area Under the ROC Curve (AUC) # does it mean it does a good job guessing? 
auc_data <- test_data_calibration_applied %>% 
  roc_auc(
    truth = market_desc, 
    pred_extra_large:pred_extra_small, 
    estimator = "macro"
  )
auc_data

# 0.959 was the given value



# 3. Colour palette adjusted exactly for your 6 tilefish market categories
# Note: Level names match the exact string names inside the .level column of roc_dataUW
class_colours <- c(
  "Extra Small"   = "#7B3F9E", # purple
  "Small Kitten"  = "#E05C2A", # burnt orange
  "Medium"        = "#2E8B57", # sea green
  "Large/Medium"  = "#D4AF37", # gold/dark yellow
  "Large"         = "#1B6CA8", # deep blue
  "Extra Large"   = "#C0392B"  # deep red
)

# 4. Build the unweighted multi-class ROC facet plot
p_facetUW <- ggplot(roc_dataUW, aes(x = 1 - specificity, y = sensitivity)) + 
  geom_abline(slope = 1, intercept = 0, linetype = "dashed", colour = "grey50", linewidth = 0.4) + 
  geom_path(aes(colour = .level), linewidth = 0.8, show.legend = FALSE) + 
  # Arranged in 3 columns to spread out your 6 market levels symmetrically into a 2x3 grid
  facet_wrap(~ .level, ncol = 3) + 
  scale_colour_manual(values = class_colours) + 
  scale_x_continuous( 
    name = "1 \u2212 Specificity (False Positive Rate)", 
    limits = c(0, 1), 
    breaks = seq(0, 1, 0.25), 
    expand = expansion(mult = 0.01) 
  ) + 
  scale_y_continuous( 
    name = "Sensitivity (True Positive Rate)", 
    limits = c(0, 1), 
    breaks = seq(0, 1, 0.25), 
    expand = expansion(mult = 0.01) 
  ) + 
  coord_equal() + 
  theme_bw(base_size = 9) + 
  theme( 
    strip.background = element_rect(fill = "grey92", colour = "grey40"), 
    strip.text = element_text(size = 8, face = "bold"), 
    panel.grid.major = element_line(colour = "grey88", linewidth = 0.3), 
    panel.grid.minor = element_blank(), 
    axis.title = element_text(size = 8), 
    axis.text = element_text(size = 7, colour = "grey20"), 
    plot.margin = margin(4, 6, 4, 4, "pt") 
  )

# Explicitly print the ROC graphic to your viewing window
print(p_facetUW)

# calibration gains
ESPR_raw <- test_clean %>% 
  mn_log_loss(market_desc, pred_extra_large:pred_extra_small) %>% 
  pull(.estimate)

ESPR_cal <- test_data_calibration_applied %>% 
  mn_log_loss(market_desc, pred_extra_large:pred_extra_small) %>% 
  pull(.estimate)

ESPR_raw
ESPR_cal

CalLoss <- ESPR_raw - ESPR_cal
rCalLoss <- 100 * CalLoss / ESPR_raw

# beta  calibration improves model fit a bit.
CalLoss
rCalLoss

# raw model scored 0.6138704 and calibrated went down to 0.5619904
# rCalLoss 8.45% improvement


# Next steps-

#make the calibrated predictions with train data
# with calibration applied


































# mapping nespp4 codes, 2007
# join key into lengths, explore combined datasets, explore 2007



lengths <- readr::read_csv(file = here("data_folder", "main", "tilefish", "tilefish_lengths2007.csv"))

key <- readr::read_csv(file = here("data_folder", "main", "tilefish", "tilefish_keyfile.csv"))



