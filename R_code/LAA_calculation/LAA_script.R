################################################################################
################################################################################
# Script:       LAA_script.R
# Purpose:      Builds five parallel landings-at-age (LAA) series for black sea
#               bass from five different landings sources and joins them side by
#               side so they can be compared. This is a verification and
#               decomposition script, not a production path: it writes nothing
#               to disk and ends with an in-memory identity check.
# Inputs:       out_of_sample_predictions_YRS_nocluster<vintage>.Rds
#               ambitious_out_of_sample_predictions_YRS_nocluster<vintage>.Rds
#               StockEff, via get_stockeff() (ITIS 167687, 2013-2024)
# Outputs:      NONE. Everything stays in memory - `ages_combined` holds the six
#               joined series, `check` holds the reconciliation.
# Dependencies: get_intermediate_stockeff.R, get_ages.R,LAA_calculation_BSB.R
#               sourced in that order at lines 55-61
#               Also needs `nefscdb_con` to already exist in the session through .Rprofile
# Pipeline:     Hand-run. No wrapper calls this script, and it calls no other
#               script. It sits downstream of the random forest (which produces
#               the prediction files) and parallel to LAA_test_script.R, which
#               exercises the monolithic LAA_calculation() instead.
#
# THE Five SERIES. Each is landings-at-age computed from a different landings
# source, NOT YET  joined on (SPECIES_ITIS, STOCK_ABBREV, YEAR, AGE):
#   CAA_sum_reg      the conservative random forest apportionment.
#   CAA_sum_amb      the ambitious random forest apportionment.
#   CAA_solo_reg    Just the MARKET_DESC_ORIG=unclassified for the conservative random forest apportionment.
#   CAA_solo_amb    Just the MARKET_DESC_ORIG=unclassified for the ambitious random forest apportionment.
#   CAA_bau         Just the unclassifieds, straight out of Stockeff
#
#
#
################################################################################
################################################################################

# This script has two goals
# 1. Make sure that the refactoring of the LAA calculation into constituent parts works
# 2. show how to get NAA.


# =============================================================================
# Section 0: Load libraries, setup directories, source scripts
# Parse the predictions folder to get the out_of_sample_predictions
# =============================================================================


library("here")
library("glue")
library("conflicted")
library("ROracle")
conflicts_prefer(dplyr::filter())


here::i_am("R_code/LAA_calculation/LAA_script.R")

source(here("R_code/LAA_calculation/get_intermediate_stockeff.R"))

# The reapportionment work here is
# done with get_ages() instead, one call per landings source.

source(here("R_code/LAA_calculation/get_ages.R"))
source(here("R_code","LAA_calculation","LAA_calculation_BSB.R"))




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

bsb_stockeff<-get_intermediate_stockeff(species_itis = 167687,
                           fyr = 2013, #Just 2013
                           lyr = 2025, #through 2024, 2025 not yet ready
                           connection = connection)

# Everything below this line works on the three data frames already
# returned into bsb_stockeff, so no further database access is needed.




# Construct a dataset of Unclassifieds,that is zero-filled for all other market categories.
# dropping LANDINGS_KG will cause the LAA_calcuation_BSB to error when run with sumflag="sum" This is by design.

# Merge and zero fill
stockeff_unclass_only<-bsb_stockeff$comm.land.res %>%
  left_join(bsb_stockeff$mkt.res, by=join_by(NESPP4)) %>%
 mutate(LANDINGS_KG_CATEGORY_APPORTION = case_when(
      MARKET_DESC=="UNCLASSIFIED" ~ LANDINGS_KG,
      MARKET_DESC!="UNCLASSIFIED" ~ 0,
      TRUE ~ 0)
    )  %>%
  relocate(YEAR, SPECIES_ITIS, STOCK_ABBREV, SEX_TYPE, NESPP4, REGION_ID, BLOCK_ID) %>%
  select(-c(LANDINGS_KG_NOADJ, LANDINGS_KG,EXP_RATIO))


total_stockeff<-bsb_stockeff$comm.land.res %>%
  summarise(LANDINGS_KG=sum(LANDINGS_KG))



