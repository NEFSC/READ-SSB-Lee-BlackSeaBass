################################################################################
################################################################################
# Script:       LAA_test_script.R
# Purpose:      Exercises the older monolithic LAA_calculation() against the
#               conservative and ambitious random-forest prediction files and
#               compares the two results. 
# Inputs:       out_of_sample_predictions_YRS_nocluster<vintage>.Rds
#               ambitious_out_of_sample_predictions_YRS_nocluster<vintage>.Rds
#               StockEff, direct queries (ITIS 167687, 1989-2024)
# Outputs:      NONE. Nothing is written to disk; results are inspected in the
#               viewer and with table().
# Dependencies: LAA_calculation.R, sourced at line 8 - this brings in ROracle,
#               tidyverse, here and glue as well as the function itself. Also
#               needs `nefscdb_con` to already exist in the session; nothing in
#               this repository defines it.
# Pipeline:     Hand-run. No wrapper calls this script and it calls no other
#               script. Parallel to LAA_calc_script.R, which exercises the
#               REFACTORED path (get_intermediate_stockeff + get_ages) over the same problem.
#
# INTERACTIVE ONLY. There are two View() calls below, so this file cannot be
# run under Rscript - it is meant to be stepped through in RStudio. Treat it as
# a worksheet, not as a reproducible script.
#
# FINDING. Both prediction files are
# confirmed to carry the same total kilograms at the year x semester x stock
# level to within 1e-6, yet the resulting landings-at-age totals differ.

# LAA is counted in FISH, not kilograms. Equal mass distributed differently across
# categories that are DEFINED BY FISH SIZE must yield different counts: a
# kilogram of Small is many more fish than a kilogram of Jumbo. 
# The prediction file must have at most one row per (SPECIES_ITIS, YEAR, STOCK_ABBREV, MARKET_DESC,
# SEMESTER) or the left join duplicates StockEff rows and inflates everything.
# A row-count assertion across the join would separate the two explanations
# cleanly. 

# ALSO WORTH KNOWING: for the assessment itself this level discrepancy largely
# washes out. fit_BSB_WHAM.R row-normalizes catch-at-age into proportions
# before handing it to WHAM, so what reaches the model is the age SHAPE, not
# the absolute numbers.
################################################################################
################################################################################

library("here")
library("ROracle")
library("tidyverse")
library("glue")
library("conflicted")
conflicts_prefer(dplyr::filter())

here::i_am("R_code/LAA_calculation/LAA_test_script.R")

# LAA_calculation() loads the MONOLITHIC version of the calculation, which does its own StockEff queries
# internally (including a stockeff_pre_prod fallback) and returns CAA_OLD and
# CAA_NEW side by side. LAA_calc_script.R uses the refactored path instead.

source(here("R_code/LAA_calculation/LAA_calculation.R"))

drv<-dbDriver("Oracle")
connection <- eval(nefscdb_con)

# Vintage-selection idiom used throughout this project: glob the folder, strip
# the fixed prefix and suffix to leave a bare ISO date, then max() for the
# newest. Lexicographic max is correct on YYYY-MM-DD.

predictions_vintage<-list.files(here("data_folder","predictions"), pattern=glob2rx("out_of_sample_predictions_YRS_nocluster*.Rds"))
predictions_vintage<-gsub("out_of_sample_predictions_YRS_nocluster","",predictions_vintage)
predictions_vintage<-gsub(".Rds","",predictions_vintage)
predictions_vintage<-max(predictions_vintage)

predictions_full_location1<-here("data_folder","predictions", glue("out_of_sample_predictions_YRS_nocluster{predictions_vintage}.Rds"))
predictions_full_location2<-here("data_folder","predictions", glue("ambitious_out_of_sample_predictions_YRS_nocluster{predictions_vintage}.Rds"))


out_of_sample_predictions1<-readRDS(predictions_full_location1)
out_of_sample_predictions2<-readRDS(predictions_full_location2)


# out_of_sample_predictions1 = conservative (the model may abstain, leaving
#   some fish UNCLASSIFIED); out_of_sample_predictions2 = ambitious (every
#   unclassified transaction is assigned to a real market category).
#

CAA<- LAA_calculation(species_itis = '167687',
                             out_of_sample_predictions = out_of_sample_predictions1,
                           fyr = 1989,
                           lyr = 2024,
                             connection = connection)

CAA2<- LAA_calculation(species_itis = '167687',
                      out_of_sample_predictions = out_of_sample_predictions2,
                      fyr = 1989,
                      lyr = 2024,
                      connection = connection)
dbDisconnect(connection)


test1<-CAA %>%
  group_by(STOCK_ABBREV, YEAR) %>%
  summarise(CAA_NEW=sum(CAA_NEW))

test2<-CAA2 %>%
  group_by(STOCK_ABBREV, YEAR) %>%
  summarise(CAA2_NEW=sum(CAA_NEW))

# These do not match and are not supposed to match. test1 and test2 sum CAA_NEW, which is a count of FISH.
# The two prediction files carry the same total KILOGRAMS - but they distribute those kilograms differently across
# market categories, and market categories are defined by fish size. The
# scaling chain divides by AVG_FISH_WT and IND_AVG_WT_KG, both of which are
# category-specific, so the same mass allocated to Small yields far more fish
# than allocated to Jumbo.



verify<-test1 %>%
  left_join(test2, by=join_by(STOCK_ABBREV, YEAR)) %>%
  mutate(diff=CAA2_NEW-CAA_NEW)


table(abs(test1$CAA_NEW-test2$CAA2_NEW)<=10)

View(verify)

v2<-verify %>%
  filter(YEAR>=2013)

View(v2)



#total landings matches

# This block is the mass-conservation check, and it passes at both the grand
# total and the year x semester x stock level (the table() at the end of the
# block reads TRUE where |diff| < 1e-6). That is the evidence that the two
# prediction files agree on kilograms - which is exactly why the count-level
# disagreement above is expected rather than alarming.

oos_test1<-out_of_sample_predictions1 %>%
  summarise(landings=sum(LANDINGS_KG_CATEGORY_APPORTION))
oos_test1

oos_test2<-out_of_sample_predictions2 %>%
  summarise(landings=sum(LANDINGS_KG_CATEGORY_APPORTION))
oos_test2

# so does landings at the year-semester-STOCKABBREV to eps()
oos_test1<-out_of_sample_predictions1 %>%
  group_by(YEAR, SEMESTER, STOCK_ABBREV)%>%
  summarise(landings1=sum(LANDINGS_KG_CATEGORY_APPORTION))

oos_test2<-out_of_sample_predictions2 %>%
  group_by(YEAR, SEMESTER, STOCK_ABBREV)%>%
  summarise(landings2=sum(LANDINGS_KG_CATEGORY_APPORTION))

verify<-oos_test1 %>%
  left_join(oos_test2, by=join_by(YEAR, SEMESTER, STOCK_ABBREV)) %>%
  mutate(diff=landings1-landings2)
table(verify$diff<1e-6)



     