# Code to make the graphics 


library("here")

# load tidyverse and related
library("tidyverse")
library("haven")
library("scales")
library("glue")

library("viridis")
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

###############################################################################
# Directories 
###############################################################################
here::i_am("writing/figure1.R")



my_images<-here("images")
descriptive_images<-here("images","descriptive")
exploratory_images<-here("images","exploratory")

dataset_name<-list.files(here("data_folder","main","commercial"), pattern=glob2rx("BSB_original_combined_dataset*.Rds"))
dataset_name<-max(dataset_name)
vintage_string<-gsub("BSB_original_combined_dataset","",dataset_name)
vintage_string<-gsub(".Rds","",vintage_string)

combined_dataset<-read_rds(here("data_folder","main","commercial", dataset_name))

combined_dataset<-combined_dataset %>%
  filter(mark_in==1 | market_desc=="Unclassified")

# To upper case, rename as SMALL_COMB, and relevel to re-order
combined_dataset<-combined_dataset %>%
  mutate(market_desc=str_to_upper(market_desc))%>%
  mutate(market_desc = if_else(market_desc == "SMALL", 
                               "SMALL.COMB", 
                               market_desc))
combined_dataset<-combined_dataset %>%
  mutate(market_desc=forcats::fct_relevel(market_desc,c("UNCLASSIFIED", "SMALL_COMB", "MEDIUM", "LARGE", "JUMBO")))



# Plot. 
p<-ggplot(combined_dataset %>% filter(priceR_CPI>=0 & priceR_CPI<=10), aes(x=priceR_CPI, weight=lndlb, after_stat(density)))+ 
  geom_histogram(binwidth=0.25) + 
  facet_wrap(~ market_desc,ncol = 1, strip.position="right") +
  labs(x = "Real Price") 

# save to png and Rds       
# decent, but i'll have to fiddle with options a little more to get the sizing correct.
ggsave(here("images","exploratory","wprice_histograms_vertical_NR.png"), plot=p)
#write_rds(p, file=here("images","exploratory","wprice_histograms_vertical_NR.Rds"))

