###############################################################################
# Purpose: 	Make plots of prices by market category and "combined market category" for 
# managed fish stocks.

# Inputs:
# - all_marketcategory_landings_
#  - market_cat_aggregations 

# Outputs:
#  - histograms of prices
#  - histograms of prices, aggregated by combined market category

###############################################################################  



library("glue")
library("tidyverse")
library("forcats")
library("here")

here::i_am("R_code/analysis/market_category_price_plots.R")


#traverse over to the DataPull repository
mega_dir<-dirname(here::here())
data_pull_dir<-file.path(mega_dir,"READ-SSB-Lee-BSB-DataPull")

year_start<-2020
year_end<-2024

vintage_string<-"2025-07-10"
options(scipen=999)

landings<-readRDS(file=file.path(data_pull_dir,"data_folder","raw","commercial", glue("all_marketcategory_landings_{vintage_string}.Rds")))

#There is no point in looking at scallop, surfclam, or ocean quahog.

landings<-landings %>%
  mutate(price=value/lndlb) %>%
    filter(!itis_tsn %in% c("079718", "080944","081343")) %>%
  mutate(species_factor=factor(itis_sci_name))


# Loop over the levels of species factor

unique_itis <- unique(landings$itis_tsn)
unique_itis <- unique_itis[!is.na(unique_itis)]


for (tsn in unique_itis) {

working_dataset<-landings %>%
  filter(itis_tsn==tsn) %>%
  mutate(market_desc_factor=factor(market_desc))


price_95th_percentile <- working_dataset %>%
     summarise(price_95th = quantile(price, 0.95, na.rm = TRUE)) %>%
     pull(price_95th)


working_dataset<-working_dataset %>%
  filter(price<=price_95th_percentile) %>%
  filter(price>0)
  

working_dataset <- working_dataset %>%
  # First calculate the mean price for each market factor
  group_by(market_desc_factor) %>%
  mutate(weighted_mean_price = weighted.mean(price, w = lndlb, na.rm = TRUE)) %>%
  ungroup() %>%
  # Reorder the factor levels based on descending mean price
  mutate(market_desc_factor_ordered = fct_reorder(market_desc_factor, 
                                                  weighted_mean_price, 
                                                  .desc = TRUE)) %>%
  # Remove the temporary weighted_mean_price column
  select(-weighted_mean_price)

species_name <- working_dataset %>%
  slice(1) %>%
  pull(itis_sci_name)


if (nrow(working_dataset)>=1) {
  
wp<-ggplot(working_dataset, aes(x = price)) + 
  geom_histogram(aes(weight = lndlb), boundary = 0) + 
   labs(, x = glue("Nominal Price of {species_name},{year_start} to {year_end} combined"), y = "Pounds") +
  #    theme_minimal() + 
  facet_wrap(vars(market_desc_factor_ordered), ncol=1, scales="free_y")

ggsave(here("images","descriptive",glue("price_hist_{species_name}.png")), 
       plot = wp,
       width = 12, 
       height = 8, 
       dpi = 300,
       units = "in")
  }

}

########################Prices by aggregate market category, eventually this completely replaces the previous code. All I've done 
# is merge in the category aggregations and change the definition of market_desc_factor to be based on category combined 


# read in market_cat keyfile aggregations and ensure it is unique
market_cat_aggregations<-readRDS(file=here("data_folder","main","commercial",glue("market_cat_aggregations_{vintage_string}.Rds")))

market_cat_aggregations<-market_cat_aggregations %>%
  select(itis_tsn,dlr_mkt,category_combined)%>%
  group_by(itis_tsn,dlr_mkt,category_combined) %>%
  slice(1) %>%
  ungroup()

# Repeat after aggregating

landings<-landings %>%
  left_join(market_cat_aggregations, by=join_by(itis_tsn==itis_tsn, dlr_mkt==dlr_mkt))


for (tsn in unique_itis) {
  
  working_dataset<-landings %>%
    filter(itis_tsn==tsn) %>%
    mutate(market_desc_factor=factor(category_combined))
  
  
  price_95th_percentile <- working_dataset %>%
    summarise(price_95th = quantile(price, 0.95, na.rm = TRUE)) %>%
    pull(price_95th)
  
  
  working_dataset<-working_dataset %>%
    filter(price<=price_95th_percentile) %>%
    filter(price>0)
  
  
  working_dataset <- working_dataset %>%
    # First calculate the mean price for each market factor
    group_by(market_desc_factor) %>%
    mutate(weighted_mean_price = weighted.mean(price, w = lndlb, na.rm = TRUE)) %>%
    ungroup() %>%
    # Reorder the factor levels based on descending mean price
    mutate(market_desc_factor_ordered = fct_reorder(market_desc_factor, 
                                                    weighted_mean_price, 
                                                    .desc = TRUE)) %>%
    # Remove the temporary weighted_mean_price column
    select(-weighted_mean_price)
  
  species_name <- working_dataset %>%
    slice(1) %>%
    pull(itis_sci_name)
  
  
  working_dataset <- working_dataset %>%
    mutate(lndlb=lndlb/1000)
  
  if (nrow(working_dataset)>=1) {
    
    wp<-ggplot(working_dataset, aes(x = price)) + 
      geom_histogram(aes(weight = lndlb), boundary = 0, binwidth=0.10) + 
      labs(, x = glue("Nominal Price of {species_name},{year_start} to {year_end} combined"), y = "Pounds (000s)") +
      #    theme_minimal() + 
      facet_wrap(vars(market_desc_factor_ordered), ncol=1, scales="free_y")
    
    ggsave(here("images","descriptive",glue("price_hist_AGG_{species_name}.png")), 
           plot = wp,
           width = 12, 
           height = 8, 
           dpi = 300,
           units = "in")
  }
  
}



