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
                    glue("cams_gears_{in_string}.Rds")),
            overwrite = TRUE
)

file.copy(
  from=file.path(cfg$data_root,"data_folder", "external",
                 glue("deflatorsQ_{in_string}.Rds")),
  to=here("data_folder", "external",
          glue("deflatorsQ_{in_string}.Rds")),
  overwrite = TRUE
)

      

# -----------------------------------------------------------------------------
# Read landings_all
# -----------------------------------------------------------------------------
landings <- read_rds(
  file.path(cfg$data_root, "data_folder", "main", "tilefish",
            glue("tile_landings_all_{in_string}.Rds"))
)
# fill dlr_date with record_land if it is missing. This happens for "not sold" records 
landings <- landings %>%
  mutate(dlr_date = if_else(is.na(dlr_date), record_land, dlr_date) 
)
# -----------------------------------------------------------------------------
# Anonymize
# -----------------------------------------------------------------------------




#explictly set RNG state
RNGkind( kind="Mersenne-Twister",normal.kind="Inversion", sample.kind="Rejection")


generate_anonymized_key <- function(data, id_col, seed = NULL) {
  # NOTE: Explicit seed argument avoids non-reproducible keys across runs
  if (!is.null(seed)) {
    set.seed(seed)
  }
  
  data %>%
    # Subset to distinct IDs using tidy-eval data masking
    distinct({{ id_col }}) %>%
    # Assign uniform pseudo-random deviate for sorting
    mutate(rand_u = runif(n())) %>%
    # Reorder table based on random draw
    arrange(rand_u) %>%
    # Assign consecutive integers; glue syntax dynamic LHS constructs "new_<colname>"
    mutate("new_{{ id_col }}" := if_else(is.na({{ id_col }}), 
                                         NA_integer_, 
                                         row_number()
                                         )
           ) %>%    
    # Remove temporary sorting column
    select(-rand_u)
}


docid_keys  <- generate_anonymized_key(landings, docid, seed = 101)
camsid_keys <- generate_anonymized_key(landings, camsid, seed = 25152)
permit_keys <- generate_anonymized_key(landings, permit, seed = 8971)
hullid_keys <- generate_anonymized_key(landings, hullid, seed = 1546)
dlrid_keys <- generate_anonymized_key(landings, dlrid, seed = 142367)
area_keys <- generate_anonymized_key(landings, area, seed = 54871)
port_keys <- generate_anonymized_key(landings, port, seed = 57431)


keyfiles<-list()
keyfiles[[1]]<-docid_keys
keyfiles[[2]]<-camsid_keys
keyfiles[[3]]<-permit_keys
keyfiles[[4]]<-hullid_keys
keyfiles[[5]]<-dlrid_keys
keyfiles[[6]]<-area_keys
keyfiles[[7]]<-port_keys


names(keyfiles)<-c("docid_keys", "camsid_keys", "permit_keys", "hullid_keys", "dlrid_keys", "area_keys","port_keys")


landings_anon<-landings %>%
  left_join(docid_keys, by=join_by(docid==docid) )%>%
  select(-docid)%>%
  rename(docid=new_docid)

landings_anon<-landings_anon %>%
  left_join(camsid_keys, by=join_by(camsid==camsid) )%>%
  select(-camsid)%>%
  rename(camsid=new_camsid)


landings_anon<-landings_anon %>%
  left_join(permit_keys, by=join_by(permit==permit) )%>%
  select(-permit)%>%
  rename(permit=new_permit)

landings_anon<-landings_anon %>%
  left_join(hullid_keys, by=join_by(hullid==hullid) )%>%
  select(-hullid)%>%
  rename(hullid=new_hullid)

landings_anon<-landings_anon %>%
  left_join(dlrid_keys, by=join_by(dlrid==dlrid) )%>%
  select(-dlrid)%>%
  rename(dlrid=new_dlrid)

landings_anon<-landings_anon %>%
  left_join(area_keys, by=join_by(area==area) )%>%
  select(-area)%>%
  rename(area=new_area)

landings_anon<-landings_anon %>%
  left_join(port_keys, by=join_by(port==port) )%>%
  select(-port)%>%
  rename(port=new_port)

#reorder
stopifnot(ncol(landings_anon)==ncol(landings))

landings_anon <- landings_anon %>% 
  select(all_of(names(landings)))

  

# truncate dlr_date to just the date (without the time)
# generate a fishing time variable that is record_land-record_sail

landings_anon<-landings_anon %>%
  mutate(fishing_time=as.numeric(record_land-record_sail, units="days"),
      dlr_date = as_date(dlr_date))

landings_anon<-landings_anon %>%
  select(-c(dlr_stid, dlr_cflic, merge_species_codes, rec, record_land, record_sail) )

# -----------------------------------------------------------------------------
# Save anonymized dataset and keyfile
# -----------------------------------------------------------------------------
 
 saveRDS(landings_anon,  file =  here("data_folder","main", "tilefish",
                                      glue("tile_landings_all_anon_{in_string}.Rds")))
         
 saveRDS(keyfiles,  file =  here("data_folder","main", "tilefish",
                                     glue("tilefish_keyfiles_{in_string}.Rds")))

