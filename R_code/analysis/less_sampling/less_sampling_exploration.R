################################################################################
################################################################################
# Script:       less_sampling_exploration.R
# Purpose:      Explores doing less sampling by blending together length and age
#                 histograms.
# Inputs:       StockEff, via get_intermediate_stockeff() (ITIS 167687, 2013-2024)
# Outputs:      NONE. Everything stays in memory - `ages_combined` holds the six
#               joined series, `check` holds the reconciliation.
# Dependencies: get_intermediate_stockeff.R, get_ages.R,LAA_calculation_BSB.R
#               sourced in that order at lines 55-61
#               Also needs `nefscdb_con` to already exist in the session through .Rprofile
# Pipeline:     Hand-run. No wrapper calls this script, and it calls no other
#               script. It sits downstream of the random forest (which produces
#               the prediction files)
#
#
#
################################################################################
################################################################################

# =============================================================================
# Section 0: Load libraries, setup directories, source scripts
# Parse the predictions folder to get the out_of_sample_predictions
# =============================================================================


library("here")
library("glue")
library("conflicted")
library("ROracle")
conflicts_prefer(dplyr::filter())


here::i_am("R_code/analysis/less_sampling/less_sampling_exploration.R")

source(here("R_code/LAA_calculation/get_intermediate_stockeff.R"))

# The reapportionment work here is
# done with get_ages() instead, one call per landings source.

source(here("R_code/LAA_calculation/get_ages.R"))
source(here("R_code","LAA_calculation","LAA_calculation_BSB.R"))

options(scipen=999)


# Vintage-selection idiom, repeated throughout this project: glob the folder,
# strip the fixed prefix and suffix off the filenames to leave a bare ISO date,
# then take max() to get the newest. max() on ISO dates is lexicographic but
# gives the right answer because YYYY-MM-DD sorts the same either way.

predictions_vintage<-list.files(here("data_folder","predictions"), pattern=glob2rx("out_of_sample_predictions_YRS_nocluster*.Rds"))
predictions_vintage<-gsub("out_of_sample_predictions_YRS_nocluster","",predictions_vintage)
predictions_vintage<-gsub(".Rds","",predictions_vintage)
predictions_vintage<-max(predictions_vintage)

stopifnot(length(predictions_vintage)==1)

predictions_full_location1<-here("data_folder","predictions", glue("out_of_sample_predictions_YRS_nocluster{predictions_vintage}.Rds"))
predictions_full_location2<-here("data_folder","predictions", glue("ambitious_out_of_sample_predictions_YRS_nocluster{predictions_vintage}.Rds"))

# out_of_sample_predictions_reg contains some Unclassifieds
# out_of_sample_predictions_amb does not.
# i.e. "conservative" vs "ambitious": the ambitious model assigns every
# unclassified transaction to a market category, the conservative one is
# allowed to leave some fish unclassified. Both files contain the
# same total kilograms.

out_of_sample_predictions_reg<-readRDS(predictions_full_location1)
out_of_sample_predictions_amb<-readRDS(predictions_full_location2)


# Pounds per kg
lbs_per_kg<-2.20462

# =============================================================================
# Section 1: Pull BSB data from stockeff
# =============================================================================


drv<-dbDriver("Oracle")
connection <- eval(nefscdb_con)

# NOTE THE YEAR RANGE. 2013-2024 here, against 1989-2024 in LAA_test_script.R
# and fit_BSB_WHAM.R. That is deliberate - the CAMS combined dataset read in
# Section 2 only covers 2013 on, and the comparison below is only meaningful
# over the years both sources cover. It does mean LAA_OLD computed here does not 
# have the same temporal range as LAA_OLD produced by the other scripts.

bsb_stockeff<-get_intermediate_stockeff(species_itis = '167687',
                           fyr = 2013, #Just 2013
                           lyr = 2025, #through 2024, 2025 not yet ready
                           connection = connection)


#bsb_stockeff$mkt.res <-bsb_stockeff$mkt.res %>%
#  mutate(MARKET_DESC=case_when(
#  MARKET_DESC == "MEDIUM OR SELECT" ~ "MEDIUM",
#  TRUE              ~ MARKET_DESC)
#)

# Everything below this line works on the three data frames already
# returned into bsb_stockeff, so no further database access is needed.

#saveRDS(bsb_stockeff, file=here("data_folder", "predictions", glue("bsb_stockeff_{predictions_vintage}.Rds")))


# Construct separate datasets of large, Medium, and Jumbo that are zero-filled for all other market categories.
# dropping LANDINGS_KG will cause the LAA_calcuation_BSB to error when run with sumflag="sum" This is by design.

# Merge and zero fill

