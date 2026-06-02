###############################################################################
# Purpose: Estimate an h2o Random Forest classification model on 4 classes
#          WITHOUT clustering on DLRID for validation. Unclassified excluded.
#
# This is the h2o/agua analogue of estimate_randomforest_nocluster.R.
# Uses the same recipe (BSB.Classification.Recipe.R) without modification.
# Mirrors the structure and outputs of the ranger version as closely as possible.
#
# Inputs:
#   - BSB_estimation_dataset (from data_prep_ml.Rmd)
#   - BSB.Classification.Recipe.R  (sourced)
#   - BSB.Workflow.h2o.Setup.R     (sourced; initializes h2o, defines workflow/grid)
#
# Outputs (all in results/h2o/ — distinct from ranger outputs in results/ranger/):
#   - h2o_nocluster_data_split<date>.Rds
#   - BSB_h2o_nocluster_tune<date>.Rds
#   - BSB_h2o_nocluster_results<date>.Rds
#   - BSB_h2o_nocluster_split_metrics<date>.Rds
###############################################################################
options(warn = 1)        # print warnings immediately as they occur
# rather than collecting them until the end


search_type <- "Prototype"
# search_type in c("Initial", "Prototype", "Advanced")
bayes_tune=FALSE
# Only used when search_type == "Prototype" — fraction of data to keep for testing
testing_fraction <- 0.2

start_time <- Sys.time()
modeltype   <- "h20nocluster"



# ============================================================
# Section 1: Setup
# ============================================================

# Ensure that you've gotten the latest stable h2o (https://docs.h2o.ai/h2o/latest-stable/h2o-docs/downloading.html)
# The version on CRAN is old

library("here")
library("tidyverse")
library("scales")
library("glue")
library("tidymodels")
library("agua")       # h2o engine for tidymodels/parsnip  
library("h2o")        # h2o backend (also loaded by agua, explicit for clarity)  
library("knitr")
library("kableExtra")
library("viridis")
library("conflicted")
library("bundle")


# Resolve package conflicts (mirrors ranger version)
conflicts_prefer(dplyr::filter())
conflicts_prefer(dplyr::lag())
conflicts_prefer(purrr::discard())
conflicts_prefer(dplyr::group_rows())
conflicts_prefer(yardstick::spec())
conflicts_prefer(recipes::fixed())
conflicts_prefer(recipes::step())
conflicts_prefer(viridis::viridis_pal())
conflicts_prefer(base::`&&`)
conflicts_prefer(base::round)

here::i_am("R_code/analysis/fit_random_forest/estimate_h2orandomforest_nocluster.R")
#log_file <- here("results", "h2o", "debug_run.log")
#log_con <- file(log_file, open = "wt")
#sink(log_con, type = "output")
#sink(log_con, type = "message")



# NOTE on parallelism:
# The ranger version uses plan("multisession") from the future package to run
# cross-validation folds in parallel across R workers. H2o manages its own
# internal parallelism via the nthreads argument set in h2o.init() (see
# BSB.Workflow.h2o.Setup.R). Do NOT set up a future parallel backend here —
# doing so can conflict with h2o's thread pool and inflate memory usage.
# No future or doParallel setup is needed or wanted for the h2o version.

lbs_per_mt <- 2204.62

# ============================================================
# File and path setup
# ============================================================

my_images         <- here("images")
descriptive_images <- here("images", "descriptive")
exploratory_images <- here("images", "exploratory")

vintage_string <- list.files(
  here("data_folder", "main", "commercial"),
  pattern = glob2rx("BSB_estimation_dataset*Rds")
)
vintage_string <- gsub("BSB_estimation_dataset", "", vintage_string)
vintage_string <- gsub(".Rds", "", vintage_string)
vintage_string <- max(vintage_string)

estimation_vintage <- as.character(Sys.Date())

