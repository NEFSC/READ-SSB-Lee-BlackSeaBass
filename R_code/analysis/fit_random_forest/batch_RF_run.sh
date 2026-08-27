#!/bin/bash
set -e
set -o pipefail
# batch file to the Tune, train, Variable importance code
# Run from the project root.
#
# set -e            : abort the batch as soon as any step fails.
# set -o pipefail   : make a failing Rscript visible through the `| tee` pipeline,
#                     instead of the pipeline reporting tee's (successful) status.
# && between steps  : each step only starts if the previous one succeeded. This is
#                     belt-and-braces with set -e, but it keeps the dependency
#                     explicit and survives someone removing set -e later.
#
# tee cannot create directories. Without this the first step would abort the whole
# run on a fresh checkout, because ./results/ranger does not exist yet.
mkdir -p ./results/ranger

# Tune
 Rscript --no-save --no-restore --verbose \
   ./R_code/analysis/fit_random_forest/tune_randomforest_nocluster.R \
   2>&1 | stdbuf -oL -eL tee ./results/ranger/tune_randomforest_nocluster.log &&

# Train
Rscript --no-save --no-restore --verbose \
  ./R_code/analysis/fit_random_forest/train_randomforest_nocluster.R \
  2>&1 | stdbuf -oL -eL tee ./results/ranger/train_randomforest_nocluster.log &&

# Fit the Variable importance
 Rscript --no-save --no-restore --verbose \
   ./R_code/analysis/fit_random_forest/variable_importance_randomforest_nocluster.R \
  2>&1 | stdbuf -oL -eL tee ./results/ranger/variable_importance_randomforest_nocluster.log &&

#################################################
# Perform the weighted calibration
#################################################
 Rscript --no-save --no-restore --verbose \
   ./R_code/analysis/fit_random_forest/weighted_calibration.R \
  2>&1 | stdbuf -oL -eL tee ./R_code/analysis/fit_random_forest/weighted_calibration.log &&

######################
# Make figures
 Rscript --no-save --no-restore --verbose \
   ./writing/figure1.R \
  2>&1 | stdbuf -oL -eL tee ./writing/figure1.log &&

 # Figure 2 requires windows, so you have to run this by hand
 # Rscript --no-save --no-restore --verbose \
 #   ./writing/figure2.R \
 #  2>&1 | stdbuf -oL -eL tee ./writing/figure2.log

# Predictions heatmap
Rscript -e "rmarkdown::render('writing/predictions_heatmap.Rmd', output_format='html_document')" &&


# tuning_diagnostics (Fold-level ROC curves)
Rscript -e "rmarkdown::render('writing/tuning_diagnostics.Rmd', output_format='html_document')" &&

# out_of_sample_predictions
Rscript -e "rmarkdown::render('writing/out_of_sample_predictions.Rmd', output_format='html_document')" &&

# ROC curves from the Trained model, computed on the training set and testing set
Rscript --no-save --no-restore --verbose \
   ./R_code/analysis/fit_random_forest/plot_ROC_curves.R \
  2>&1 | stdbuf -oL -eL tee ./R_code/analysis/fit_random_forest/plot_ROC_curves.log &&

# This success message is deliberately the LAST link of the && chain, not a
# separate statement. set -e does not abort on a failure that happens partway
# through a && list (POSIX exempts every command except the one after the final
# &&), so a trailing standalone echo would still run after a failed step and
# report success with exit status 0. Chaining it means a failed step skips the
# message, and the chain's non-zero status becomes the script's exit status.
echo "batch_RF_run.sh: all steps completed successfully."




########################
# TO DO:
#  render the manuscript - you're not actually going to do this, but
# Rscript -e "rmarkdown::render('writing/Economic_informed_stock_assessments.Rmd', output_format='pdf_document')"