stockeff_working <- bsb_stockeff$comm.land.res %>%
  left_join(bsb_stockeff$mkt.res, by = join_by(NESPP4)) %>%
  relocate(YEAR, SPECIES_ITIS, STOCK_ABBREV, SEX_TYPE, NESPP4, REGION_ID, BLOCK_ID) %>%
  select(-c(LANDINGS_KG_NOADJ, EXP_RATIO))  

mkt_cats <- c("LARGE", "JUMBO", "MEDIUM OR SELECT", "SMALL")

# Map over categories to generate the named list
stockeff_list <- mkt_cats %>%
  # set_names() ensures purrr returns a list natively named by these values
  set_names((.)) %>% 
  map(~ stockeff_working %>%
        mutate(
          # .x injects the current market category string into the logic check.
          # The TRUE ~ 0 catch-all safely handles both non-matches and NAs.
          LANDINGS_KG_CATEGORY_APPORTION = case_when(
            MARKET_DESC == .x ~ LANDINGS_KG,
            TRUE              ~ 0
          )
        ) %>%
        select(-LANDINGS_KG)
  )



total_stockeff<-bsb_stockeff$comm.land.res %>%
  summarise(LANDINGS_KG=sum(LANDINGS_KG))



# check that you did the zero out properly
total_stockeff<-bsb_stockeff$comm.land.res %>%
  left_join(bsb_stockeff$mkt.res, by=join_by(NESPP4)) %>%
  group_by(MARKET_DESC) %>%
  summarise(LANDINGS_KG=sum(LANDINGS_KG)) %>%
  ungroup() %>%
  arrange(MARKET_DESC)


processed_totals_df <- purrr::map_dfr(
  stockeff_list, 
  ~ dplyr::summarise(.x, 
                     LANDINGS_KG_CATEGORY_APPORTION = sum(LANDINGS_KG_CATEGORY_APPORTION, na.rm = TRUE)),
  .id = "MARKET_DESC"
) %>%
  arrange(MARKET_DESC)

processed_totals_df
total_stockeff

# you did.

# 
# # prep stockeff by hand
# bsb_sf_prepped<-bsb_stockeff$comm.land.res %>%
#   left_join(bsb_stockeff$mkt.res, by=join_by(NESPP4)) %>%
#   rename(LANDINGS_KG_CATEGORY_APPORTION = LANDINGS_KG) %>%
#   relocate(YEAR, SPECIES_ITIS, STOCK_ABBREV, SEX_TYPE, NESPP4, REGION_ID, BLOCK_ID) %>%
#   select(-c(LANDINGS_KG_NOADJ, EXP_RATIO))
# 
# processed_all<-bsb_sf_prepped %>%
#   summarise(LANDINGS_KG_CATEGORY_APPORTION=sum(LANDINGS_KG_CATEGORY_APPORTION)) %>%
#   pull(LANDINGS_KG_CATEGORY_APPORTION)
# 
# message("There are ", processed_all, "kg of total landings prepped and going into STOCKEFF")
# 
# 
# stopifnot(!anyNA(stockeff_large_only$NESPP4))

    
   

####################################
# pass in each market category individually
####################################

# Compute age composition for each market category separately. 

###########Removes the NA age classes
############
CAA_solo <- purrr::map(
  stockeff_list, 
  ~ LAA_calculation(
    species_itis = '167687',
    out_of_sample_predictions = .x,
    fyr = 2013,
    lyr = 2025,
    connection = connection,
    sumflag="solo",
    plotson=FALSE,
    plotstub="bau"
    ) %>%
    filter(CAA_TYPE=="Apportioned",
           !is.na(AGE)) %>%
    select(-CAA_TYPE)
)
dbDisconnect(connection)

# Contract to 8 age classes, stick market_desc back in the dataframe
CAA_solo <- purrr::imap(
  CAA_solo, 
  ~.x %>%
  mutate(AGE = case_when(
    AGE >= 8 ~ 8,
    TRUE     ~ AGE),
    MARKET_DESC = .y) %>%
  group_by(SPECIES_ITIS,STOCK_ABBREV,MARKET_DESC, YEAR,AGE) %>% 
    summarise(CAA = sum(CAA, na.rm=TRUE),
              WAA = sum(WAA, na.rm=TRUE)
              )%>%
  select(SPECIES_ITIS, STOCK_ABBREV, MARKET_DESC, YEAR, AGE, CAA, WAA) 
)


# lets look at the catch at age, by market category and year.
# Focus on the Jumbo, Large, and Medium, just for a few years
# Try "blending" the J and M.  
#         Convert each to a pdf/cdf.