# check that you did the zero out properly
total_stockeff_unc<-bsb_stockeff$comm.land.res %>%
  left_join(bsb_stockeff$mkt.res, by=join_by(NESPP4)) %>%
  filter(MARKET_DESC=="UNCLASSIFIED") %>%
  summarise(LANDINGS_KG=sum(LANDINGS_KG)) %>%
  pull(LANDINGS_KG)

processed_unc<-stockeff_unclass_only %>%
  summarise(LANDINGS_KG_CATEGORY_APPORTION=sum(LANDINGS_KG_CATEGORY_APPORTION)) %>%
  pull(LANDINGS_KG_CATEGORY_APPORTION)


message("There are ", total_stockeff_unc, "kg of Unclassified in Stockeff")
message("There are ", processed_unc, "kg of Unclassified that are prepped and going into Stockeff")

stopifnot(processed_unc==total_stockeff_unc)
# you did.


# prep stockeff by hand
bsb_sf_prepped<-bsb_stockeff$comm.land.res %>%
  left_join(bsb_stockeff$mkt.res, by=join_by(NESPP4)) %>%
  rename(LANDINGS_KG_CATEGORY_APPORTION = LANDINGS_KG) %>%
  relocate(YEAR, SPECIES_ITIS, STOCK_ABBREV, SEX_TYPE, NESPP4, REGION_ID, BLOCK_ID) %>%
  select(-c(LANDINGS_KG_NOADJ, EXP_RATIO))

processed_all<-bsb_sf_prepped %>%
  summarise(LANDINGS_KG_CATEGORY_APPORTION=sum(LANDINGS_KG_CATEGORY_APPORTION)) %>%
  pull(LANDINGS_KG_CATEGORY_APPORTION)

message("There are ", processed_all, "kg of total landings prepped and going into STOCKEFF")


stopifnot(!anyNA(stockeff_unclass_only$NESPP4))

    
   

  

##########################################################
# Facilitate merge to Stockeff data for 
#out_of_sample_predictions1 and out_of_sample_predictions2 
##########################################################

out_of_sample_predictions_reg<-out_of_sample_predictions_reg %>%
  mutate(SPECIES_ITIS="167687",
         SEX_TYPE="NONE",
         REGION_ID=1,
         BLOCK_ID=as.integer(SEMESTER)
  ) %>%
  filter(YEAR<=2025) %>%
  select(-SEMESTER)

out_of_sample_predictions_reg<-out_of_sample_predictions_reg %>%
  left_join(bsb_stockeff$mkt.res, by=join_by(MARKET_DESC)) %>%
  relocate(YEAR, SPECIES_ITIS, STOCK_ABBREV, SEX_TYPE, NESPP4, REGION_ID, BLOCK_ID)

stopifnot(!anyNA(out_of_sample_predictions_reg$NESPP4))

out_of_sample_predictions_amb<-out_of_sample_predictions_amb %>%
  mutate(SPECIES_ITIS="167687",
         SEX_TYPE="NONE",
         REGION_ID=1,
         BLOCK_ID=as.integer(SEMESTER)
  )  %>%
  filter(YEAR<=2025) %>%
  select(-SEMESTER)

out_of_sample_predictions_amb<-out_of_sample_predictions_amb %>%
  left_join(bsb_stockeff$mkt.res, by=join_by(MARKET_DESC)) %>%
  relocate(YEAR, SPECIES_ITIS, STOCK_ABBREV, SEX_TYPE, NESPP4, REGION_ID, BLOCK_ID)

stopifnot(!anyNA(out_of_sample_predictions_amb$NESPP4))

####################################
# Full Age and length structures ###
####################################
CAA_sum_reg<- LAA_calculation(species_itis = '167687',
                          out_of_sample_predictions = out_of_sample_predictions_reg,
                          fyr = 2013,
                          lyr = 2025,
                          connection = connection,
                          sumflag="sum",
                          plotson=FALSE,
                          plotstub="reg")
CAA_sum_amb<- LAA_calculation(species_itis = '167687',
                          out_of_sample_predictions = out_of_sample_predictions_amb,
                          fyr = 2013,
                          lyr = 2025,
                          connection = connection,
                          sumflag="sum",
                          plotson=FALSE,
                          plotstub="amb")

