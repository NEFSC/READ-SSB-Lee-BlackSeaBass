global in_string 2025_07_09
do "$processing_code/commercial/A01_data_prep.do"


/* Run the R code */
/* this doesn't work because the data_prep_ml.R script depends on setting directories with here and having an open project. 
Starting this executes in in the working directory, so here fails

I don't want to figure it out, so the next best thing is that I need to run the data_prep_ml.R in Rstudio.

local execute_me  "${dir_to_R}\Rscript.exe --no-save --no-restore --verbose $R_code/data_extraction_processing/processing/data_prep_ml.R >  $R_code/data_extraction_processing/processing/data_prep_ml.log 2>&1"

shell `execute_me'
*/