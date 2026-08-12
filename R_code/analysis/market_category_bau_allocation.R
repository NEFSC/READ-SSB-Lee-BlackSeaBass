# business as usual allocation of unclassifieds to market categories
# this is run AFTER the combined_datset is created.

library("here")

# load tidyverse and related
library("tidyverse")
library("haven")
library("scales")
library("glue")

# load utilities
library("knitr")
library("kableExtra")
library("viridis")
library("conflicted")

#deal with conflicts
conflicts_prefer(dplyr::filter())
conflicts_prefer(dplyr::lag())
conflicts_prefer(purrr::discard())
conflicts_prefer(dplyr::group_rows())
conflicts_prefer(viridis::viridis_pal())

###############################################################################
# Directories 
###############################################################################
here::i_am("R_code/analysis/market_category_bau_allocation.R")




data_vintage_string<-"2026-05-28"


# read in combined dataset

combined_dataset<-read_rds(file=here("data_folder","main","commercial",glue("BSB_original_combined_dataset{data_vintage_string}.Rds")))

# summ to the year semester stockabbrev market_desc 
sum<-combined_dataset %>%
  group_by(market_desc, semester, year, STOCK_ABBREV) %>%
  summarise(livlb=sum(livlb))

#mutate, filter and tidyup
short<-sum %>%
  mutate(landings_mt=livlb/(1000*2.204))%>%
  dplyr::filter(STOCK_ABBREV %in% c("NORTH", "SOUTH"))%>%
  mutate(year=as.numeric(as.character(year)))  




# get percentages for the non-unclassifed

# apply percentages to the classifieds

# graph


  


class_colours <- c(
  "Jumbo"  = "#1B6CA8",   # deep blue
  "Large"  = "#E05C2A",   # burnt orange
  "Medium" = "#2E8B57",   # sea green
  "Small"  = "#7B3F9E" ,   # purple
  "Unclassified" = "#404040" # dark gray
)


p_conserv_predictions <- ggplot(
  short %>% dplyr::filter(market_desc !="Unclassified") ,
  aes(x = year, y = landings_mt, fill = market_desc)
) +
  geom_col(
    position = position_stack(reverse = TRUE),
    width    = 0.8,       # leaves a visible gap between years
    colour   = NA         # suppress bar outlines
  ) +
  facet_grid(
    rows = vars(STOCK_ABBREV),
    cols = vars(semester),
    scales = "free_y"
  ) +
  scale_fill_manual(
    name   = "Market Category",
    values = class_colours,
    labels = c("Jumbo", "Large", "Medium", "Small","Unclassified")
  ) +
  scale_x_continuous(
    name   = "Year",
    breaks = scales::breaks_pretty(n = 5),
    expand = expansion(mult = 0.01)
  ) +
  scale_y_continuous(
    name   = "Live weight (mt)",
    labels = scales::label_comma(accuracy = 1),
    expand = expansion(mult = c(0, 0.05))
  ) +
  theme_bw(base_size = 9) +
  theme(
    strip.background   = element_rect(fill = "grey92", colour = "grey40"),
    strip.text         = element_text(size = 8, face = "bold"),
    panel.grid.major.x = element_blank(),
    panel.grid.minor.x = element_blank(),
    panel.grid.major.y = element_line(colour = "grey88", linewidth = 0.3),
    panel.grid.minor.y = element_blank(),
    axis.title         = element_text(size = 8),
    axis.text          = element_text(size = 7, colour = "grey20"),
    axis.text.x        = element_text(angle = 45, hjust = 1),
    legend.position    = "bottom",
    legend.title       = element_text(size = 7, face = "bold"),
    legend.text        = element_text(size = 7),
    legend.key.width   = unit(0.4, "cm"),
    legend.key.height  = unit(0.3, "cm"),
    legend.margin      = margin(0, 0, 0, 0),
    legend.box.spacing = unit(4, "pt"),
    plot.margin        = margin(4, 6, 4, 4, "pt")
  )

ggsave(
  here("images", "background",
       glue("market_category_distributions.pdf")),
  plot   = p_conserv_predictions,
  width  = 174,
  height = 120,    # adjust in 5mm increments if strip labels or legend crowd
  units  = "mm",
  device = cairo_pdf
)


percentages <-short %>% 
  dplyr::filter(market_desc !="Unclassified")%>%
  group_by(year, semester, STOCK_ABBREV) %>%
  mutate(total_landings=sum(livlb)) %>%
  ungroup() %>%
  mutate(pct=livlb/total_landings) %>%
  select(year, semester, market_desc, STOCK_ABBREV,pct)%>%
  rename(market_desc_new=market_desc)

unclass_baseline<-short %>%
  dplyr::filter(market_desc =="Unclassified")%>%
  left_join(percentages, by=join_by(year, semester, STOCK_ABBREV) , relationship="one-to-many") %>%
  mutate(allocated=livlb*pct) %>%
  group_by(year, semester, STOCK_ABBREV, market_desc_new) %>%
  mutate(allocated_mt=sum(allocated/(1000*2.204))) 
  
  

bau_allocation <- ggplot(
  unclass_baseline,
  aes(x = year, y = allocated_mt, fill = market_desc_new)
) +
  geom_col(
    position = position_stack(reverse = TRUE),
    width    = 0.8,       # leaves a visible gap between years
    colour   = NA         # suppress bar outlines
  ) +
  facet_grid(
    rows = vars(STOCK_ABBREV),
    cols = vars(semester),
    scales = "free_y"
  ) +
  scale_fill_manual(
    name   = "Market Category",
    values = class_colours,
    labels = c("Jumbo", "Large", "Medium", "Small","Unclassified")
  ) +
  scale_x_continuous(
    name   = "Year",
    breaks = scales::breaks_pretty(n = 5),
    expand = expansion(mult = 0.01)
  ) +
  scale_y_continuous(
    name   = "Live weight (mt)",
    labels = scales::label_comma(accuracy = 1),
    expand = expansion(mult = c(0, 0.05))
  ) +
  theme_bw(base_size = 9) +
  theme(
    strip.background   = element_rect(fill = "grey92", colour = "grey40"),
    strip.text         = element_text(size = 8, face = "bold"),
    panel.grid.major.x = element_blank(),
    panel.grid.minor.x = element_blank(),
    panel.grid.major.y = element_line(colour = "grey88", linewidth = 0.3),
    panel.grid.minor.y = element_blank(),
    axis.title         = element_text(size = 8),
    axis.text          = element_text(size = 7, colour = "grey20"),
    axis.text.x        = element_text(angle = 45, hjust = 1),
    legend.position    = "bottom",
    legend.title       = element_text(size = 7, face = "bold"),
    legend.text        = element_text(size = 7),
    legend.key.width   = unit(0.4, "cm"),
    legend.key.height  = unit(0.3, "cm"),
    legend.margin      = margin(0, 0, 0, 0),
    legend.box.spacing = unit(4, "pt"),
    plot.margin        = margin(4, 6, 4, 4, "pt")
  )

ggsave(
  here("images", "background",
       glue("bau_reallocation.pdf")),
  plot   = bau_allocation,
  width  = 174,
  height = 120,    # adjust in 5mm increments if strip labels or legend crowd
  units  = "mm",
  device = cairo_pdf
)
  