####################################
# Just the reclassified fish     ###
####################################

CAA_solo_reg<- LAA_calculation(species_itis = '167687',
                          out_of_sample_predictions = out_of_sample_predictions_reg,
                          fyr = 2013,
                          lyr = 2025,
                          connection = connection,
                          sumflag="solo",
                          plotson=FALSE,
                          plotstub="reg")

CAA_solo_amb<- LAA_calculation(species_itis = '167687',
                          out_of_sample_predictions = out_of_sample_predictions_amb,
                          fyr = 2013,
                          lyr = 2025,
                          connection = connection,
                          sumflag="solo",
                          plotson=FALSE,
                          plotstub="amb")

####################################
# pass in just the stockeff Unclassified fish
# and see what the business as usual case thinks about the unclassified fish
####################################

CAA_sum_bau<- LAA_calculation(species_itis = '167687',
                          out_of_sample_predictions = stockeff_unclass_only,
                          fyr = 2013,
                          lyr = 2025,
                          connection = connection,
                          sumflag="sum",
                          plotson=FALSE,
                          plotstub="bau")

# When I pass in the unclassified, this works just fine
test5<-CAA_sum_bau %>%
  group_by(CAA_TYPE) %>%
  summarise(sum=sum(WAA))
test5


# Feed in the stockeff landings.  When I do this, this is completely 'business as usual'
#  I'm sending in a dataframe of "Unclassified" landings that is reclassified to "unclassified"
# it exactly matches what you'd get out if you just didn't do anything (and looked at the "Original"
# however, doing it this way with the sumflag=solo lets me pull just the unclassified lengths

CAA_solo_bau<- LAA_calculation(species_itis = '167687',
                               out_of_sample_predictions = stockeff_unclass_only,
                               fyr = 2013,
                               lyr = 2025,
                               connection = connection,
                               sumflag="solo",
                               plotson=FALSE,
                               plotstub="bau")


CAA_solo_bau2<- LAA_calculation(species_itis = '167687',
                          out_of_sample_predictions = bsb_sf_prepped,
                          fyr = 2013,
                          lyr = 2025,
                          connection = connection,
                          sumflag="solo",
                          plotson=FALSE,
                          plotstub="bau")

CAA_solo_bau2<-CAA_solo_bau2 %>%
  filter(CAA_TYPE=="Apportioned") %>%
  mutate(AGE = case_when(
    AGE<9 ~ AGE,
    AGE>8 ~ 8
  )) %>%
  group_by(SPECIES_ITIS,STOCK_ABBREV,YEAR,AGE,CAA_TYPE) %>% summarise(CAA=sum(CAA),WAA=sum(WAA)) %>%
  select(SPECIES_ITIS, STOCK_ABBREV, YEAR, AGE, CAA, WAA) %>%
  group_by(SPECIES_ITIS, STOCK_ABBREV, YEAR) %>%
  mutate(CAA_sum=sum(CAA, na.rm=TRUE),
            WAA_sum=sum(WAA, na.rm=TRUE)) %>%
  mutate(CAA_prop=CAA/CAA_sum,
         WAA_prop=WAA/WAA_sum) %>%
  ungroup() %>%
  select(-c(CAA_sum, WAA_sum))  %>%
  mutate(CAA_TYPE="StockEff_All")


CAA_solo_bau<-CAA_solo_bau %>%
  filter(CAA_TYPE=="Apportioned") %>%
  mutate(CAA_TYPE="Original") %>% # This looks shady, but I've passed in unclassifieds, so it is correct
  mutate(AGE = case_when(
    AGE<9 ~ AGE,
    AGE>8 ~ 8
  )) %>%
  group_by(SPECIES_ITIS,STOCK_ABBREV,YEAR,AGE,CAA_TYPE) %>% summarise(CAA=sum(CAA),WAA=sum(WAA)) %>%
  select(SPECIES_ITIS, STOCK_ABBREV, YEAR, AGE, CAA, WAA, CAA_TYPE) %>%
  group_by(SPECIES_ITIS, STOCK_ABBREV, YEAR,CAA_TYPE) %>%
  mutate(CAA_orig_sum=sum(CAA, na.rm=TRUE),
            WAA_orig_sum=sum(WAA, na.rm=TRUE)) %>%
  mutate(CAA_prop=CAA/CAA_orig_sum,
         WAA_prop=WAA/WAA_orig_sum) %>%
  ungroup() %>%
  select(-c(CAA_orig_sum, WAA_orig_sum)) 


