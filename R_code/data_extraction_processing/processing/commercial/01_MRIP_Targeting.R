
# This is a code to construct survey-weighted totals in R.  I've done the data prep in stata, which is far from ideal.


library("here")
library("haven")
library("survey")
library("srvyr")
here::i_am("R_code/01_MRIP_Targeting.R")
options(scipen=999)

#Handle single PSUs
options(survey.adjust.domain.lonely=TRUE)
options(survey.lonely.psu="adjust")




catch_dataset<-read_dta(here("data_folder","raw","catch_dataset.dta"))
trips_dataset<-read_dta(here("data_folder","raw","trips_dataset.dta"))

trips_dataset<-trips_dataset %>%
  mutate(mode=ifelse(mode_fx==4,"FH",ifelse(mode_fx==5,"FH","PR"))
)


#srvyr data prep
tidy_catch_in<-catch_dataset %>%
  as_survey_design(id=psu_id, weights=wp_int, strata=strat_id, fpc=NULL)


catch_totals_filtered<-tidy_catch_in %>%
  group_by(year, month,common_dom ) %>%
  dplyr::filter(common_dom=="BSB") %>%
  summarise(tot_cat=survey_total(tot_cat),
            claim=survey_total(claim),
            harvest=survey_total(harvest),
            release=survey_total(release)
  )

catch_totals_filtered_stco<-tidy_catch_in %>%
  group_by(year, month,stco,common_dom ) %>%
  dplyr::filter(common_dom=="BSB") %>%
  summarise(tot_cat=survey_total(tot_cat),
            claim=survey_total(claim),
            harvest=survey_total(harvest),
            release=survey_total(release)
  )



# Targeting 
# srvyr data prep



tidy_trips_in<-trips_dataset %>%
  as_survey_design(id=psu_id, weights=wp_int, strata=strat_id, fpc=NULL)


target_totals_by_mode<-tidy_trips_in %>%
  dplyr::filter(dom_id==1) %>%
  group_by(year, month,mode ) %>%
  summarise(dtrip=survey_total(dtrip)
  )

target_totals<-tidy_trips_in %>%
  dplyr::filter(dom_id==1) %>%
  group_by(year, month ) %>%
  summarise(dtrip=survey_total(dtrip)
  )


target_totals_stco<-tidy_trips_in %>%
  dplyr::filter(dom_id==1) %>%
  group_by(year, month,stco ) %>%
  summarise(dtrip=survey_total(dtrip)
)

