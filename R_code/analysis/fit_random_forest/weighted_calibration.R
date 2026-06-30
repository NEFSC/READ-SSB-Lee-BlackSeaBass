



search_type<-"Advanced"
modeltype<-"nocluster"


library("here")

# load tidyverse and related
library("tidyverse")
library("scales")
library("ggrepel")
# load tidyverse and related
library("tidymodels")

# load machine learning and estimation tools
library("nnet")
library("ranger")
library("bonsai")
library("probably")
library("discrim")

# load utilities
library("knitr")
library("kableExtra")
library("viridis")
library("glue")

#3d plots
library("htmlwidgets")
library("plotly")

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

here::i_am("R_code/analysis/fit_random_forest/weighted_calibration.R")

# modeltype_patterns.R defines all file-naming pattern variables (data_pattern,
# tuning_pattern, final_pattern, vi_pattern, prepped_recipe string, prob_names, etc.)
# predict_byhand.R defines the predict_byhand() wrapper used throughout.
source(here("R_code","analysis","helpers","modeltype_patterns.R"))
source(here("R_code","analysis","helpers","predict_byhand.R"))



lbs_per_mt<-2204.62
#############################################################################
my_images<-here("images")
descriptive_images<-here("images","descriptive")
exploratory_images<-here("images","exploratory")


###############################################################
# Vintage resolution: scan results and data directories to identify the most
# recent versioned file for each object type. For each object type , matching
# filenames are listed, the known prefix and ".Rds" suffix are stripped, and
# max() of the remaining date/version strings picks the latest.
# finalfit_vintage and VI_vintage are set equal to tuning_vintage by
# construction; the upstream tuning/training code guarantees they are in sync.
###############################################################
data_vintage_string<-list.files(here("results","ranger"), pattern=glob2rx(glue("{data_pattern}*Rds")))
data_vintage_string<-gsub(data_pattern,"",data_vintage_string)
data_vintage_string<-gsub(".Rds","",data_vintage_string)
data_vintage_string<-max(data_vintage_string)

tuning_vintage<-list.files(here("results","ranger"), pattern=glob2rx(glue("{tuning_pattern}*Rds")))
tuning_vintage<-gsub(tuning_pattern,"",tuning_vintage)
tuning_vintage<-gsub(".Rds","",tuning_vintage)
tuning_vintage<-max(tuning_vintage)

# Tuning, training, VI code guarantees that the finalfit and VI vintages are the same as the tuning vintages.  

finalfit_vintage<-tuning_vintage
VI_vintage<-tuning_vintage


final_fit_file_name<-glue("{final_pattern}{tuning_vintage}.Rds")
vi_file_name<-glue("{vi_pattern}{tuning_vintage}.Rds")
prepped_recipe_file_name<-glue("{prepped_recipe}{tuning_vintage}.Rds")


vintage_string<-list.files(here("data_folder","main","commercial"), pattern=glob2rx("BSB_estimation_dataset*Rds"))

raw_oos_data_vintage_string<-list.files(here("data_folder","main","commercial"), pattern=glob2rx("BSB_unclassified_dataset*Rds"))
raw_oos_data_vintage_string<-gsub("BSB_unclassified_dataset","",raw_oos_data_vintage_string)
raw_oos_data_vintage_string<-gsub(".Rds","",raw_oos_data_vintage_string)
raw_oos_data_vintage_string<-max(raw_oos_data_vintage_string)

###############################################################
# Load in data
###############################################################
# # this was created with data_prep_ml.Rmd
data_split<-readr::read_rds(file=here("results","ranger",glue("{data_pattern}{data_vintage_string}.Rds")))
# Onlyneed the test and validation 
train_data <- training(data_split)
validation_data <- validation(data_split)
test_data <- testing(data_split)

# recreate the frequency weights variables
# lndlb (landed pounds per transaction) serves as a frequency/case weight
# throughout; high-volume transactions receive proportionally more influence
# in all subsequent weighted metrics.
validation_data<-validation_data %>%
  mutate(weighting=frequency_weights(lndlb))
