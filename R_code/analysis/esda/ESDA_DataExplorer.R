######  
#  **********************************************************************
#  * Purpose: 	Quality Assurance and checks on data for machine learning models.
#  * Inputs:
#    - BSB_estimation_dataset (from data_prep_ml.Rmd)
#    - BSB_unclassified_dataset (from data_prep_ml.Rmd)
#
#
# Outputs:
  
library("here")
# load tidyverse and related
library("tidyverse")
library("scales")
library("glue")
library("haven")


# load utilities
library("knitr")
library("kableExtra")
library("viridis")

# Load data exploration
library("skimr")
library("DataExplorer")


#always load conflicted
library("conflicted")

#deal with conflicts
conflicts_prefer(dplyr::filter())
conflicts_prefer(dplyr::lag())
conflicts_prefer(purrr::discard())
conflicts_prefer(dplyr::group_rows())
conflicts_prefer(yardstick::spec())
conflicts_prefer(recipes::fixed())
conflicts_prefer(recipes::step())
conflicts_prefer(viridis::viridis_pal())

here::i_am("R_code/analysis/esda/ESDA_DataExplorer.R")

#traverse over to the DataPull repository
mega_dir<-dirname(here::here())
data_pull_dir<-file.path(mega_dir,"READ-SSB-Lee-BSB-DataPull")

lbs_per_mt<-2204.62
#############################################################################
my_images<-here("images")
descriptive_images<-here("images","descriptive")
exploratory_images<-here("images","exploratory")
vintage_string<-list.files(here("data_folder","main","commercial"), pattern=glob2rx("landings_cleaned_*.dta"))
vintage_string<-gsub("landings_cleaned_","",vintage_string)
vintage_string<-gsub(".dta","",vintage_string)
vintage_string<-max(vintage_string)
#############################################################################

#############################################################################
# Data read in #
#############################################################################
cleaned_landings<-read_dta(here("data_folder","main","commercial", paste0("landings_cleaned_",vintage_string,".dta")))
#cams_gears<-haven::read_dta(here("data_folder","main","commercial", paste0("cams_gears_",vintage_string,".dta")))
camsid_specific_stats<-read_dta(here("data_folder","main","commercial", paste0("camsid_specific_cleaned_",vintage_string,".dta")))
daily_ma<-read_dta(here("data_folder","main","commercial", paste0("daily_ma_",vintage_string,".dta")))
state_ma<-read_dta(here("data_folder","main","commercial", paste0("state_ma_",vintage_string,".dta")))
stockarea_ma<-read_dta(here("data_folder","main","commercial", paste0("stockarea_ma_",vintage_string,".dta")))
dlrid_historical<-read_dta(here("data_folder","main","commercial", paste0("dlrid_historical_stats_",vintage_string,".dta")))
dlrid_lag<-read_dta(here("data_folder","main","commercial", paste0("dlrid_lag_stats_",vintage_string,".dta")))

gear_ma<-read_dta(here("data_folder","main","commercial", paste0("gear_ma_",vintage_string,".dta")))

#############################################################################
# END  Data read in #
#############################################################################


#############################################################################
# Data Processing from data_prep_ml #
#############################################################################

# Initial data, tidied up a little.
start_data<-cleaned_landings %>%
  group_by(stockarea,year, camsid) %>%
  summarise(lndlb=sum(lndlb)) %>%
  ungroup() %>%
  group_by(stockarea,year) %>%
  summarise(lnd_mt=sum(lndlb/2204),
            trips=n()) %>%
  mutate(lbs_per_trip=lnd_mt*2204/trips) %>%
  filter(year>=2015) %>%
  mutate(year=forcats::as_factor(year),
         stockarea=haven::as_factor(stockarea, levels="label")) 




# this is the "collapse" statement in stata. Not sure but I think some of the things in the group_by() might need to be a "first" in the summarise
cleaned_landings<-cleaned_landings %>%
  group_by(camsid,hullid, mygear, record_sail, record_land, dlr_date, dlrid, state, grade_desc, market_desc, dateq, year, month, stockarea, status) %>%
  summarise(value=sum(value),
            valueR_CPI=sum(valueR_CPI),
            lndlb=sum(lndlb),
            livlb=sum(livlb),
            weighting=sum(weighting)
  ) %>%
  ungroup()



