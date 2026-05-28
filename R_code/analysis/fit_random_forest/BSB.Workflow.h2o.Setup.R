###############################################################################
# Purpose: Script to set up the BSB h2o Workflow.
#          This is the h2o/agua analogue of BSB.Workflow.Setup.R.
#          It is sourced by estimate_h2orandomforest_nocluster.R.
#
# Requires the following objects to already exist in the environment:
#   - BSB.Classification.Recipe  (from BSB.Classification.Recipe.R)
#   - search_type                (set in the calling estimation script)
#   - npredict                   (set in BSB.Classification.Recipe.R)
###############################################################################

# ============================================================
# Section 1: H2O Initialization
# ============================================================

# Initialize h2o. Adjust nthreads and max_mem_size to match your hardware.
# This container has approximately 24 threads and 96 GB RAM available.
# Conservative defaults leave headroom for R, the OS, and cross-validation overhead.

h2o.init(
  nthreads     = 8,    # adjust as needed; using 16 of ~24 available threads
  max_mem_size = "32g"  # adjust as needed; using 72 of ~96 GB RAM
)

# ============================================================
# Section 2: Model Specification
# ============================================================

#   RECIPE COMPATIBILITY NOTE 
# H2o handles categorical (factor) predictors natively — it does not require
# or benefit from prior dummy encoding.
#
# If step_dummy() is ever added to BSB.Classification.Recipe.R in the future,
# remove or disable it before passing the recipe to an h2o workflow. Dummy-
# encoding factor variables before h2o sees them is redundant at best and may
# corrupt the model. 

tune_spec_h2o <- rand_forest(
  trees = 500,    # adjust as needed; higher values increase stability but slow training
  mtry  = tune(),
  min_n = tune()
) %>%
  set_mode("classification") %>%
  set_engine(
    "h2o",
    seed            =  286724  ,
    # categorical_encoding = "SortByResponse",  # matches ranger "order", but I'm not going to do this.
    histogram_type  = "QuantilesGlobal",    # robust binning well-suited to large, skewed datasets
    sample_rate     = 0.632,                # bootstrap-equivalent row-sampling fraction (Breiman 2001)
    nbins           = 32,                   # number of histogram bins per feature; increase for finer splits
    stopping_rounds = 0,                    # Do not do early stopping
    varimp_type           = "permutation"   # request permutation importance
 
 )

# ============================================================
# Section 3: Workflow
# ============================================================

# Naming convention mirrors BSB.Ranger.Workflow from BSB.Workflow.Setup.R.
BSB.H2O.Workflow <-
  workflow() %>%
  add_model(tune_spec_h2o) %>%
  add_recipe(BSB.Classification.Recipe) %>%
  add_case_weights(weighting)  # weight column name confirmed: 'weighting'

hardhat::extract_parameter_set_dials(BSB.H2O.Workflow)

# ============================================================
# Section 4: Metrics
# ============================================================

# Identical metric set to BSB.Workflow.Setup.R.
# Because the workflow carries case weights, all three metrics are weight-aware.
class_and_probs_metrics <- metric_set(brier_class, mn_log_loss, roc_auc)

# ============================================================
# Section 5: Tuning Grid
# ============================================================

# Space-filling grid strategy mirrors BSB.Workflow.Setup.R exactly.
# search_type must be set in the calling estimation script before this file is sourced.
# Edit ranges and sizes here to adjust the search.

# h20's min_n is the sum of frequency weights

if (search_type == "Initial") {
  h2o_grid <- grid_space_filling(
    mtry(range  = c(5L, 35L)),   # number of candidate predictors sampled per split
    min_n(range = c(500L, 200000L)),  # minimum weight (sum of frequency weights) required in a leaf node
    size = 24                    # number of grid points for initial exploration
  )
}

if (search_type == "Advanced") {
  h2o_grid <- grid_space_filling(
    mtry(range  = c(10L, 35L)),  # tightened after initial search; upper bound near ~40 predictors
    min_n(range = c(500L, 200000L)),  # minimum weight (sum of frequency weights)  required in a leaf node
    size = 120                   # larger grid for refined hyperparameter search
  )
}

if (search_type == "Prototype") {
  h2o_grid <- grid_space_filling(
    mtry(range  = c(2L, npredict)), # full range; npredict comes from BSB.Classification.Recipe.R
    min_n(range = c(1000L, 5000L)),  # minimum weight (sum of frequency weights)  required in a leaf node
    size = 4                        # minimal grid; use only for quick code testing
  )
}
