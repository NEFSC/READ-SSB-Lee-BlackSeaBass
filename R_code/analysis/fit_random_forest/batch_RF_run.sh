#!/bin/bash

# batch file to run a bunch of RF models over the weekend
#Rscript --no-save --no-restore --verbose ./estimate_randomforest_nocluster_Tsubset.R > estimate_randomforest_nocluster_Tsubset.log 2>&1

#Rscript --no-save --no-restore --verbose ./estimate_randomforest_nocluster.R > estimate_randomforest_nocluster.log 2>&1

#Run from the project root
Rscript --no-save --no-restore --verbose \
  ./R_code/analysis/fit_random_forest/estimate_orandomforest_nocluster.R \
  2>&1 | stdbuf -oL -eL tee ./results/h2o/estimate_orandomforest_nocluster.log


# Rscript --no-save --no-restore --verbose ./estimate_5class_randomforest.R > estimate_5class_randomforest.log 2>&1

 
#Rscript --no-save --no-restore --verbose ./estimate_randomforest_RegionN_nocluster.R > estimate_randomforest_RegionN_nocluster.log 2>&1

# Rscript --no-save --no-restore --verbose  ./estimate_randomforest.R > estimate_randomforest.log 2>&1