test_data<-test_data %>%
  mutate(weighting=frequency_weights(lndlb))

prepped_recipe<-read_rds(file=here("results","ranger",prepped_recipe_file_name))

final_ranger_fit<-read_rds(file=here("results","ranger",glue("{final_pattern}{tuning_vintage}.Rds")))

################################################################################
# Generate class-probability predictions on the validation set via the custom
# predict_byhand() wrapper (applies prepped_recipe before calling ranger).
# The modal predicted class is extracted by finding the column with the highest
# probability for each row, then bound back alongside the raw probabilities
# and original validation data.

#predict
class_levels <- c("Jumbo", "Large", "Medium", "Small")
validation_preds<-predict_byhand(new_data=validation_data,
                            prepped_recipe = prepped_recipe,
                            ranger_fitted_model  = final_ranger_fit)

class <- colnames(validation_preds)[max.col(validation_preds, ties.method = "first")]
class<-as_tibble(class) %>%
  rename(.pred_class=value) %>%
  mutate(.pred_class=str_remove(.pred_class,".pred_" ) # Removes all matches
  )

class<-class %>%
  mutate(.pred_class=factor(.pred_class)) %>%
  mutate(.pred_class=fct_relevel(.pred_class,class_levels)
  )
# Bind cols
validation_preds<-bind_cols(validation_preds,validation_data)

validation_preds<-validation_preds%>%
  mutate(weighting=hardhat::frequency_weights(lndlb)) 

# look at the fit metrics
# Weighted fit metrics on validation predictions: ROC AUC, log loss, and
# Brier score, all using lndlb as case weights so high-volume transactions
# contribute proportionally.

# compute training metrics with yardstick
validation_metrics <-  bind_rows(
  roc_auc(validation_preds, truth = market_desc,
          starts_with(".pred_"),
          case_weights = weighting),
  mn_log_loss(validation_preds, truth = market_desc,
              starts_with(".pred_"),
              case_weights = weighting),
  brier_class(validation_preds, truth = market_desc,
              starts_with(".pred_"),
              case_weights = weighting)
)
validation_metrics


# Apply the Final fit to the validation dataset. 
#The validation plots indicate characteristic issues with probability trees. All models are underconfident. Groups of observations with a 75% predicted probability of Jumbo have a true probability of Jumbo of almost 90%.  Groups of observations with a predicted probability of ~15% probabilty of Jumbo have a true probability closer to 10%.

# Calibration should fix this.
validation_data<-validation_preds

# Build a pre-calibration windowed calibration plot on the validation data.
# cal_plot_windowed() requires observation-level data (no case weights argument),
# so the transaction-level data is first uncounted: each row is replicated lndlb
# times, producing one pseudo-row per landed pound. Because the uncounted
# dataset is very large, a stratified 25% subsample is drawn for the plot and
# for fitting the calibration model below.
# NOTE: initial_split() treats 'prop' as the share going to the "training" slot.
# training() therefore extracts the 25% portion here. The naming is
# counterintuitive -- uv2 is the calibration-fitting sample, not a model-training sample.
# 25% sample because the uncounted data is just massive.

set.seed(9834549)

uv2<-validation_preds

uncounted_validation<-uv2 %>%
  mutate(lndlb2=lndlb)%>%
  uncount(lndlb2)


cal_gg<-uncounted_validation %>%
  cal_plot_windowed(
    truth          = market_desc,
    estimate       = c(.pred_Jumbo, .pred_Large, .pred_Medium, .pred_Small),
    step_size      = 0.10,
    include_points = FALSE
  )

cal_data <- cal_gg$data



# --- 2. Build publication-ready faceted calibration plot ---
# Dashed diagonal = perfect calibration. Ribbon = CI on the observed event rate
# within each window. Formatted to ICES JMS double-column spec.
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
  facet_wrap(~ market_desc, ncol = 2)+
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

# --- 3. Save at ICES JMS double-column specification ---
ggsave(
  here("results", "ranger", "final",
       glue("calplot_raw_Weighted_window{modeltype}{finalfit_vintage}.pdf")),
  plot   = p_cal,
  width  = 84,
  height = 88,     # suits 4 panels in one row; increase to 130 for 2x2 layout
  units  = "mm",
  device = cairo_pdf
)

