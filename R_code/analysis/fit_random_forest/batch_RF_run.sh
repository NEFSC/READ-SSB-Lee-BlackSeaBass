#!/bin/bash

# batch file to run a bunch of RF models over the weekend

Rscript --no-save --no-restore --verbose  ./estimate_randomforest.R > estimate_randomforest.log 2>&1

Rscript --no-save --no-restore --verbose  ./estimate_randomforest_nocluster.R > estimate_randomforest_nocluster.log 2>&1

# Rscript --no-save --no-restore --verbose ./estimate_5class_nocluster_randomforest.R > estimate_5class_nocluster_randomforest.log 2>&1

# Rscript --no-save --no-restore --verbose ./estimate_5class_randomforest.R > estimate_5class_randomforest.log 2>&1

 
