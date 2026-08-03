# =============================================================================
# weighted_calibration.R
#
# Purpose:
#   Post-hoc probability calibration for the BSB market-grade random forest.
#   Fits two multinomial calibration models (unsmoothed and spline-smoothed) on
#   the validation set, compares them by Brier score on the held-out test set,
#   keeps the smoothed model, produces publication-ready calibration plots, and
#   writes aggregated calibrated vs. uncalibrated predictions (transaction counts
#   and landed weight) to disk.
#
#   "Pounds" metrics are computed on data uncounted by lndlb;
#   "transaction" metrics on the raw rows.
#
#   Pipeline position: run AFTER train_randomforest_nocluster.R.
#
#
# Inputs (read from results/ranger; newest vintage auto-selected in Section 1):
#   data_split       -- rsample 3-way split (train / validation / test)
#   prepped_recipe   -- recipe object after prep()
#   final_ranger_fit -- final trained ranger model
#
# Outputs:
#   Calibration model objects (results/ranger/final/*.Rds):
#     calibrate_transactions_multinom_* -- multinomial, smoothed (smooth=TRUE),
#         transaction-level. The unsmoothed model is fit for comparison, then
#         rm()'d -- it is NOT saved.
#   Prediction datasets (results/ranger):
#     validation_preds*.dta
#     aggregate_uncounted_calibrated_test_predictions_*  (transactions + pounds)
#     aggregate_nocal_predictions_*                      (uncalibrated counterpart)
#   Plots (results/ranger/final/*.pdf):
#     calplot_raw_transactions_*         -- raw (uncalibrated) validation, windowed
#     calplot_multi_Valid*               -- calibrated (smoothed) validation, pub-ready
#     calplot_multi_test* / calplot_uncal_test* -- calibrated / uncalibrated test, windowed
#     test_data_calibrated_multinomial_* -- pub-ready calibrated test
#     test_data_uncalibrated*            -- pub-ready uncalibrated test
#
# Contents:
#   0  Setup: config, libraries, conflict resolution, paths, constants
#   1  Resolve file vintages and construct filenames
#   2  Load data, re-split validation/test 50/50, rebuild weights, load recipe & model
#   3  Validation-set predictions and weighted fit metrics
#   4  Pre-calibration diagnostic plot (raw validation)
#   5  Fit calibration models (unsmoothed + smoothed multinomial) and validation sanity check
#   6  Validation-set calibration plots
#   7  Test-set predictions, apply calibrations, Brier comparison, save chosen model
#   8  Test-set calibrated metrics (ROC AUC / log loss / Brier)
#   9  Test-set calibration plots
#   10 Test-set uncalibrated publication plot
#   11 Aggregate CALIBRATED test predictions; accuracy tables
#   12 Aggregate UNCALIBRATED test predictions; accuracy tables (parallel to Section 11)
#   13 Class-distribution and Small-class diagnostics (runs after completion message)
# =============================================================================

# =============================================================================
# SECTION 0 — Setup: config, libraries, conflict resolution, paths, constants
# Search/model config, package loads, {conflicted} preferences, here() anchor,
# helper sourcing (modeltype_patterns.R, predict_byhand.R), and unit constants.
# =============================================================================
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
library("haven")
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


# =============================================================================
# SECTION 1 — Resolve file vintages and construct filenames
# Scan results/data dirs for the most recent versioned file per object type:
# list matching filenames, strip the known prefix and ".Rds" suffix, take
# max() of the remaining date/version strings.
# finalfit_vintage and VI_vintage are set equal to tuning_vintage by
# construction; upstream tuning/training guarantees they stay in sync.
# =============================================================================
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

# =============================================================================
# SECTION 2 — Load data, re-split validation/test 50/50, rebuild weights, load recipe & model
# Read the rsample split (created by data_prep_ml.Rmd) and pull train/validation/
# test. The original validation and test sets are then recombined and re-split
# 50/50 (initial_split, seed 32560049) to give ~10%/10% validation/test, leaving
# more data for calibration. Rebuild lndlb frequency weights on the new
# validation and test sets, then load the prepped recipe and final ranger fit.
# =============================================================================
# # this was created with data_prep_ml.Rmd
data_split<-readr::read_rds(file=here("results","ranger",glue("{data_pattern}{data_vintage_string}.Rds")))
# Onlyneed the test and validation 
train_data <- training(data_split)
validation_data <- validation(data_split)
test_data <- testing(data_split)