CAA_compositions <- purrr::imap(
  CAA_solo, 
  ~.x %>%
    group_by(SPECIES_ITIS,STOCK_ABBREV, MARKET_DESC, YEAR) %>% 
    mutate(CAA_tot = sum(CAA, na.rm=TRUE)
    )%>%
    mutate(CAA_comp=CAA/CAA_tot)%>%
    select(SPECIES_ITIS, STOCK_ABBREV, MARKET_DESC, YEAR, AGE, CAA_comp) 
)


alpha_list<-c(1, 10,20, 30, 35, 40, 45, 50, 55, 60, 65, 70, 75, 80, 90, 99)






CAA_MB<-CAA_compositions$`MEDIUM OR SELECT` %>% 
  ungroup() %>%
  rename(CAA_Comp_Medium=CAA_comp) %>%
  select(-MARKET_DESC)

CAA_JB<-CAA_compositions$JUMBO %>% 
  ungroup() %>%
  rename(CAA_Comp_Jumbo=CAA_comp) %>%
  select(-MARKET_DESC)

#done to here. merge. Add the two CAAs.  Plot, compare to Large on ly
CAA_blend<-CAA_MB %>%
  full_join(CAA_JB, by=join_by(SPECIES_ITIS, STOCK_ABBREV, YEAR, AGE))


CAA_blend<-CAA_blend %>%
  full_join(CAA_compositions$LARGE, by=join_by(SPECIES_ITIS, STOCK_ABBREV, YEAR, AGE)) %>%
  select(-MARKET_DESC) %>%
  rename(CAA_Comp_Large=CAA_comp)




# Map over the list of dataframes
CAA_blend_list <- purrr::map(
  alpha_list, 
  ~ CAA_blend %>%
    mutate(
      alpha = .x,
      CAA_Comp_Large_sub = (.x / 100) * CAA_Comp_Jumbo + (1 - (.x / 100)) * CAA_Comp_Medium
    ) %>%
    pivot_longer(cols=starts_with("CAA_Comp"),
                 values_to="CAA_prop",
                 names_to="CAA_TYPE",
                 names_prefix="CAA_Comp_")
  
  )

#Name the items in the list
CAA_blend_list<-set_names(CAA_blend_list,alpha_list)

CAA_plots<-purrr::imap(
  CAA_blend_list, 
  ~ {
    
    p<-.x %>%
    filter(YEAR>=2017, YEAR<=2019) %>%
    filter(CAA_TYPE %in% c("Large","Large_sub")) %>%
    ggplot(
      aes(x=AGE,
          y=CAA_prop,
          col=CAA_TYPE,
          fill = CAA_TYPE)
      ) + 
  geom_col(position = "dodge", alpha = 0.5, linewidth=0.1) + 
  theme_bw(base_size = 9) +
  scale_x_continuous(
    breaks = 2:8,
    labels = c("2", "3", "4", "5", "6", "7", "8+")
  ) +
  scale_fill_grey(start = 0.2, end = 0.7) +
  scale_color_grey(start = 0.2, end = 0.7) +
  theme(
    axis.text.x      = element_text(size = 7, colour = "grey20",
                                    angle = 45, hjust = 1),
    axis.text.y      = element_text(size = 7, colour = "grey20"),
    axis.title       = element_text(size = 8),
    legend.title     = element_text(size = 7),
    legend.text      = element_text(size = 8),
    legend.key.height = unit(0.4, "cm"),
    legend.key.width  = unit(0.3, "cm"),
    legend.position  =  "bottom",
    panel.grid       = element_blank(),
    panel.border     = element_rect(colour = "grey40", linewidth = 0.5),
    plot.margin      = margin(4, 4, 4, 4, "pt")
  ) + 
  labs(
    x = "Age",
    y = "Catch-at-Age proportions (based on numbers)",
    color = NULL, 
    fill = NULL,
    title = glue::glue("Large_sub is {.y}% Jumbo and (100-{.y})% Medium")
  ) +
  facet_grid(YEAR ~ STOCK_ABBREV)  

  
  ggsave(
    filename = here("results",glue("EIDC_CAA_blend_{.y}.png")),
    plot=p,
    width  = 168,
    height = 168,
    units  = "mm",
    device = png
  )
return(p)
  }
)

# Use imagemagick's convert to stack into a gif.
fp<-here("results")
command_to_eval<-glue("convert -delay 100 -loop 0  {fp}/EIDC_*.png   {fp}/EIDC_CAA_blended.gif")
system(command_to_eval)

# I've got alot of graphs and combinations here
# 2017  -- North 70%J, 30% M
# 2018  -- North 60%J, 40%M
# 2019  -- South 10% J, 90% M

# It looks like we can match a single peak or a double peak, but not a plateau.