# Output file names — all prefixed with "h2o_" or contain "h2o" to distinguish
# from ranger outputs. Do not overwrite anything in results/ranger/.
data_save_name      <- glue("h2o_nocluster_data_split{estimation_vintage}.Rds")
tune_file_name      <- glue("BSB_h2o_nocluster_tune{estimation_vintage}.Rds")
final_fit_file_name <- glue("BSB_h2o_nocluster_results{estimation_vintage}.Rds")
split_metrics_name  <- glue("BSB_h2o_nocluster_split_metrics{estimation_vintage}.Rds")

if (search_type == "Prototype") {
  data_save_name      <- glue("h2o_nocluster_data_split_TEST{estimation_vintage}.Rds")
  tune_file_name      <- glue("BSB_h2o_nocluster_tune_TEST{estimation_vintage}.Rds")
  final_fit_file_name <- glue("BSB_h2o_nocluster_results_TEST{estimation_vintage}.Rds")
  split_metrics_name  <- glue("BSB_h2o_nocluster_split_metrics_TEST{estimation_vintage}.Rds")
}

# Create output directory if it does not yet exist
dir.create(here("results", "h2o"), showWarnings = FALSE, recursive = TRUE)

# ============================================================
# Data loading and splitting
# ============================================================

estimation_dataset <- readr::read_rds(
  file = here("data_folder", "main", "commercial",
              glue("BSB_estimation_dataset{vintage_string}.Rds"))
)

set.seed(4587315)

#  drop unused factor levels — mirrors ranger version
estimation_dataset <- estimation_dataset %>%
  mutate(
   weighting   = as.integer(weighting),
    market_desc = fct_drop(market_desc)
  )

estimation_dataset <- estimation_dataset %>%
  mutate(across(where(~ is.factor(.) && is.ordered(.)), ~ factor(., ordered = FALSE)))

# When testing, take a subset of the data to verify code is working
if (search_type == "Prototype") {
  estimation_dataset$rand <- runif(nrow(estimation_dataset))
  estimation_dataset <- estimation_dataset %>%
    dplyr::filter(rand <= testing_fraction)
}

# Keep the same columns as the ranger version
keep_cols <- c(
  "market_desc", "myl_id", "dlrid", "weighting",
  "mygear", "price", "priceR_CPI", "stockarea", "state",
  "year", "month", "semester", "lndlb", "grade_desc",
  "trip_level_BSB", "catch_share", "shore", "nofederal",
  "StateOtherQJumbo",     "StateOtherQLarge",     "StateOtherQMedium",     "StateOtherQSmall",
  "StockareaOtherQJumbo", "StockareaOtherQLarge", "StockareaOtherQMedium", "StockareaOtherQSmall",
  "MA7_StockareaQJumbo",  "MA7_StockareaQLarge",  "MA7_StockareaQMedium",  "MA7_StockareaQSmall",
  "MA7_StateQJumbo",      "MA7_StateQLarge",      "MA7_StateQMedium",      "MA7_StateQSmall",
  "MA7_gearQJumbo",       "MA7_gearQLarge",       "MA7_gearQMedium",       "MA7_gearQSmall",
  "MA7_stockarea_trips",  "MA7_state_trips", "first_dlr_year",
  "LagSharePoundsJumbo",  "LagSharePoundsLarge",  "LagSharePoundsMedium",  "LagSharePoundsSmall",
  "Price_Diff_J",         "Price_Diff_L",         "Price_Diff_M"
)

estimation_dataset <- estimation_dataset %>%
  select(all_of(keep_cols))

set.seed(2824)
# 70% train, 15% validation/calibrate, 15% test — identical split to ranger version
data_split      <- initial_validation_split(data = estimation_dataset, prop = c(0.7, 0.15))
train_data      <- training(data_split) %>%
  mutate(weighting = frequency_weights(weighting))
test_data       <- testing(data_split) %>%
  mutate(weighting = frequency_weights(weighting))