# First split was 80, 5, 15.  reasonable when I was going to unweight at all stages
# I think this isn't leaving enough data for the calibration 
# I'm going to re-stick the validation and test data together. Then I'm going to split it in half, so I get 
# 10% and 10%.

rebind<-rbind(test_data, validation_data)
# seed
set.seed(32560049)
ds2<-initial_split(rebind, prop=0.5 )

validation_data<-training(ds2)
test_data<-testing(ds2)


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

# =============================================================================
# SECTION 3 — Validation-set predictions and weighted fit metrics
# Class-probability predictions on the validation set via predict_byhand()
# (applies prepped_recipe, then ranger). Modal class = column with the highest
# probability per row, bound back to the raw probabilities and original data.
# Also writes validation_preds*.dta and computes lndlb-weighted ROC AUC, log
# loss, and Brier score (metrics run on lndlb-uncounted data).
# =============================================================================

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


validation_subs<-validation_preds %>%
  select(c(starts_with(".pred"),market_desc, lndlb)) %>%
  rename(pred_Jumbo=.pred_Jumbo,
         pred_Large=.pred_Large,
         pred_Medium=.pred_Medium,
         pred_Small=.pred_Small)

write_dta(validation_subs, path=here("results","ranger",glue("validation_preds{finalfit_vintage}.dta")))

uncounted_validation<-validation_preds %>%
  mutate(lndlb2=lndlb)%>%
  uncount(lndlb2)


# look at the fit metrics
# Weighted fit metrics on validation predictions: ROC AUC, log loss, and
# Brier score, all using lndlb as case weights so high-volume transactions
# contribute proportionally.

# compute fit  metrics on the validation set with Yardstick with yardstick
validation_metrics <-  bind_rows(
  roc_auc(uncounted_validation, truth = market_desc,
          starts_with(".pred_")),
  mn_log_loss(uncounted_validation, truth = market_desc,
              starts_with(".pred_")),
  brier_class(uncounted_validation, truth = market_desc,
              starts_with(".pred_"))
)
validation_metrics


#The validation plots indicate characteristic issues with probability trees. All models are underconfident. Groups of observations with a 75% predicted probability of Jumbo have a true probability of Jumbo of almost 90%.  Groups of observations with a predicted probability of ~15% probabilty of Jumbo have a true probability closer to 10%.
# Calibration should fix this.
validation_data<-validation_preds

# =============================================================================
# SECTION 4 — Pre-calibration diagnostic plot (raw validation)
# Windowed calibration plot on RAW (transaction-level) validation predictions,
# used to decide whether calibration is needed, plus a publication-ready faceted
# version saved as calplot_raw_transactions_*. The ggplot/ggsave block here
# recurs, near-verbatim, in Sections 6, 9, and 10.
# =============================================================================

set.seed(9834549)


cal_gg<-validation_preds %>%
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
       glue("calplot_raw_transactions_{modeltype}{finalfit_vintage}.pdf")),
  plot   = p_cal,
  width  = 84,
  height = 88,     # suits 4 panels in one row; increase to 130 for 2x2 layout
  units  = "mm",
  device = cairo_pdf
)

# =============================================================================
# SECTION 5 — Fit calibration models (unsmoothed + smoothed multinomial)
# Fits two multinomial calibration models on the validation predictions, each
# via do.call():
#   calibrate_UW_multinom  -- smooth = FALSE (unsmoothed)
#   calibrate_UW_multinom2 -- smooth = TRUE  (spline-smoothed)
# Both are applied back to the validation set and their Brier scores compared as
# a sanity check (the fair comparison is on the test set, Section 7). Neither
# model is written to disk here; the chosen (smoothed) model is saved in Section 7.
# =============================================================================
# I tried to use cal_estimate_multinomial with smooth=TRUE to fit a multinomial
# model with splines.  
# mcgv::gam() will not actually accept weights (it silently swallows them)
# The smooth=TRUE option seems to fit better for transactions.
#################################################################################


