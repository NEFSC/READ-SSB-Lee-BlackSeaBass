###############################################################################
# A00_tilefish_anonymizer.R
# Purpose: remove confidential information from the tilefish dataset.  
#
# Inputs:
#   - landings_all_{in_string}.Rds       (R-produced, DataPull repo)
#
# Outputs:
#   - landings_all_anon_{in_string}.Rds       (R-produced, DataPull repo)
# Also copies deflators and gearcode to local directory
# Expects in environment:
#   in_string, vintage_string, data_main
#   apply_gear_categories(), apply_bsb_market_rebinning(), apply_bsb_grade_cleaning()
#   from gear_market_helpers.R (sourced by wrapper)
###############################################################################

library("here")
library("tidyverse")
library("lubridate")
library("glue")
library("slider")

library("conflicted")
conflicts_prefer(dplyr::filter)
conflicts_prefer(lubridate::year)
conflicts_prefer(lubridate::month)
conflicts_prefer(lubridate::week)
conflicts_prefer(dplyr::summarise)
conflicts_prefer(dplyr::arrange)


here::i_am("R_code/data_extraction_processing/processing/tilefish/A00_tilefish_anonymizer.R")

cfg <- config::get(file = here("config.yml"))
stopifnot(cfg$runtype=="NefscContainer")
tile_data_dir<-here("data_folder", "main", "tilefish")     
dir.create(tile_data_dir, showWarnings=FALSE)

commercial_data_dir<-here("data_folder", "main", "commercial")     
dir.create(commercial_data_dir, showWarnings=FALSE)


in_string      <- "2026-06-09"  
vintage_string <- Sys.Date()   # matches Stata vintage_string / output vintage
lbs_to_kg<-2.20462

source(here("R_code", "analysis","helpers",  "gear_market_helpers.R"))

# Move cams_gears and the deflators from the datapull directory to the analysis directory
file.copy(
    from=file.path(cfg$data_root,"data_folder", "main", "commercial",
                   glue("cams_gears_{in_string}.Rds")),
    to=here("data_folder","main", "commercial", 
                    glue("cams_gears_{in_string}.Rds"))
)

file.copy(
  from=file.path(cfg$data_root,"data_folder", "external",
                 glue("deflatorsQ_{in_string}.Rds")),
  to=here("data_folder", "external",
          glue("deflatorsQ_{in_string}.Rds"))
)

      

# -----------------------------------------------------------------------------
# Read landings_all
# -----------------------------------------------------------------------------
landings <- read_rds(
  file.path(cfg$data_root, "data_folder", "main", "tilefish",
            glue("tile_landings_all_{in_string}.Rds"))
)

# -----------------------------------------------------------------------------
# Anonymize
# -----------------------------------------------------------------------------

landings_anon<-landings




# -----------------------------------------------------------------------------
# Save anonymized dataset and keyfile
# -----------------------------------------------------------------------------

saveRDS(landings_anon,  file =  here("data_folder","main", "tilefish",
                                     glue("tile_landings_all_anon_{in_string}.Rds")))
        

