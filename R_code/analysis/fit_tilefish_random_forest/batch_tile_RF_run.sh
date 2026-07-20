#!/bin/bash
set -o pipefail
# data prep
Rscript --no-save --no-restore --verbose \
  ./R_code/data_extracting_processing/processing/tilefish/00_tilefish_processing_wrapper.R \
  2>&1 | stdbuf -oL -eL tee ./R_code/data_extracting_processing/processing/tilefish/00_tilefish_processing_wrapper.log

# Fit  
Rscript --no-save --no-restore --verbose \
  ./R_code/analysis/fit_tilefish_random_forest/fit_tilefish_classification.R \
  2>&1 | stdbuf -oL -eL tee ./R_code/analysis/fit_tilefish_random_forest/fit_tilefish_classification.log 