CAA_solo_amb<-CAA_solo_amb %>%
  filter(CAA_TYPE=="Apportioned") %>%
  mutate(AGE = case_when(
    AGE<9 ~ AGE,
    AGE>8 ~ 8
  )) %>%
  group_by(SPECIES_ITIS,STOCK_ABBREV,YEAR,AGE,CAA_TYPE) %>% summarise(CAA=sum(CAA),WAA=sum(WAA)) %>%
  select(SPECIES_ITIS, STOCK_ABBREV, YEAR, AGE, CAA, WAA, CAA_TYPE) %>%
  group_by(SPECIES_ITIS, STOCK_ABBREV, YEAR,CAA_TYPE) %>%
  mutate(CAA_orig_sum=sum(CAA, na.rm=TRUE),
         WAA_orig_sum=sum(WAA, na.rm=TRUE)) %>%
  mutate(CAA_prop=CAA/CAA_orig_sum,
         WAA_prop=WAA/WAA_orig_sum) %>%
  ungroup() %>%
  select(-c(CAA_orig_sum, WAA_orig_sum)) 





################################PLOTS################################
# Just the landings that were originally unclassified


CAA_comp<-CAA_solo_bau%>%
  rbind(CAA_solo_amb)

########### I want to look at the Apportion from 
CAA_PLOT <- ggplot(data=CAA_comp %>% filter(AGE<=8, AGE>=2),
                   aes(x=AGE,y=CAA_prop,col=CAA_TYPE,fill = CAA_TYPE)) + 
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
    y = "Catch-at-Age proportions of Unclassified (based on numbers)",
    color = NULL, 
    fill = NULL#,
#    title = "Catch at age proportions based on numbers of fish"
  ) +
  facet_grid(YEAR ~ STOCK_ABBREV)  

CAA_PLOT


ggsave(
  filename = here("results",glue("CAA_comparison_UNC_only.pdf")),
  plot = CAA_PLOT,
  width  = 84,
  height = 168,
  units  = "mm",
  device = cairo_pdf
)




CAA_PLOT <- ggplot(data=CAA_comp %>% filter(AGE<=8, AGE>=2),
                   aes(x=AGE,y=WAA_prop,col=CAA_TYPE,fill = CAA_TYPE)) + 
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
    y = "Catch-at-Age proportions of Unclassified (based on numbers)",
    color = NULL, 
    fill = NULL#,
#    title = "Catch at age proportions based on kg landed"
    
  ) +
  facet_grid(YEAR ~ STOCK_ABBREV)
CAA_PLOT

ggsave(
  filename = here("results",glue("WAA_comparison_UNC_only.pdf")),
  plot = CAA_PLOT,
  width  = 84,
  height = 168,
  units  = "mm",
  device = cairo_pdf
)






#Overall re-apportion#

CAA_sum_amb<-CAA_sum_amb %>%
  group_by(SPECIES_ITIS, STOCK_ABBREV, CAA_TYPE, YEAR) %>%
  mutate(CAA_orig_sum=sum(CAA, na.rm=TRUE),
         WAA_orig_sum=sum(WAA, na.rm=TRUE)) %>%
  mutate(CAA_prop=CAA/CAA_orig_sum,
         WAA_prop=WAA/WAA_orig_sum) %>%
  ungroup() %>%
  select(-c(CAA_orig_sum, WAA_orig_sum)) 



CAA_PLOT <- ggplot(data=CAA_sum_amb %>% filter(AGE<=8, AGE>=2),
                   aes(x=AGE,y=WAA_prop,col=CAA_TYPE,fill = CAA_TYPE)) + 
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
    y = "Catch-at-Age proportions (all landings) using weights",
    color = NULL, 
    fill = NULL#,
#    title = "Catch at age proportions based on kg landed"
    
  ) +
  facet_grid(YEAR ~ STOCK_ABBREV)
CAA_PLOT