################################################################################
# I tried to use cal_estimate_multinomial with smooth=TRUE to fit a multinomial
# model with splines.  
# mcgv::gam() will not actually accept weights (it silently swallows them)
#
################################################################################

# This throws an error, but wrapping a do.call forces the weights to get evaluated immediately.

# calibrate_weighted_multinom <- cal_estimate_multinomial(uv2, 
#                                          truth=market_desc, 
#                                          estimate=.pred_Jumbo:.pred_Small,
#                                          smooth=FALSE, 
#                                          weights=lndlb)

# Fit a weighted model. without smoothing splines


uv2<-uv2 %>%
  mutate(.cal_weight=as.integer(lndlb))


 calibrate_case_weighted_multinom <- do.call(
   cal_estimate_multinomial,
   list(
     .data = uv2,
     truth = quote(market_desc),
     estimate = quote(.pred_Jumbo:.pred_Small),
     smooth = FALSE,
     weights = uv2$.cal_weight
   )
 )
 
 
 write_rds(calibrate_case_weighted_multinom, file=here("results","ranger","final",glue(
   "calibrate_weighted_multinom_{modeltype}{finalfit_vintage}.Rds")))
 
 # Fit the unweighted one, 
  calibrate_case_UW_multinom <- do.call(
   cal_estimate_multinomial,
   list(
     .data = uv2,
     truth = quote(market_desc),
     estimate = quote(.pred_Jumbo:.pred_Small),
     smooth = FALSE
     )
 )
 
  
  
  
  
  #print them both. They are different. 
  calibrate_case_weighted_multinom$estimates
  calibrate_case_UW_multinom$estimates
 

# Apply the weighted calibration and pull the calibration gains.
# Calibration is applied to the full validation set (not just the 25% subsample
# used to fit it). Weighted Brier scores computed pre- and post-calibration;
# CalLoss and rCalLoss summarize the absolute and relative improvement.
# This particular computation is 'just for fun'. We really want to evaluate the
# performance of the calibration on the TEST set, not this set.	And we can't use the 75% 
# leftover of the subsample because it's not independent.	 
validation_data_Weighted_multicalib_applied <-
  validation_data %>%
  cal_apply(calibrate_case_weighted_multinom)

ESPR_Wraw<-validation_data %>%
  brier_class(market_desc,.pred_Jumbo:.pred_Small,
      case_weights = weighting) %>%
  pull(.estimate)
              

ESPR_W_multi<-validation_data_Weighted_multicalib_applied %>%
  brier_class(market_desc,.pred_Jumbo:.pred_Small,
      case_weights = weighting) %>%
  pull(.estimate)

message("Brier score, uncalibrated:  ", ESPR_Wraw)
message("Brier score, calibrated:  ", ESPR_W_multi)


CalLoss<-ESPR_Wraw-ESPR_W_multi
rCalLoss<-100*CalLoss/ESPR_Wraw

message("Relative, change (%):  ", round(rCalLoss, 2))

rCalLoss
rm(ESPR_Wraw, ESPR_W_multi, CalLoss, rCalLoss)

# Windowed calibration plot on the calibrated validation predictions, for
# visual confirmation that calibration corrected the underconfidence pattern.
# like the previous section, this is just a sanity check. It should be evaluated on the test set
# this is also not "uncounted", so it's not quite right
cal_weighted_multi<-cal_plot_windowed(validation_data_Weighted_multicalib_applied,
                  truth = market_desc, step_size = 0.05, include_points =FALSE)

cal_weighted_multi
rm(cal_weighted_multi)

uncounted_validation_Weighted_multicalib_applied <-
  uncounted_validation %>%
  cal_apply(calibrate_case_weighted_multinom)

cal_uncounted_multi<-cal_plot_windowed(uncounted_validation_Weighted_multicalib_applied,
                                      truth = market_desc, step_size = 0.05, include_points =FALSE)
cal_uncounted_multi