# South - Delaware, Florida*, Maryland, North Carolina, South Carolina*, Virginia
# North - Connecticut, Maine*, Massachusetts, New Hampshire*, New Jersey, New York, Pennsylvania*, Rhode Island, Vermont*
# * have no landings or limited landings are are dropped later.

cleaned_landings<-cleaned_landings %>% 
  mutate(region=case_when(
    state %in% c(9,23,25,33,36,42,44,50) ~ "North",
    state %in% c(10, 12,24,34, 37,45,51)  ~ "South",
    .default = "Unknown"  )
  )


# merge in camsid (trip) level statistics
cleaned_landings<-cleaned_landings %>%
  left_join(camsid_specific_stats, by=join_by(camsid==camsid, dlr_date==dlr_date), relationship="many-to-one")

# merge in daily level statistics
cleaned_landings<-cleaned_landings %>%
  left_join(daily_ma, by=join_by(dlr_date==dlr_date), relationship="many-to-one")

# merge in state-day statistics
cleaned_landings<-cleaned_landings %>%
  left_join(state_ma, by=join_by(state==state, dlr_date==dlr_date), relationship="many-to-one")

# merge in stockarea-day statistics
cleaned_landings<-cleaned_landings %>%
  left_join(stockarea_ma, by=join_by(stockarea==stockarea, dlr_date==dlr_date), relationship="many-to-one")


# merge in gear-day statistics
cleaned_landings<-cleaned_landings %>%
  left_join(gear_ma, by=join_by(mygear==mygear, dlr_date==dlr_date), relationship="many-to-one")


# merge in dlrid historical statistics
cleaned_landings<-cleaned_landings %>%
  left_join(dlrid_historical, by=join_by(dlrid==dlrid), relationship="many-to-one")


# merge in dlrid lag statistics
cleaned_landings<-cleaned_landings %>%
  left_join(dlrid_lag, by=join_by(dlrid==dlrid,year==year), relationship="many-to-one")

# NAs for Transaction count and lndlb can be replaced by zero.
# Not sure what to do with Shares of landings of Fraction of transactions columns 
cleaned_landings<-cleaned_landings %>%
  mutate(TransactionCountJumbo=replace_na(TransactionCountJumbo),
         TransactionCountLarge=replace_na(TransactionCountLarge),
         TransactionCountMedium=replace_na(TransactionCountMedium),
         TransactionCountSmall=replace_na(TransactionCountSmall),
         TransactionCountUnclassified=replace_na(TransactionCountUnclassified)
  )

cleaned_landings<-cleaned_landings %>%
  mutate(DealerHLbsPurchasedJumbo=replace_na(DealerHLbsPurchasedJumbo),
         DealerHLbsPurchasedLarge=replace_na(DealerHLbsPurchasedLarge),
         DealerHLbsPurchasedMedium=replace_na(DealerHLbsPurchasedMedium),
         DealerHLbsPurchasedSmall=replace_na(DealerHLbsPurchasedSmall),
         DealerHLbsPurchasedUnclassified=replace_na(DealerHLbsPurchasedUnclassified)
  )





# compute prices and real prices
cleaned_landings<-cleaned_landings %>%
  mutate(price=value/lndlb,
         priceR_CPI=valueR_CPI/lndlb,
         month=lubridate::month(dlr_date))

# trip level BSB landings
cleaned_landings<-cleaned_landings %>%
  group_by(camsid) %>%
  mutate(trip_level_BSB=sum(lndlb)) %>%
  ungroup()

# Encode semester
cleaned_landings<-cleaned_landings %>%
  mutate(semester=case_when(
    month<=6  ~ 1,
    month>=7  ~ 2,
    .default=0)
  ) 
#Use the variable labels to convert to factors 
cleaned_landings<-cleaned_landings %>%
  mutate(market_desc=haven::as_factor(market_desc, levels="label"),
         mygear=haven::as_factor(mygear, levels="label"),
         state=haven::as_factor(state, levels="label"),
         grade_desc=haven::as_factor(grade_desc, levels="label"),
         stockarea=haven::as_factor(stockarea, levels="label")
  )

#Factor the cams status column
cleaned_landings<-cleaned_landings %>%
  mutate(status=factor(status,levels=c("MATCH","DLR_ORPHAN_SPECIES","DLR_ORPHAN_TRIP","PZERO"))
  )