ggsave(
  filename = here("results",glue("WAA_comparison_all.pdf")),
  plot = CAA_PLOT,
  width  = 84,
  height = 168,
  units  = "mm",
  device = cairo_pdf
)




CAA_PLOT <- ggplot(data=CAA_sum_amb %>% filter(AGE<=8, AGE>=2),
                   aes(x=AGE,y=CAA_prop,col=CAA_TYPE,fill = CAA_TYPE)) + 
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
    y = "Catch-at-Age proportions (all landings) using numbers",
    color = NULL, 
    fill = NULL#,
#    title = "Catch at age proportions based on numbers landed"
    
  ) +
  facet_grid(YEAR ~ STOCK_ABBREV)
CAA_PLOT


ggsave(
  filename = here("results",glue("CAA_comparison_all.pdf")),
  plot = CAA_PLOT,
  width  = 84,
  height = 168,
  units  = "mm",
  device = cairo_pdf
)







# 
# 
# #mass check
# test1<-CAA_sum_reg %>%
#   group_by(CAA_TYPE) %>%
#   summarise(sum=sum(WAA))
# test1
# 
# test2<-CAA_sum_amb %>%
#   group_by(CAA_TYPE) %>%
#   summarise(sum=sum(WAA))
# test2
# 
# 
# test3<-CAA_solo_reg %>%
#   group_by(CAA_TYPE) %>%
#   summarise(sum=sum(WAA))
# test3
# 
# test4<-CAA_solo_amb %>%
#   group_by(CAA_TYPE) %>%
#   summarise(sum=sum(WAA))
# test4
# 
# 
# # note -- there's a differnt amount of weight passed through with the BAU and the other types.
# # It's a difference between CAMS combined with the RF data processing compared to the StockEff processing
# # We were aware of this and not particularly concerned.
# test5<-CAA_bau %>%
#   group_by(CAA_TYPE) %>%
#   summarise(sum=sum(WAA))
# test5
# 
# 
# 
# 
# 
# 
# ##########test code
# 
# species_itis = '167687'
# out_of_sample_predictions = out_of_sample_predictions_reg
# fyr = 2013
# lyr = 2024
# connection = connection
# sumflag="solo"
# plotstub="reg"
# 
# 
# bsb_stockeff<-get_intermediate_stockeff(species_itis=species_itis,
#                                         fyr=fyr,
#                                         lyr=lyr,
#                                         connection=connection)
# 
# #unpack
# comm.land.length.age.res<-bsb_stockeff$comm.land.length.age.res
# mkt.res <- bsb_stockeff$mkt.res
# comm.land.res<-bsb_stockeff$comm.land.res
# 
# 
# nrow(out_of_sample_predictions)
# table(out_of_sample_predictions$MARKET_DESC)
# table(out_of_sample_predictions$MARKET_DESC, out_of_sample_predictions$YEAR)
# table(out_of_sample_predictions$MARKET_DESC, out_of_sample_predictions$BLOCK_ID)
# table(out_of_sample_predictions$MARKET_DESC, out_of_sample_predictions$STOCK_ABBREV)
# 
# out_of_sample_predictions <- out_of_sample_predictions %>%
#   mutate(has_rf_pred = 1)
# nrow(out_of_sample_predictions)
# 
# ## Combine the stockeff files and apportionment file
# 
# comm.land.length.age2 <- comm.land.res  %>%
#   left_join(comm.land.length.age.res, by=join_by(SPECIES_ITIS, NESPP4, YEAR, SEX_TYPE, STOCK_ABBREV, REGION_ID, BLOCK_ID)) %>%
#   left_join(mkt.res, by=join_by(NESPP4))
# nrow(comm.land.length.age2)
# 
# 
# 
# comm.land.length.age2$merge_marker=1
# comm.land.length.age2<-comm.land.length.age2 %>%
#   full_join(out_of_sample_predictions, by=join_by(SPECIES_ITIS, MARKET_DESC, NESPP4, YEAR, SEX_TYPE, STOCK_ABBREV, REGION_ID, BLOCK_ID))
# nrow(comm.land.length.age2)
# 
# 
# table(comm.land.length.age2$has_rf_pred, comm.land.length.age2$merge_marker)

dbDisconnect(connection)