# Predict out-of-sample on the final test holdout.
# Same predict_byhand / modal-class extraction / bind-back pattern as validation.
class_levels <- c("Jumbo", "Large", "Medium", "Small")
test_preds<-predict_byhand(new_data=test_data,
                          prepped_recipe = prepped_recipe,
                            ranger_fitted_model  = final_ranger_fit)

test_class <- colnames(test_preds)[max.col(test_preds, ties.method = "first")]
test_class<-as_tibble(test_class) %>%
  mutate(.pred_class=str_remove(.pred_class,".pred_" ) # Removes all matches
  )

test_class<-test_class %>%
  mutate(.pred_class=factor(.pred_class)) %>%
  mutate(.pred_class=fct_relevel(.pred_class,class_levels)
  )



# Bind cols
test_data<-bind_cols(test_class,test_preds,test_data)

test_data<-test_data%>%
  mutate(weighting=hardhat::frequency_weights(lndlb)) 






############ How well calibrated is the model? 
# A: Better when calibrated - same pattern as training data.
# Calibration diagnostics on the test holdout: uncount by lndlb weight
# (same rationale as validation), then build windowed cal plots for both
# raw (uncalibrated) and calibrated predictions for side-by-side comparison.
# Plot the "raw" predictions
test_data_uncount<- test_data  %>%
  uncount(weights = weighting)


uncalibrated<-cal_plot_windowed(test_data_uncount, truth = market_desc, step_size = 0.05,include_points=FALSE)


# Apply the calibration model (fit on validation subsample) to the test holdout.

test_data_calibration_applied <-
  test_data %>%
  cal_apply(calibrate_case_weighted_multinom)


test_data_calibration_applied_uncount<- test_data_calibration_applied  %>%
  uncount(weights = weighting)


calibrated<-cal_plot_windowed(test_data_calibration_applied_uncount, truth = market_desc, step_size = 0.05,include_points=FALSE)

calibrated

# Pub Ready Calibration
# Extract data from the ggplot internals
cal_data <- calibrated$data



# --- 2. Build publication-ready faceted calibration plot ---
# Calibrated test predictions. Same theme/formatting as validation plot above.
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
# --- 3. Save at ICES JMS double-column specification ---
ggsave(
  here("results", "ranger", "final",
       glue("cal_Wmultinom_testing{modeltype}{finalfit_vintage}.pdf")),
  plot   = p_cal,
  width  = 84,
  height = 88,     # suits 4 panels in one row; increase to 130 for 2x2 layout
  units  = "mm",
  device = cairo_pdf
)





# Pub Ready Calibration
# Extract data from the ggplot internals
# Uncalibrated test predictions publication plot, built from uncalibrated$data.
# Paired with the calibrated plot above for direct visual comparison.
uncal_data <- uncalibrated$data



# --- 2. Build publication-ready faceted calibration plot ---
p_uncal <- ggplot(uncal_data,
                aes(x = predicted_midpoint, y = event_rate)) +
  # perfect calibration reference line
  geom_abline(slope = 1, intercept = 0,
              linetype = "dashed", colour = "grey50", linewidth = 0.4) +
  # confidence band
  geom_ribbon(aes(ymin = lower, ymax = upper),
              fill = "#1B6CA8", alpha = 0.15) +
  # calibration curve
  geom_line(colour = "#1B6CA8", linewidth = 0.8) +
  facet_wrap(~ market_desc, ncol = 2)+
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
p_uncal
# --- 3. Save at ICES JMS double-column specification ---
ggsave(
  here("results", "ranger", "final",
       glue("uncal_windowed_testing{modeltype}{finalfit_vintage}.pdf")),
  plot   = p_uncal,
  width  = 84,
  height = 88,     # suits 4 panels in one row; increase to 130 for 2x2 layout
  units  = "mm",
  device = cairo_pdf
)




# Brier score comparison on the test holdout: raw vs. calibrated predictions.
# CalLoss = absolute reduction in Brier score; rCalLoss = relative reduction (%).
ESPR_raw<-test_data %>%
  brier_class(market_desc,.pred_Jumbo:.pred_Small,
          case_weights = weighting) %>%
  pull(.estimate)