# Fit the unweighted one, 
calibrate_UW_multinom <- do.call(
  cal_estimate_multinomial,
  list(
    .data = validation_preds,
    truth = quote(market_desc),
    estimate = quote(.pred_Jumbo:.pred_Small),
    smooth = FALSE
  )
)

# Fit the unweighted one, 
calibrate_UW_multinom2 <- do.call(
  cal_estimate_multinomial,
  list(
    .data = validation_preds,
    truth = quote(market_desc),
    estimate = quote(.pred_Jumbo:.pred_Small),
    smooth = TRUE
  )
)

# Apply calibration to validation data
CalM1 <-
  validation_data %>%
  cal_apply(calibrate_UW_multinom)

validation_transactions_multicalib_applied <-
  validation_data %>%
  cal_apply(calibrate_UW_multinom2)


# calculate brier class
CalM1 %>%
  brier_class(market_desc,.pred_Jumbo:.pred_Small) %>%
  pull(.estimate)


validation_transactions_multicalib_applied %>%
  brier_class(market_desc,.pred_Jumbo:.pred_Small) %>%
  pull(.estimate)

validation_data %>%
  brier_class(market_desc,.pred_Jumbo:.pred_Small) %>%
  pull(.estimate)


message("Brier Classification computed for the two calibration models on the validation data")
message("This is a sanity check, but not the fair comparison (next step)" )




# =============================================================================
# SECTION 6 — Validation-set calibration plots
# Windowed calibration plot on the CALIBRATED (smoothed multinomial) validation
# predictions, as a visual sanity check that underconfidence was corrected, plus
# a pub-ready version saved as calplot_multi_Valid*. Same caveat as Section 5:
# this is validation, not the fair test-set evaluation, and is not uncounted.
# Reuses the Section 4 ggplot/ggsave block.
# =============================================================================

# Plain figure for transaction
# nice figure for pounds

# Windowed calibration plot on the calibrated validation predictions, for
# visual confirmation that calibration corrected the underconfidence pattern.
# like the previous section, this is just a sanity check. It should be evaluated on the test set
# this is also not "uncounted", so it's not quite right
cal_transactions_multi<-cal_plot_windowed(validation_transactions_multicalib_applied,
                                          truth = market_desc, step_size = 0.05, include_points =FALSE)


cal_data <- cal_transactions_multi$data



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
       glue("calplot_multi_Valid{modeltype}{finalfit_vintage}.pdf")),
  plot   = p_cal,
  width  = 84,
  height = 88,     # suits 4 panels in one row; increase to 130 for 2x2 layout
  units  = "mm",
  device = cairo_pdf
)

message("Finished creating weighted calibration plot")


message("Final predictions on test set")

# =============================================================================
# SECTION 7 — Test-set predictions, apply calibrations, Brier comparison
# Out-of-sample predictions on the held-out test set (same predict_byhand /
# modal-class / bind-back pattern as Section 3). Applies both calibration models
# to the test set and compares Brier scores (raw vs. unsmoothed vs. smoothed;
# CalLoss / rCalLoss) -- the fair evaluation. The unsmoothed model and its
# applied object are dropped; the smoothed model is written to disk as
# calibrate_transactions_multinom_*.
# =============================================================================



# Calibration is applied to the full test set.
# Brier scores computed pre- and post-calibration;
# CalLoss and rCalLoss summarize the absolute and relative improvement.


#####################################################

# predict  on the test dataset
class_levels <- c("Jumbo", "Large", "Medium", "Small")
test_preds<-predict_byhand(new_data=test_data,
                           prepped_recipe = prepped_recipe,
                           ranger_fitted_model  = final_ranger_fit)

test_class <- colnames(test_preds)[max.col(test_preds, ties.method = "first")]

test_class<-as_tibble(test_class) %>%
  rename(.pred_class=value) %>%
  mutate(.pred_class=str_remove(.pred_class,".pred_" ) # Removes all matches
  )

