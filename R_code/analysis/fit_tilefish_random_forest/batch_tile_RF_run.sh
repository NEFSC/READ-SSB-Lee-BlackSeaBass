#!/bin/bash
set -e
set -o pipefail
###############################################################################
# This will run the data prep routine, model tuning, and model training
#     Run from the project root with:
#    ./R_code/analysis/fit_tilefish_random_forest/batch_tile_RF_run.sh
# 
# To skip the data prep (because it's already done and good), comment out those 3 lines
###############################################################################
#
# set -e / set -o pipefail / && between steps: see batch_RF_run.sh for the rationale.
# In short - abort the batch as soon as a step fails, and make a failing Rscript
# visible through the `| tee` pipeline rather than reporting tee's status.
export R_CONFIG_ACTIVE="Hilo"
echo $R_CONFIG_ACTIVE
# data prep
 Rscript --no-save --no-restore --verbose \
   ./R_code/data_extraction_processing/processing/tilefish/00_tilefish_processing_wrapper.R \
   2>&1 | stdbuf -oL -eL tee ./R_code/data_extraction_processing/processing/tilefish/00_tilefish_processing_wrapper.log &&

# Fit
Rscript --no-save --no-restore --verbose \
  ./R_code/analysis/fit_tilefish_random_forest/fit_tilefish_classification.R \
  2>&1 | stdbuf -oL -eL tee ./R_code/analysis/fit_tilefish_random_forest/fit_tilefish_classification.log

echo "batch_tile_RF_run.sh: all steps completed successfully."

