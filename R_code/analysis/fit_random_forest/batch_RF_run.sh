#!/bin/bash

# batch file to run a bunch of RF models over the weekend
#Rscript --no-save --no-restore --verbose  ./estimate_randomforest_South_nocluster.R > estimate_randomforest_South_nocluster.log 2>&1

#Rscript --no-save --no-restore --verbose ./estimate_randomforest_nocluster.R > estimate_randomforest_nocluster.log 2>&1

#Rscript --no-save --no-restore --verbose  ./estimate_randomforest_North_nocluster.R > estimate_randomforest_North_nocluster.log 2>&1

# Rscript --no-save --no-restore --verbose ./estimate_5class_nocluster_randomforest.R > estimate_5class_nocluster_randomforest.log 2>&1

# Rscript --no-save --no-restore --verbose ./estimate_5class_randomforest.R > estimate_5class_randomforest.log 2>&1

 
#Rscript --no-save --no-restore --verbose ./estimate_randomforest_RegionN_nocluster.R > estimate_randomforest_RegionN_nocluster.log 2>&1

Rscript --no-save --no-restore --verbose  ./estimate_randomforest_nocluster_Tsubset.R > estimate_randomforest_nocluster_Tsubset.log 2>&1