test_class<-test_class %>%
  mutate(.pred_class=factor(.pred_class)) %>%
  mutate(.pred_class=fct_relevel(.pred_class,class_levels)
  )



# Bind cols
test_data<-bind_cols(test_class,test_preds,test_data)


# Apply Calibrations 1 and 2 to the test data with predictions
CalTM1 <-
  test_data %>%
  cal_apply(calibrate_UW_multinom)

ESPR_TM1 <- CalTM1 %>%
  brier_class(market_desc,.pred_Jumbo:.pred_Small) %>%
  pull(.estimate)

test_data_calibration_applied <-
  test_data %>%
  cal_apply(calibrate_UW_multinom2)

ESPR_TM2<-test_data_calibration_applied %>%
  brier_class(market_desc,.pred_Jumbo:.pred_Small) %>%
  pull(.estimate)

ESPR_raw<-test_data %>%
  brier_class(market_desc,.pred_Jumbo:.pred_Small) %>%
  pull(.estimate)


message("Brier Classification for the uncalibrated):", ESPR_raw)

message("Brier Classification for the unsmooth (multinomial):", ESPR_TM1)

message("Brier Classification for the smooth (multinomial):", ESPR_TM2)



CalLoss<-ESPR_raw-ESPR_TM2
rCalLoss<-100*CalLoss/ESPR_raw

message("Relative, change (%):  ", round(rCalLoss, 2))


# The Smoothed multinomial is best, We'll quickly verify that's the case
# And then drop the unsmooth one


cal_plot_windowed(test_data_calibration_applied,truth = market_desc, 
                  step_size = 0.05, include_points =FALSE)

cal_plot_windowed(CalTM1,truth = market_desc, 
                  step_size = 0.05, include_points =FALSE)

cal_plot_windowed(test_data,truth = market_desc, 
                  step_size = 0.05, include_points =FALSE)


message("Eyeballed the basic plots. The smooth version definitely looks better that unsmooth ")

rm(calibrate_UW_multinom)
rm(CalTM1)


write_rds(calibrate_UW_multinom2, file=here("results","ranger","final",glue(
  "calibrate_transactions_multinom_{modeltype}{finalfit_vintage}.Rds")))


# =============================================================================
# SECTION 8 — Test-set calibrated metrics
# Computes the full yardstick metric trio (ROC AUC, log loss, Brier) on the
# smoothed-multinomial-calibrated test predictions (test_data_calibration_applied).
# =============================================================================


############ How well calibrated is the model? 
# A: Better when calibrated - same pattern as training data.
# raw (uncalibrated) and calibrated predictions for side-by-side comparison.




# compute calibrated test  metrics with yardstick
test_metricsCAL <-  bind_rows(
  roc_auc(test_data_calibration_applied%>%select(-.pred_class), truth = market_desc,
          starts_with(".pred_")),
  mn_log_loss(test_data_calibration_applied%>%select(-.pred_class), truth = market_desc,
              starts_with(".pred_")),
  brier_class(test_data_calibration_applied%>%select(-.pred_class), truth = market_desc,
              starts_with(".pred_"))
)
test_metricsCAL

# =============================================================================
# SECTION 9 — Test-set calibration plots
# Windowed calibration plots for the test set: calibrated (calplot_multi_test*)
# and uncalibrated (calplot_uncal_test*), followed by a pub-ready calibrated plot
# saved as test_data_calibrated_multinomial_*. Reuses the Section 4 ggplot block.
# =============================================================================
calibrated<-cal_plot_windowed(test_data_calibration_applied, 
                              truth = market_desc, 
                              step_size = 0.1 , 
                              include_points=FALSE)
calibrated
ggsave(
  here("results", "ranger", "final",
       glue("calplot_multi_test{modeltype}{finalfit_vintage}.pdf")),
  plot   = calibrated,
  width  = 84,
  height = 88,     # suits 4 panels in one row; increase to 130 for 2x2 layout
  units  = "mm",
  device = cairo_pdf
)


uncalibrated<-cal_plot_windowed(test_data, 
                                truth = market_desc, 
                                step_size = 0.1 , 
                                include_points=FALSE)
