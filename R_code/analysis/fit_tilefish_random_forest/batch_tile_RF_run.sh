#!/bin/bash
set -e
set -o pipefail
# Run from the project root.
#
# set -e / set -o pipefail / && between steps: see batch_RF_run.sh for the rationale.
# In short - abort the batch as soon as a step fails, and make a failing Rscript
# visible through the `| tee` pipeline rather than reporting tee's status.

# data prep
# Rscript --no-save --no-restore --verbose \
#   ./R_code/data_extraction_processing/processing/tilefish/00_tilefish_processing_wrapper.R \
#   2>&1 | stdbuf -oL -eL tee ./R_code/data_extraction_processing/processing/tilefish/00_tilefish_processing_wrapper.log &&

# Fit
Rscript --no-save --no-restore --verbose \
  ./R_code/analysis/fit_tilefish_random_forest/fit_tilefish_classification.R \
  2>&1 | stdbuf -oL -eL tee ./R_code/analysis/fit_tilefish_random_forest/fit_tilefish_classification.log

echo "batch_tile_RF_run.sh: all steps completed successfully."
