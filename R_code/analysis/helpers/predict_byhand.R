
# =============================================================================
# PREDICTION WRAPPER
#
# This function enforces the bake → predict sequence programmatically.
# It is the safety equivalent of a fitted workflow's predict() method:
# you cannot call the model without preprocessing because the preprocessing
# is inside the function.
#
# Usage (fresh session or production):
#   preds <- predict_market(unclassified_data)
#
# Arguments:
#   new_data     — raw data frame in the same format as the training data
#                  (unexpanded; must contain all predictor columns)
#   prepped_recipe  — the prepped_recipe
#   ranger_fitted_model   — the output of a ranger fit
#
# Returns a tibble with columns .pred_CCCCCCCC,
# one row per row of new_data.
# =============================================================================
predict_byhand <- function(new_data=train_data,
                           prepped_recipe = prepped_recipe,
                           ranger_fitted_model  = final_ranger_fit) {
  
  # ranger sees the data — step_novel() ensures unseen factor levels are pooled
  # to "new" rather than causing an error.
  new_baked <- bake(prepped_recipe, new_data = new_data)
  
  # -- Predict: return class probabilities -------------------------------------
  predict(ranger_fitted_model, data = new_baked, type = "response")$predictions %>%
    as_tibble() %>%
    rename_with(~ paste0(".pred_", .))
}