validation_data <- validation(data_split)  %>%
  mutate(weighting = frequency_weights(weighting)) # the "calibrate" split

readr::write_rds(data_split, file = here("results", "h2o", data_save_name))

nrow(train_data)
nrow(test_data)
nrow(validation_data)

# Source the recipe first (requires train_data to exist), then the h2o workflow
# setup (which calls h2o.init() and defines BSB.H2O.Workflow, h2o_grid,
# class_and_probs_metrics). Do NOT source BSB.Workflow.Setup.R here.
#source(here("R_code", "analysis", "fit_random_forest", "BSB.h2o.Classification.Recipe.R"))
#source(here("R_code", "analysis", "fit_random_forest", "BSB.Workflow.h2o.Setup.R"))
# ============================================================
#Troubleshoot with this bit of code.
# mini_df <- train_data #|>
# #  dplyr::slice_sample(n = 10000)
source(here("R_code", "analysis", "fit_random_forest", "BSB.h2o.mini.Recipe2.R"))
# 
# mini_spec <- rand_forest(trees = 500, mtry = 10, min_n = 1000) |>
#   set_engine("h2o", seed = 123L) |>
#   set_mode("classification")
# 
# mini_wf <- workflow() |>
#   add_recipe(BSB.Classification.Recipe) |>
#   add_model(mini_spec)  |> 
#   add_case_weights(weighting)

# fit(mini_wf, data = train_data)

# reset
#h2o.shutdown(prompt = FALSE)
#source(here("R_code", "analysis", "fit_random_forest", "BSB.h2o.Classification.Recipe.R"))
source(here("R_code", "analysis", "fit_random_forest", "BSB.Workflow.h2o.Setup.R"))
# ============================================================









# ============================================================
# Section 2: Tuning Grid
# ============================================================

# h2o_grid was defined in BSB.Workflow.h2o.Setup.R based on search_type.
# Edit that file to adjust grid ranges and sizes.

set.seed(123)
# 10-fold cross-validation stratified on outcome — mirrors ranger version
myfolds <- rsample::vfold_cv(train_data, strata = market_desc, v = 10)






# ============================================================
# Section 3: Tuning
# ============================================================

# --- Phase 3a: Initial grid search ---

# NOTE: h2o submits each model fit as a job to the h2o cluster internally.
# Parallelism is controlled by nthreads set in h2o.init(), not by R.
# The parallel_over = "everything" control argument is kept for API consistency
# with the ranger version, but h2o will handle actual parallelism itself.

rf_control_grid <- control_grid(
  save_pred = TRUE, 
  verbose=TRUE,
  allow_par=FALSE,
  extract = function(x) {
    
    # Print current h2o cluster contents to console
    current_objects <- h2o::h2o.ls()
    message("--- After fold completion ---")
    message("H2o objects in memory: ", nrow(current_objects))
    message(paste(current_objects$key, collapse=", ")) 
    
    # Also print JVM memory status
    message("H2o cluster memory: ", 
            round(h2o::h2o.clusterStatus()$mem_value_size$mem_value_size / 1024^2, 1), 
            " MB")

    # Match all three object types associated with DRF model fits
    removable_ids <- current_objects$key[
      grepl("^DRF_model_R_[0-9]+_[0-9]+$", current_objects$key) |      # model
        grepl("^modelmetrics_DRF_model_R_",   current_objects$key) |      # metrics
        grepl("^transformation_[[:alnum:]]+_DRF_", current_objects$key)
    ]
    
    message("Removing ", length(removable_ids), " objects")
    
    for (id in removable_ids) {
      tryCatch(h2o::h2o.rm(id), error = function(e) NULL)
    }
    Sys.sleep(5)
    
    message("H2o objects after cleanup: ", nrow(h2o::h2o.ls()))
    message("H2o cluster memory after cleanup: ",
            round(h2o::h2o.clusterStatus()$mem_value_size$mem_value_size / 1024^2, 1),
            " MB")
        
    tibble::tibble()  # return empty tibble, not NULL
  },
  backend_options = agua_backend_options(parallelism = 1)  # h2o sequential too
)