ESPR_cal<-test_data_calibration_applied %>%
  brier_class(market_desc,.pred_Jumbo:.pred_Small,
          case_weights = weighting) %>%
  pull(.estimate)

ESPR_raw
ESPR_cal

CalLoss<-ESPR_raw-ESPR_cal
rCalLoss<-100*CalLoss/ESPR_raw

#this shows how much the calibration improve the brier score.
CalLoss
rCalLoss

##################PREDICT ####################################
##################PREDICT ####################################
# Aggregate calibrated test predictions to stockarea × year × market_desc.
# For each market grade, predicted pounds = P(grade) × lndlb per transaction.
# tryCatch silently skips any grade that has no corresponding .pred_* column
# (e.g., Unclassified may be absent from the calibrated output).
# prob_names is defined in modeltype_patterns.R.
# Calibrated Predictions
### pull a few categories, compute a prob*lndlb variable, sum 

prob_names<-colnames(test_data_calibration_applied) 
prob_names<-grep("^\\.pred_", prob_names, value=TRUE)
prob_names<-grep("^\\.pred_class", prob_names, value=TRUE, invert=TRUE)

# keep just a few columns
test_data_calibration_applied<-test_data_calibration_applied %>%
  select(c( weighting, market_desc, lndlb, stockarea, year, any_of(prob_names), .pred_class))

# predicted pounds per transaction in the validation dataset.
# multiply the prediction by the landed pounds to get predicted pounds in each class. 
for (l in c("Jumbo", "Large", "Medium", "Small", "Unclassified")) {
  tryCatch({
    test_data_calibration_applied[[paste0("pred_", l)]] <- test_data_calibration_applied[[paste0(".pred_", l)]] * test_data_calibration_applied$lndlb
  }, error = function(e) {
    # R will just silently continue to the next iteration
  })
}
# Sum up the predictions by year, market category, and stockarea. 
test_predictions<-test_data_calibration_applied %>%
   group_by(stockarea, year,market_desc) %>%
  select(-.pred_class) %>%
  mutate(transactions=1) %>%
  summarise(across(c(starts_with(c("pred_",".pred_")), "lndlb", "transactions"), \(x) sum(x, na.rm = TRUE))) %>%
   ungroup()
test_predictions$modeltype<-modeltype

test_predictions<-test_predictions %>%
  mutate(market_desc=fct_relevel(market_desc,"Jumbo","Large","Medium","Small")) 

write_rds(test_predictions, file=here("results","ranger",glue("aggregate_WCtest_predictions_{modeltype}{finalfit_vintage}.Rds")))

#test_predictions<-test_predictions %>%
#  dplyr::filter(year %in% c(2021,2022,2023,2024))

## Probabalistic Predictions of the class of each transaction

# Topline accuracy summary for the test holdout.
# Two views of prediction error:
#   (1) Transaction counts: sum .pred_* probability columns to get expected
#       transaction counts by grade, compare to observed transaction counts.
#   (2) Landed weight (mt): sum pred_* (prob × lndlb) columns, convert lbs
#       to mt, compare to observed mt.
# % errors formatted via scales::percent().

aggregate_transactions<-test_predictions %>%
    summarise(across(c(starts_with(".pred_")), sum)) %>%
  pivot_longer(cols=starts_with(".pred_"), names_to="market_desc", names_prefix=".pred_",values_to="ObsPredicted")


aggregate_test_predictions<-test_predictions %>%
    summarise(across(c(starts_with("pred_")), sum)) %>%
  pivot_longer(cols=starts_with("pred_"), names_to="market_desc", names_prefix="pred_",values_to="predicted")


true<-test_predictions %>%
    group_by(market_desc) %>%
    summarise(lndlb=sum(lndlb),
              transactions=sum(transactions))

Testmkt_preds<-aggregate_transactions %>%
  left_join(true, by=join_by(market_desc==market_desc))

Testmkt_preds<-Testmkt_preds %>%
  left_join(aggregate_test_predictions, by=join_by(market_desc==market_desc))

