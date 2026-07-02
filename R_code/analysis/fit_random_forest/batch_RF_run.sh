#!/bin/bash
set -o pipefail
# batch file to the Tune, train, Variable importance code
# Tune. Run from the project root
# Rscript --no-save --no-restore --verbose \
#   ./R_code/analysis/fit_random_forest/tune_randomforest_nocluster.R \
#   2>&1 | stdbuf -oL -eL tee ./results/ranger/tune_randomforest_nocluster.log #\
#&& \
# Train \
#Rscript --no-save --no-restore --verbose \
#  ./R_code/analysis/fit_random_forest/train_randomforest_nocluster.R \
#  2>&1 | stdbuf -oL -eL tee ./results/ranger/train_randomforest_nocluster.log #\
#&& \
# Fit the Variable importance 
# Rscript --no-save --no-restore --verbose \
#   ./R_code/analysis/fit_random_forest/variable_importance_randomforest_nocluster.R \
#  2>&1 | stdbuf -oL -eL tee ./results/ranger/variable_importance_randomforest_nocluster.log

#################################################
# Perform the weighted calibration
#################################################
 Rscript --no-save --no-restore --verbose \
   ./R_code/analysis/fit_random_forest/weighted_calibration.R \
  2>&1 | stdbuf -oL -eL tee ./R_code/analysis/fit_random_forest/weighted_calibration.log

######################
# Make figures
 Rscript --no-save --no-restore --verbose \
   ./writing/figure1.R \
  2>&1 | stdbuf -oL -eL tee ./writing/figure1.log

 # Figure 2 requires windows, so you have to run this by hand
 # Rscript --no-save --no-restore --verbose \
 #   ./writing/figure2.R \
 #  2>&1 | stdbuf -oL -eL tee ./writing/figure2.log

# Predictions heatmap
Rscript -e "rmarkdown::render('writing/predictions_heatmap.Rmd', output_format='html_document')"


# tuning_diagnostics heatmap
Rscript -e "rmarkdown::render('writing/tuning_diagnostics.Rmd', output_format='html_document')"

# out_of_sample_predictions
Rscript -e "rmarkdown::render('writing/out_of_sample_predictions.Rmd', output_format='html_document')"


########################
# render the manuscript - you're not actually going to do this, but 
# Rscript -e "rmarkdown::render('writing/Economic_informed_stock_assessments.Rmd', output_format='pdf_document')"