start_time_tune <- Sys.time()
set.seed(8675309)




# 
# 
# test_params <- tibble::tibble(small_grid[2,])
# 
# finalized_wf <- BSB.H2O.Workflow |> finalize_workflow(test_params)
# 
# # Now test on fold 1
# 
# fold1_analysis <- analysis(myfolds$splits[[1]])
# test_fit<-fit(finalized_wf, data = fold1_analysis)
# 


message("Starting tune_grid()...")
flush.connection(stdout())
flush.connection(stderr())
small_grid<-h2o_grid[1:2,]

#flip the order of h2o_grid
h2o_grid<-h2o_grid[nrow(h2o_grid):1,]
# Start background logger
r_user <- system("whoami", intern = TRUE)
perf_log_file <- here("results", "h2o", "perf_usage.log")
system(
  paste0(
    "bash -c 'while true; do ",
    "CPU=$(top -bn2 -d0.5 | grep Cpu | tail -1 | awk \"{print \\$2+\\$4}\"); ",
    "MEM=$(ps -u ", r_user, " --no-headers -o rss | awk \"{sum+=\\$1} END {print sum/1024}\"); ",
    "echo \"$(date +%H:%M:%S) CPU: ${CPU}% MEM: ${MEM}MB\"; ",
    "sleep 5; done' > ", perf_log_file, " 2>&1 &"
  )
)
message("Performance logger started for user: ", r_user, ", writing to: ", perf_log_file)

tune_res <- tune_grid(
  BSB.H2O.Workflow,
  resamples = myfolds,
  grid      = h2o_grid,
  control   = rf_control_grid,
  metrics   = class_and_probs_metrics
)

system("pkill -f 'while true.*top'", ignore.stdout = TRUE, ignore.stderr = TRUE)
message("CPU logger stopped")

write_rds(tune_res, file = here("results", "h2o", tune_file_name))
end_time_tune <- Sys.time()
end_time_tune - start_time_tune

# --- Phase 3b: Bayesian optimization ---

# NOTE on tune_bayes() with h2o/agua:
# tune_bayes() from the tune package is designed to work with any parsnip-
# compatible engine, including h2o via agua. However, h2o models are submitted
# as jobs to the h2o cluster, which may interact unexpectedly with the sequential
# Bayesian acquisition logic. If tune_bayes() produces errors or hangs, comment
# out this block and proceed to Section 4 using tune_res instead of tune_res2.
# In that case, also change 'select_best(tune_res2, ...)' to 'select_best(tune_res, ...)'.
if(bayes_tune==TRUE){
  bayes_param <- BSB.H2O.Workflow %>%
    extract_parameter_set_dials() %>%
    update(mtry = finalize(mtry(), train_data))
  
  set.seed(9035768)
  start_time_bt <- Sys.time()
  
  tune_res2 <- tune_bayes(
    object     = BSB.H2O.Workflow,
    resamples  = myfolds,
    initial    = tune_res,
    param_info = bayes_param,
    iter       = 30,             # adjust as needed; mirrors ranger version
    control    = control_bayes(
      verbose       = TRUE,
      no_improve    = 10,
      save_pred     = TRUE,
      save_workflow = FALSE,
      extract       = NULL,
      parallel_over = "everything"
    ),
    metrics = metric_set(mn_log_loss)
  )
  
  end_time_bt <- Sys.time()
  end_time_bt - start_time_bt
  
  # Overwrite initial grid save with Bayesian results — mirrors ranger version behavior
  write_rds(tune_res2, file = here("results", "h2o", tune_file_name))
  
  autoplot(tune_res2, type = "performance") +
    labs(title = "Did Bayesian optimization converge? (h2o)")
}else if (bayes_tune==FALSE){
  tune_res2<-tune_res
}