Testmkt_preds<-Testmkt_preds %>%
  mutate(predicted=predicted/lbs_per_mt,
         lndlb=lndlb/lbs_per_mt) %>%
  rename(true_mt=lndlb,
         predicted_mt=predicted,
         predicted_transactions=ObsPredicted)%>%
  mutate(`mt error (%)`=percent((predicted_mt-true_mt)/true_mt, accuracy=0.01),
         `Transaction error (%)` = percent((predicted_transactions-transactions)/transactions, accuracy=0.01) )


transaction_predictions<-Testmkt_preds %>%
  select(market_desc,transactions, predicted_transactions, `Transaction error (%)`)


knitr::kable(transaction_predictions, caption='Calibrated Predictions on the 15% Validation Sample (transaction count).',format.args = list(big.mark = ","), digits=0, align=c("l",rep('r',times=4)))  

weighted_predictions<-Testmkt_preds %>%
  select(market_desc,true_mt, predicted_mt, `mt error (%)`)

knitr::kable(weighted_predictions, caption='Calibrated Predictions on the 15% Validation Sample (mt).',format.args = list(big.mark = ","), digits=0, align=c("l",rep('r',times=4)))  

# Here are the predictions (transactions and mt) for the hold-out sample, without the probability calibrations.


# Parallel aggregation block for uncalibrated test predictions.
# Identical pipeline to the calibrated block above; exists for direct
# comparison of calibrated vs. raw model output.
# write_rds is commented out -- nocal_predictions exists in memory only.

# Subset data, construct predicted pounds, and aggregate

### pull a few categories, compute a prob*lndlb variable, sum 


# keep just a few columns
test_data_nocalibration_applied<-test_data%>%
  select(c( weighting, market_desc, lndlb, stockarea, year, any_of(prob_names), .pred_class))

# predicted pounds per transaction in the validation dataset.
# multiply the prediction by the landed pounds to get predicted pounds in each class. 
for (l in c("Jumbo", "Large", "Medium", "Small", "Unclassified")) {
  tryCatch({
    test_data_nocalibration_applied[[paste0("pred_", l)]] <- test_data_nocalibration_applied[[paste0(".pred_", l)]] * test_data_nocalibration_applied$lndlb
  }, error = function(e) {
    # R will just silently continue to the next iteration
  })
}
# Sum up the predictions by year, market category, and stockarea. 
nocal_predictions<-test_data_nocalibration_applied%>%
   group_by(stockarea, year,market_desc) %>%
  select(-.pred_class) %>%
  mutate(transactions=1) %>%
  summarise(across(c(starts_with(c("pred_",".pred_")), "lndlb", "transactions"), \(x) sum(x, na.rm = TRUE))) %>%
   ungroup()
nocal_predictions$modeltype<-modeltype

nocal_predictions<-nocal_predictions%>%
  mutate(market_desc=fct_relevel(market_desc,"Jumbo","Large","Medium","Small")) 

write_rds(nocal_predictions, file=here("results","ranger",glue("aggregate_nocal_predictions_{modeltype}{finalfit_vintage}.Rds")))