uncalibrated
ggsave(
  here("results", "ranger", "final",
       glue("calplot_uncal_test{modeltype}{finalfit_vintage}.pdf")),
  plot   = uncalibrated,
  width  = 84,
  height = 88,     # suits 4 panels in one row; increase to 130 for 2x2 layout
  units  = "mm",
  device = cairo_pdf
)


# Pub Ready Calibration
# Extract data from the ggplot internals
cal_data <- calibrated$data


message("Saving to Publication ready format")

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
       glue("test_data_calibrated_multinomial_{modeltype}{finalfit_vintage}.pdf")),
  plot   = p_cal,
  width  = 84,
  height = 88,     # suits 4 panels in one row; increase to 130 for 2x2 layout
  units  = "mm",
  device = cairo_pdf
)




# =============================================================================
# SECTION 10 — Test-set uncalibrated publication plot
# Pub-ready faceted plot of the UNCALIBRATED test predictions, built from the
# uncalibrated windowed plot's $data (Section 9). Pairs with the calibrated plot
# in Section 9 for direct visual comparison; saved as test_data_uncalibrated*.
# Reuses the Section 4 ggplot block.
# =============================================================================
message("Plotting results of test set  without calibration")


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
       glue("test_data_uncalibrated{modeltype}{finalfit_vintage}.pdf")),
  plot   = p_uncal,
  width  = 84,
  height = 88,     # suits 4 panels in one row; increase to 130 for 2x2 layout
  units  = "mm",
  device = cairo_pdf
)



# =============================================================================
# SECTION 11 — Aggregate CALIBRATED test predictions; accuracy tables
# Reuses the calibrated test predictions from Section 7 (already cal_apply'd
# there) and aggregates to stockarea x year x market_desc. Predicted pounds per
# grade = P(grade) * lndlb (tryCatch skips absent grades). Writes
# aggregate_uncounted_calibrated_test_predictions_*, then builds topline
# transaction-count and landed-weight (mt) accuracy tables via knitr::kable().
# Section 12 is the uncalibrated mirror of this block.
# =============================================================================
message("Beginning calibrated predictions")






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

write_rds(test_predictions, file=here("results","ranger",glue("aggregate_uncounted_calibrated_test_predictions_{modeltype}{finalfit_vintage}.Rds")))

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


knitr::kable(transaction_predictions, caption='Calibrated Predictions on the 10% Test Sample (transaction count).',format.args = list(big.mark = ","), digits=0, align=c("l",rep('r',times=4)))  

weighted_predictions<-Testmkt_preds %>%
  select(market_desc,true_mt, predicted_mt, `mt error (%)`)

knitr::kable(weighted_predictions, caption='Calibrated Predictions on the 10% Test Sample (mt).',format.args = list(big.mark = ","), digits=0, align=c("l",rep('r',times=4)))  
message("End of calibrated predictions")


# =============================================================================
# SECTION 12 — Aggregate UNCALIBRATED test predictions; accuracy tables
# Parallel to Section 11 but on RAW (uncalibrated) test predictions, for direct
# comparison. Identical aggregation/table pipeline. Writes
# aggregate_nocal_predictions_* to disk.
# =============================================================================
message("Beginning uncalibrated predictions")



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







aggregate_transactions<-nocal_predictions %>%
  summarise(across(c(starts_with(".pred_")), sum)) %>%
  pivot_longer(cols=starts_with(".pred_"), names_to="market_desc", names_prefix=".pred_",values_to="ObsPredicted")


aggregate_test_predictions<-nocal_predictions %>%
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

knitr::kable(transaction_predictions, caption='Uncalibrated Predictions on the 10% Test Sample (transaction count).',format.args = list(big.mark = ","), digits=0, align=c("l",rep('r',times=4)))  

weighted_predictions<-Testmkt_preds %>%
  select(market_desc,true_mt, predicted_mt, `mt error (%)`)

knitr::kable(weighted_predictions, caption='Uncalibrated Predictions on the 10% Test Sample (mt).',format.args = list(big.mark = ","), digits=0, align=c("l",rep('r',times=4)))  


message("End of uncalibrated predictions")

















message("weighted_calibration.R completed successfully.")