cleaned_landings<-cleaned_landings %>%
  mutate(shore=as.numeric(hullid=="FROM_SHORE"),
         nofederal=as.numeric(str_detect(camsid, "^000000*"))
  )


combined_dataset<-cleaned_landings %>%
  mutate(keep = case_when(year<2015~ 0,
                          year>2024~ 0,
                          price<0.15 ~ 0,
                          price>15 ~ 0,
                          is.na(price) ~ 0,
                          state =="CN"  ~ 0,
                          state =="FL"  ~ 0, 
                          state =="PA"  ~ 0,
                          state =="SC"  ~ 0,
                          .default=1)
  )

# deal with factors
combined_dataset<-combined_dataset %>%
  filter(keep==1 )%>%
  mutate(market_desc=forcats::fct_relevel(market_desc,c("Jumbo","Large","Medium","Small","Unclassified")) ) %>%
  mutate(year=forcats::as_factor(year)) %>%
  mutate(month=forcats::as_factor(month)) %>%
  mutate(semester=forcats::as_factor(semester)) %>%
  mutate(dlrid=forcats::as_factor(dlrid)) %>%
  mutate(market_desc=fct_drop(market_desc),
         year=fct_drop(year),
         state=fct_drop(state)) %>%
  select(-keep)#%>%
#  mutate(weighting = frequency_weights(weighting)) the frequency weighting causes problems with some esda commands


##########################################################################
# End Data Processing from data_prep_ml #
#############################################################################

# Skim 
skim_results<-skim(combined_dataset)



DateTime<-format(Sys.time(), "%Y_%m_%d_%H_%M_%S%Z")


configs<-configure_report(
  add_plot_scatterplot=FALSE,
  add_plot_density = TRUE,
    plot_qq_args = list(sampled_rows = 2000L),
  )


# combined_dataset %>%
#   DataExplorer::create_report(
#     output_file = here("R_code","analysis","esda",glue("Report_{DateTime}")),
#     report_title = "EDA Report - Combined ML Dataset",
#     y = "market_desc",
#     config=configs
#   )
combined_backup<-combined_dataset
combined_dataset<-combined_backup

combined_dataset<-combined_dataset %>%
  filter(state!="ME") %>%
  filter(market_desc !="Unclassified")

combined_dataset<-combined_dataset %>%
  mutate(state=fct_relevel(state, "NC","VA","MD","DE","NJ","NY","CT","RI","MA"),
         time_period=case_when(
           year %in% c(2015,2016,2017,2018,2019,2020) ~ 1,
           year %in% c(2021,2022,2023,2024) ~ 2
         )
         
  )

# Boxplot of estimation data
# unweighted
ggplot(combined_dataset, aes(y=priceR_CPI, x=market_desc, fill=state)) + 
  geom_boxplot(outliers=FALSE) +
  ggtitle("Unweighted Prices")
ggsave(here("images","exploratory",glue("prices_by_market.png")), plot=last_plot())

# weighted by landed pounds
ggplot(combined_dataset, aes(y=priceR_CPI, x=market_desc, fill=state, weight=lndlb)) + 
  geom_boxplot(outliers=FALSE)+
  ggtitle("Weighted Prices")

ggsave(here("images","exploratory",glue("Wprices_by_market.png")), plot=last_plot())


ggplot(combined_dataset , aes(y=priceR_CPI, x=market_desc, fill=state, weight=lndlb)) + 
  geom_boxplot(outliers=FALSE) +
  facet_wrap(vars(time_period)) + 
  ggtitle("Weighted Prices, 2015-2020 and 2021-2024")
ggsave(here("images","exploratory",glue("Wprices_by_market_recent.png")), plot=last_plot())





#facet wrapped by year.
ggplot(combined_dataset %>% filter(time_period==1), aes(y=priceR_CPI, x=market_desc, fill=state, weight=lndlb)) + 
  geom_boxplot(outliers=FALSE)+
  facet_wrap(vars(year))+
  ggtitle("Weighted Prices")
ggsave(here("images","exploratory",glue("FW1_Wprices_by_market.png")), plot=last_plot())

ggplot(combined_dataset %>% filter(time_period==2), aes(y=priceR_CPI, x=market_desc, fill=state, weight=lndlb)) + 
  geom_boxplot(outliers=FALSE)+
  facet_wrap(vars(year))+
  ggtitle("Weighted Prices")
