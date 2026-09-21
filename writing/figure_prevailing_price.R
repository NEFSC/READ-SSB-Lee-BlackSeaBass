# Code to make the graphics in Figure 1
# Stacked Length Histogram by Aggregated Market Category
# Stacked price per kg histogram by same aggregations

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
here::i_am("writing/figure_prevailing_price.R")

lbs_per_kg<-2.20462

my_images<-here("images")
descriptive_images<-here("images","descriptive")
exploratory_images<-here("images","exploratory")

dataset_name<-list.files(here("data_folder","main","commercial"), pattern=glob2rx("BSB_original_combined_dataset*.Rds"))
dataset_name<-max(dataset_name)
vintage_string<-gsub("BSB_original_combined_dataset","",dataset_name)
vintage_string<-gsub(".Rds","",vintage_string)


grand_ma_prices<-readRDS(
  file = here("data_folder", "main", "commercial",
              glue("grand_moving_average_prices_{vintage_string}.Rds"))
)

grand_ma_prices<-grand_ma_prices %>%
  filter(state %in% c("CT","DE", "MA", "MD", "NC", "NJ", "NY", "RI", "VA"))

grand_ma_prices<-grand_ma_prices %>%
  pivot_longer(cols=c(JumboMA14price, LargeMA14price, MediumMA14price, SmallMA14price), names_to="market_desc", values_to="price")

grand_ma_prices<-grand_ma_prices %>%
  mutate(market_desc=str_replace(market_desc,"MA14price","")) %>%
  mutate(price=price*lbs_per_kg) %>%
  filter(market_desc !="Small")
  

# --- 3. Colour palette — four classes ---
class_colours <- c(
  "Jumbo"  = "#1B6CA8",   # deep blue
  "Large"  = "#E05C2A",   # burnt orange
  "Medium" = "#2E8B57",   # sea green
  "Small"  = "#7B3F9E"    # purple
)




# price.mktcomb <- ggplot(
#   grand_ma_prices %>% filter(dlr_date>=ymd("2024-01-01") , dlr_date<=ymd("2025-12-31"))
#    %>% filter(state %in% c("NJ", "RI", "MA")),
#   aes(x = dlr_date, group=market_desc, y = price, color=market_desc)
# ) +
#   geom_line( ) + 
#   scale_colour_manual(values = class_colours) +
#   
# #    colour    = "grey20",
# #    linewidth = 0.3
# #  ) +
#  facet_grid(rows = vars(state), cols = NULL) +
#   theme(
#     strip.background   = element_rect(fill = "grey92", colour = "grey40"),
#     strip.text         = element_text(size = 8, face = "bold"),
#     panel.grid.major.x = element_blank(),
#     panel.grid.minor.x = element_blank(),
#     panel.grid.major.y = element_line(colour = "grey88", linewidth = 0.3),
#     panel.grid.minor.y = element_blank(),
#     axis.title         = element_text(size = 8),
#     axis.text          = element_text(size = 7, colour = "grey20"),
#     plot.margin        = margin(4, 6, 4, 4, "pt")
#   )
# 
# ggsave(
#   here("images", "exploratory",
#        glue("prevailing_prices.pdf")),
#   plot   = price.mktcomb,
#   width  = 84,
#   height = 150,    # 4 stacked panels; adjust in 5mm increments if strips crowd
#   units  = "mm",
#   device = cairo_pdf
# )



# This is easier to see what we want it to show.
# 

price.mktcomb2 <- ggplot(
  grand_ma_prices %>% filter(dlr_date>=ymd("2024-01-01") , dlr_date<=ymd("2026-01-01"))
  %>% filter(state %in% c("NJ", "RI", "MA")),
  aes(x = dlr_date, y = price,  group=state, linetype=state)
) +
  geom_line(
    colour    = "grey20",
      linewidth = 0.4
    ) +
  
scale_y_continuous(
    name   = "Price per kg (Real 2013Q1 USD)"
  ) + 
scale_x_date(
    name   = "Year",
    date_breaks = "1 year",
    date_minor_breaks = "3 months",
    date_labels = "%Y"
    )  + 
scale_linetype_manual(
  name = "State",
  values = c("MA" = "dashed", "NJ" = "solid", "RI" = "dotted")
) +
  facet_grid(rows = vars(market_desc), cols = NULL) +
  theme(
    strip.background     = element_rect(fill = "grey92", colour = "grey40"),
    strip.text           = element_text(size = 8, face = "bold"),
    panel.grid.major.x   = element_blank(),
    panel.grid.minor.x   = element_blank(),
    panel.grid.major.y   = element_line(colour = "grey88", linewidth = 0.3),
    panel.grid.minor.y   = element_blank(),
    axis.title           = element_text(size = 8),
    axis.text            = element_text(size = 7, colour = "grey20"),
    # Display major and minor tick marks on x-axis
    axis.ticks.x         = element_line(colour = "grey20"),
    plot.margin          = margin(4, 6, 4, 4, "pt")
  )


ggsave(
  here("images", "exploratory",
       glue("prevailing_prices_cat.pdf")),
  plot   = price.mktcomb2,
  width  = 84,
  height = 150,    # 3 stacked panels; adjust in 5mm increments if strips crowd
  units  = "mm",
  device = cairo_pdf
)