#any errors?
tune_res2 |> 
  tune::collect_notes() |>
  dplyr::filter(type == "error") |>
  dplyr::select(location, note) |>
  print(width = 200)


# ============================================================
# Section 4: Model Selection and Finalization
# ============================================================

# Select best hyperparameters by mn_log_loss — mirrors ranger version
best_tree <- tune_res2 %>%
  select_best(metric = "brier_class")

best_tree

final_wf <- BSB.H2O.Workflow %>%
  finalize_workflow(best_tree)

# Right before the data_split, I had to take out the frequency_weights, because
# fread was having a problem with it downstream.  This creates a new "weighted" dataset
# Then, I 'update' the split object with this data.
estimation_dataset_weighted<-estimation_dataset %>%
  mutate(weighting = frequency_weights(as.integer(weighting)))

data_split_weighted <- data_split
data_split_weighted$data <- estimation_dataset_weighted


# This mirrors the ranger version exactly.
final_fit <- final_wf %>%
  last_fit(data_split_weighted, metrics = class_and_probs_metrics)

final_fitted_workflow <- extract_workflow(final_fit)

final_workflow_bundled <- bundle(final_fitted_workflow)
write_rds(final_workflow_bundled, file = here("results", "h2o", final_fit_file_name))

# Primary test-set metrics (mirrors ranger version output)
test_set_metrics<-final_fit %>% 
  collect_metrics()


test_set_metrics

final_preds <- collect_predictions(final_fit)

# ============================================================
# Section 5: Three-Way Split Evaluation
# ============================================================

# The ranger version evaluates on test only (via collect_metrics() above).
# The block below additionally evaluates on train and validation/calibrate splits
# by extracting the final fitted workflow and predicting on each split directly.



# NOTE on probability column names:
# augment() produces one column per class level, named .pred_<level>.
# The four expected class levels from market_desc are: Jumbo, Large, Medium, Small.
# To verify: levels(train_data$market_desc)

train_preds <- augment(final_fitted_workflow, new_data = train_data)
val_preds   <- augment(final_fitted_workflow, new_data = validation_data)
test_preds  <- augment(final_fitted_workflow, new_data = test_data)

train_metrics <- train_preds %>%
  class_and_probs_metrics(
    truth        = market_desc,
    estimate     = .pred_class,
    .pred_Jumbo, .pred_Large, .pred_Medium, .pred_Small,
    case_weights = weighting
  )

val_metrics <- val_preds %>%
  class_and_probs_metrics(
    truth        = market_desc,
    estimate     = .pred_class,
    .pred_Jumbo, .pred_Large, .pred_Medium, .pred_Small,
    case_weights = weighting
  )

test_metrics <- test_preds %>%
  class_and_probs_metrics(
    truth        = market_desc,
    estimate     = .pred_class,
    .pred_Jumbo, .pred_Large, .pred_Medium, .pred_Small,
    case_weights = weighting
  )

cat("\n--- Train metrics ---\n")
print(train_metrics)

cat("\n--- Validation/Calibrate metrics ---\n")
print(val_metrics)

cat("\n--- Test metrics ---\n")
print(test_metrics)


cat("\n--- Canned Test metrics ---\n")
print(test_set_metrics)


# ============================================================
# Section 6: Save Outputs
# ============================================================

# All outputs go to results/h2o/ — never to results/ranger/
# File names include "h2o" prefix; no ranger output is overwritten.

readr::write_rds(
  list(final_preds=final_preds, train = train_metrics, validation = val_metrics, test = test_metrics, canned=test_set_metrics),
  file = here("results", "h2o", split_metrics_name)
)

end_time <- Sys.time()
end_time
end_time - start_time
sessionInfo()

cat("All done\n")

# ============================================================
# Section 7: H2O Shutdown
# ============================================================

h2o.shutdown(prompt = FALSE)