ggsave(here("images","exploratory",glue("FW2_Wprices_by_market.png")), plot=last_plot())




#facet wrapped by year.
ggplot(combined_dataset %>% filter(time_period==1), aes(y=priceR_CPI, x=year, fill=market_desc, weight=lndlb)) + 
  geom_boxplot(outliers=FALSE)+
  facet_wrap(vars(state))+
  ggtitle("Weighted Prices")
ggsave(here("images","exploratory",glue("FW1_Wprices_by_state.png")), plot=last_plot())

ggplot(combined_dataset %>% filter(time_period==2), aes(y=priceR_CPI, x=year, fill=market_desc, weight=lndlb)) + 
  geom_boxplot(outliers=FALSE)+
  facet_wrap(vars(state))+
  ggtitle("Weighted Prices")
ggsave(here("images","exploratory",glue("FW2_Wprices_by_state.png")), plot=last_plot())






# Boxplot of validation data -- grouped a different way
# unweighted
ggplot(combined_dataset, aes(y=priceR_CPI, fill=market_desc, x=state)) + 
  geom_boxplot()+
  ggtitle(" Prices")
ggsave(here("images","exploratory",glue("prices_by_state.png")), plot=last_plot())



ggplot(combined_dataset, aes(y=priceR_CPI, fill=market_desc, x=state, weight=lndlb)) + 
  geom_boxplot()+
  ggtitle("Weighted Prices")
ggsave(here("images","exploratory",glue("prices_by_state.png")), plot=last_plot())
# weighted by landed pounds



# Boxplot of validation data -- grouped a different way
# unweighted
ggplot(combined_dataset, aes(y=priceR_CPI, fill=market_desc, x=state)) + 
  geom_boxplot(outliers=FALSE)+
  facet_wrap(vars(time_period)) + 
  ggtitle(" Prices")
ggsave(here("images","exploratory",glue("FWprices_by_state.png")), plot=last_plot())



ggplot(combined_dataset, aes(y=priceR_CPI, fill=market_desc, x=state, weight=lndlb)) + 
  geom_boxplot(outliers=FALSE)+
  facet_wrap(vars(time_period)) + 
    ggtitle("Weighted Prices")
ggsave(here("images","exploratory",glue("FW_Wprices_by_state.png")), plot=last_plot())



# Large and Medium Kernel density overlays, facet 
ggplot(combined_dataset %>% filter(market_desc %in%c("Jumbo","Large","Medium")) %>% filter(region=="South"), aes(priceR_CPI, fill = market_desc, color=market_desc,weight=lndlb)) +
  geom_density(alpha = 0.1, aes(y = after_stat(count))) +
  xlim(0,10) + 
  facet_wrap(~ time_period + state, scales = "free_y", nrow=2)

ggsave(here("images","exploratory",glue("FGS_Kdensity_by_state.png")), plot=last_plot())


ggplot(combined_dataset %>% filter(market_desc %in%c("Jumbo","Large","Medium")) %>% filter(region=="North"), aes(priceR_CPI, fill = market_desc, color=market_desc,weight=lndlb)) +
  geom_density(alpha = 0.1, aes(y = after_stat(count))) +
  xlim(0,10) + 
  facet_wrap(~ time_period + state, scales = "free_y", nrow=2)

ggsave(here("images","exploratory",glue("FGN_Kdensity_by_state.png")), plot=last_plot())


###########################################
				  
																		  

# there's a handful of outlier lndlbs.    

# The dealer idiosycracies are with the Small and Unclassified categories.
# Landings of small tend to be reported by dealers who did more small in the 2010-2014 time period
# Same story for Unclassifieds, but magnified.


# 
# combined_dataset %>% filter(lndlb<=1000) %>%
#   DataExplorer::create_report(
#     output_file = here("R_code","analysis","esda",glue("Report_1k_{DateTime}")),
#     report_title = "EDA Report - Combined ML Dataset lndlb<=1000",
#     y = "market_desc",
#     config=configs
#   )
# 

# Correlation of the Lag Shares

corrs<-combined_dataset %>%
  group_by(dlrid,year) %>%
  slice(1) %>%
  ungroup() %>%
  select(starts_with("LagSharePounds"))

cor(corrs)