# =============================================================================
# SECTION 13 — Class-distribution and Small-class diagnostics
# Post-hoc checks that run AFTER the completion message above. Reports the
# landed-weight / observation share of each grade across train/validation/test,
# and examines how sparse the Small-class probability mass is (why its
# calibration plot is unreliable).
# =============================================================================
# There isn't too much small in the dataset. (<5%). 

message("training set check:")

train_data %>%group_by(market_desc) %>%
  summarise(lnd=sum(lndlb),
            obs=n()) %>%
  ungroup() %>%
  mutate(total=sum(lnd),
         totalobs=sum(obs)) %>%
  mutate(frac=lnd/total,
         fracobs=obs/totalobs) %>%
  select(-c(total,totalobs))
message("validation set check:")
validation_data %>%group_by(market_desc) %>%
  summarise(lnd=sum(lndlb),
            obs=n()) %>%
  ungroup() %>%
  mutate(total=sum(lnd),
         totalobs=sum(obs)) %>%
  mutate(frac=lnd/total,
         fracobs=obs/totalobs) %>%
  select(-c(total,totalobs))

message("test set check:")
test_data %>%group_by(market_desc) %>%
  summarise(lnd=sum(lndlb),
            obs=n()) %>%
  ungroup() %>%
  mutate(total=sum(lnd),
         totalobs=sum(obs)) %>%
  mutate(frac=lnd/total,
         fracobs=obs/totalobs) %>%
  select(-c(total,totalobs))


# Small investigate
message("there isn't much data for smalls where there's even the tiniest bit of probability.")
test_data %>%
  summarise(
    p10  = quantile(.pred_Small, 0.10),
    p25  = quantile(.pred_Small, 0.25),
    p50  = quantile(.pred_Small, 0.50),
    p75  = quantile(.pred_Small, 0.75),
    p90  = quantile(.pred_Small, 0.90),
    p95  = quantile(.pred_Small, 0.95),
    p99  = quantile(.pred_Small, 0.99),
    pct_below_01 = mean(.pred_Small < 0.10),
    pct_below_05 = mean(.pred_Small < 0.05)
  )


# test_data_calibration_applied %>%
#   summarise(
#     p10  = quantile(.pred_Small, 0.10),
#     p25  = quantile(.pred_Small, 0.25),
#     p50  = quantile(.pred_Small, 0.50),
#     p75  = quantile(.pred_Small, 0.75),
#     p90  = quantile(.pred_Small, 0.90),
#     p95  = quantile(.pred_Small, 0.95),
#     p99  = quantile(.pred_Small, 0.99),
#     pct_below_01 = mean(.pred_Small < 0.10),
#     pct_below_05 = mean(.pred_Small < 0.05)
#   )


message(" In contrast, there's a nice spread for predictions of Larges")
test_data %>%
  summarise(
    p10  = quantile(.pred_Large, 0.10),
    p25  = quantile(.pred_Large, 0.25),
    p50  = quantile(.pred_Large, 0.50),
    p75  = quantile(.pred_Large, 0.75),
    p90  = quantile(.pred_Large, 0.90),
    p95  = quantile(.pred_Large, 0.95),
    p99  = quantile(.pred_Large, 0.99),
    pct_below_01 = mean(.pred_Large < 0.10),
    pct_below_05 = mean(.pred_Large < 0.05)
  )

# Takeaway 1. The calibration plot is misleading for the Small class, where there
# are very few datapoints

test_data_pounds<-test_data %>%
  uncount(weighting)

test_data_pounds%>%
  summarise(
    p10  = quantile(.pred_Small, 0.10),
    p25  = quantile(.pred_Small, 0.25),
    p50  = quantile(.pred_Small, 0.50),
    p75  = quantile(.pred_Small, 0.75),
    p90  = quantile(.pred_Small, 0.90),
    p95  = quantile(.pred_Small, 0.95),
    p99  = quantile(.pred_Small, 0.99),
    pct_below_01 = mean(.pred_Small < 0.10),
    pct_below_05 = mean(.pred_Small < 0.05)
  ) 

# Takeaway 2 -- it's even worse for the uncounted data, where P90 for Small is 0.017 (just under 2%)