run_this<-0
if (run_this==1){
  
  # weighted multinomial calibration
  # Fit a smooth multinomial calibration model on the 25% uncounted validation
  # subsample (uv2). cal_estimate_multinomial jointly recalibrates probabilities
  # across all market_desc classes. The fitted calibration object is saved for
  # application to the test holdout below.
  calibrate_weighted_multinom <- cal_estimate_multinomial(uncounted_validation,
                                                          truth=market_desc,
                                                          estimate=.pred_Jumbo:.pred_Small,
                                                          smooth=TRUE)
  
  write_rds(calibrate_weighted_multinom, file=here("results","ranger","final",glue(
    "calibrate_W_multinom_{modeltype}{finalfit_vintage}.Rds")))
  
  
  
  
  uv2<-uv2 %>%
    mutate(.cal_weight=as.integer(lndlb))
  
  
  # I tried to pass weights through in a variety of ways. None worked, because of the 
  # way cal_estimate_multinomial works.  Here's my proof: These two pieces of code p
  # produce the same output.
  calibrate_case_weighted_multinom <- do.call(
    cal_estimate_multinomial,
    list(
      .data = uv2,
      truth = quote(market_desc),
      estimate = quote(.pred_Jumbo:.pred_Small),
      smooth = TRUE,
      weights = uv2$.cal_weight
    )
  )
  
  cal_fitW <- calibrate_case_weighted_multinom$estimates[[1]]$estimate
  
  calibrate_case_weighted_multinomUW <- do.call(
    cal_estimate_multinomial,
    list(
      .data = uv2,
      truth = quote(market_desc),
      estimate = quote(.pred_Jumbo:.pred_Small),
      smooth = TRUE#,
      #  weights = uv2$weight
    )
  )
  

  calibrate_case_weighted_multinom$estimates[[1]]$estimate
  
  calibrate_case_weighted_multinomUW$estimates[[1]]$estimate
  
  
  ###########################################################
  # My last remaining option is to DIY it without probably
  ###########################################################
  levels(uv2$market_desc)   # check order first
  
  
  
  # load in some probably utils that are not exported.
  # clean_env from utils
  
  clean_env <- function(x) {
    attr(x, ".Environment") <- rlang::base_env()
    x
  }
  
  # ------------------------------- GAM Helpers ----------------------------------
  # From cal-estimate-utils.R
  f_from_str <- function(y, x, smooth = FALSE) {
    if (smooth) {
      x <- paste0("s(", x, ")")
    }
    trms <- paste0(x, collapse = "+")
    f <- paste(y, "~", trms)
    f <- stats::as.formula(f)
    attr(f, ".Environment") <- rlang::base_env()
    f
  }
  
  # mgcv multinomial models needs a list of formulas, one for each level, and
  # only the first one requires a LHS
  multinomial_f_from_str <- function(y, x) {
    num_class <- length(x)
    res <- vector(mode = "list", length = num_class - 1)
    for (i in seq_along(res)) {
      if (i == 1) {
        res[[i]] <- f_from_str(y, x[-length(x)], smooth = TRUE)
      } else {
        res[[i]] <- f_from_str(NULL, x[-length(x)], smooth = TRUE)
      }
    }
    res
  }
  
  
  # prepare the data
  
  calibration_data<-uv2 %>%
    select(c(market_desc, starts_with(".pred_")), lndlb) %>%
    mutate(market_desc_int = as.integer(market_desc) - 1L) %>%
    mutate(lndlb=as.integer(lndlb)) %>%
    mutate(.cal_weights    = lndlb)     # weight column inside the data frame
  
  
  
  
  
  #pull the weights column
  
  estimate<-c(".pred_Jumbo", ".pred_Large", ".pred_Medium", ".pred_Small")
  f <- multinomial_f_from_str("market_desc_int", estimate)
  
  modelW <- mgcv::gam(f, 
                      data = calibration_data, 
                      family = mgcv::multinom(3),
                      weights=.cal_weights)
  
  
  modelUW <- mgcv::gam(f, 
                       data = calibration_data, 
                       family = mgcv::multinom(3)
  )
  summary(modelUW)
  summary(modelW)
  
  
  f <- f_from_str("market_desc", estimate[-length(estimate)])
  
  model <- nnet::multinom(formula = f, data = calibration_data, weights=.cal_weights)
  modelUW <- nnet::multinom(formula = f, data = calibration_data )
  
  summary(modelUW)
  summary(model)
  
  
  model$terms <- clean_env(model$terms)
  
  
  
  
  
  test_data <- calibration_data %>%
    mutate(binary = as.integer(market_desc_int == 0))
  
  test_weighted <- mgcv::gam(
    binary ~ s(.pred_Jumbo),
    data    = test_data,
    family  = binomial(),
    weights = .cal_weights
  )
  
  test_unweighted <- mgcv::gam(
    binary ~ s(.pred_Jumbo),
    data    = test_data,
    family  = binomial()
  )
  
  summary(test_weighted)
  summary(test_unweighted)
  
  
}





