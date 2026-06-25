#!/bin/bash
set -o pipefail
# Fit  
Rscript --no-save --no-restore --verbose \
  ./R_code/analysis/fit_tilefish_random_forest/fit_tilefish_random_forest.R \
  2>&1 | stdbuf -oL -eL tee ./R_code/analysis/fit_tilefish_random_forest/fit_tilefish_random_forest.log 



