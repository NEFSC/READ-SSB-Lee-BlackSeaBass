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

lbs_per_kg<-2.20462

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

combined_dataset<-combined_dataset %>%
  mutate(lndkg=lndlb/lbs_per_kg)%>%
  mutate(pricekgR_CPI=valueR_CPI/lndkg)

# To upper case, rename as SMALL_COMB, and relevel to re-order
combined_dataset<-combined_dataset %>%
  mutate(market_desc=str_to_upper(market_desc))%>%
  mutate(market_desc = if_else(market_desc == "SMALL", 
                               "SMALL.COMB", 
                               market_desc))
combined_dataset<-combined_dataset %>%
  mutate(market_desc=forcats::fct_relevel(market_desc,c("UNCLASSIFIED", "SMALL.COMB", "MEDIUM", "LARGE", "JUMBO")))

price.mktcomb <- ggplot(
  combined_dataset %>% filter(pricekgR_CPI >= 0 & pricekgR_CPI <= 10*lbs_per_kg),
  aes(x = pricekgR_CPI, weight = lndlb, y = after_stat(density))
) +
  geom_histogram(
    binwidth  = 0.25,
    fill      = "grey80",
    colour    = "grey20",
    linewidth = 0.3
  ) +
  facet_grid(rows = vars(market_desc), cols = NULL) +
  scale_x_continuous(
    name   = "Real price (USD/kg, CPI-deflated)",
    limits = c(0, 24),
    breaks = seq(0, 24, 4),
    expand = expansion(mult = 0.01)
  ) +
  scale_y_continuous(
    name   = "Density",
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
    plot.margin        = margin(4, 6, 4, 4, "pt")
  )

ggsave(
  here("images", "exploratory",
       glue("wprice_histograms_vertical_NR.pdf")),
  plot   = price.mktcomb,
  width  = 84,
  height = 150,    # 4 stacked panels; adjust in 5mm increments if strips crowd
  units  = "mm",
  device = cairo_pdf
)

#write_rds(p, file=here("images","exploratory","wprice_histograms_vertical_NR.Rds"))
####################################################################################################
####################################################################################################
####################################################################################################
# Biosampling data 
####################################################################################################
####################################################################################################

# Load in Length data


load(here("data_folder","main","commercial", "Landings.lengths.1989-2024.Rdata"))



# Random specifications for the size of plots I think
fyr <- 2013
lyr <- 2024
save.fig <- 'y'
fig.type <- 'png'
fig.ht.hist <- 8.3
fig.wd.hist <- 7.3

min.length <- 10
max.length <- 65

nespp4.order <- c(0, 6, 5, 3, 1, 7, 2)

# Years
yrs <- as.character(fyr:lyr)

# Order market names
mkt.cat.names <- mkt.cat.names %>% arrange(match(MKTCAT, nespp4.order))

# Originally written by Kiersten Curti and/or Sam Truesdell, this does length analysis:

##### Overview #####

# Print categories that are in the landings data but not in the length data
land.all %>% distinct(QTR) %>% 
  filter(!QTR %in% (len.all %>% select(QTR) %>% pull()))

land.all %>% distinct(SEMESTER) %>% 
  filter(!SEMESTER %in% (len.all %>% select(SEMESTER) %>% pull()))

land.all %>% distinct(NEGEAR2.GEARNM) %>% 
  filter(!NEGEAR2.GEARNM %in% (len.all %>% select(NEGEAR2.GEARNM) %>% pull()))

land.all %>% distinct(BSB.GEAR.CAT1) %>% 
  filter(!BSB.GEAR.CAT1 %in% (len.all %>% select(BSB.GEAR.CAT1) %>% pull()))

land.all %>% distinct(REGION) %>% 
  filter(!REGION %in% (len.all %>% select(REGION) %>% pull()))

land.all %>% distinct(MKTNM) %>% 
  filter(!MKTNM %in% (len.all  %>% select(MKTNM) %>% pull()))

land.all %>% distinct(MKTCOMB) %>% 
  filter(!MKTCOMB %in% (len.all %>% select(MKTCOMB) %>% pull()))


# Look at landings with missing variables
# NESPP4
missing.mkt <- land.all %>%
  filter(is.na(NESPP4==TRUE))
missing.mkt %>%
  group_by(YEAR, REGION) %>%
  summarize(n=n(),
            MT = sum(MT))

# Remove outliers from length data
length.outliers <- tibble(len.all) %>%
  filter(!LENGTH %in% (min.length:max.length)) %>%
  group_by(LENGTH) %>%
  summarize(NUMLEN = sum(NUMLEN))

dim(len.all)
len.all <- tibble(len.all) %>%
  filter(LENGTH %in% (min.length:max.length))
dim(len.all)

# Total length frequencies
total.lenfq <- len.all %>%
  group_by(LENGTH) %>%
  summarize(NUMLEN = sum(NUMLEN))



##### 1) At the finest resolution (by negear, qtr or year, market category and area), do we have samples where we had landings? #####

# Select only those years where biosampling occurred (i.e. where len.all.sel.yrs is not null)
sampled.yrs <- unique(len.all$YEAR)
tibble(yrs) %>% filter(!yrs %in% sampled.yrs)

land.all.samp <- tibble(land.all) %>%
  filter(YEAR %in% sampled.yrs)


# Function to sum landing and length data according to defined factors and merge the two datasets to determine if we have length samples where we have landings
merge.land.len.fx <- function(factor.names)  {
  #factor.names <- c("QTR", "AREA", "NEGEAR2.GEARNM", "MKTNM")
  #factor.names <- c("QTR", "NEGEAR2.GEARNM", "MKTNM", "AREA")
  #factor.names <- c("MKTNM")
  # Factors = YEAR, SEMIAN or QTR, NEGEAR2.GEARNM or GEAR.CAT, MKTNM or MKTSIMP, AREA or AREAF
  
  # Sum landing and length data by factors in factor.names
  # Variables = MT (landings) and NUMLEN (lengths)
  land.summed <- land.all.samp %>%
    group_by(across(c('YEAR',all_of(factor.names)))) %>%
    summarize(MT = sum(MT)) %>%
    ungroup()
  
  len.summed <- len.all %>%
    group_by(across(c('YEAR',all_of(factor.names)))) %>%
    summarize(NUMLEN = sum(NUMLEN)) %>%
    ungroup()
  
  len.summed$YEAR <- as.double(len.summed$YEAR)
  if(!is.null(len.summed$QTR)) len.summed$QTR <- as.integer(len.summed$QTR)
  
  # Number of samples for each factor combination
  nsamp.summed <- len.all %>%
    # Keep the rows where SampleID is *not* a duplicate
    distinct(SampleID, .keep_all = TRUE) %>%
    group_by(across(c('YEAR',factor.names))) %>%
    summarize(n.samples = n()) %>%
    ungroup()
  
  nsamp.summed$YEAR <- as.double(nsamp.summed$YEAR)
  if(!is.null(nsamp.summed$QTR)) nsamp.summed$QTR <- as.integer(nsamp.summed$QTR)
  
  land.len.merged <- 
    # Merge summarized NUMLENs with summarized n.samples
    full_join(len.summed, nsamp.summed) %>%
    # Merge length with landings data
    full_join(., land.summed) %>%
    group_by(YEAR) %>%
    mutate(MT.prop = round(MT/sum(MT, na.rm=TRUE), 2),
           MT = round(MT, 4),
           MT.sample = MT/n.samples
    ) %>%
    arrange(desc(MT.prop))
  
  land.len.merged
} # End of merge.land.len.fx function


# Function to select those categories where we have length samples but no landings
subset.missing.mt <- function(input.mat) {
  # input.mat <- samp.negear.area.mkt.qtr
  x1 <- input.mat %>%
    filter(!is.na(NUMLEN), is.na(MT))
  if(nrow(x1)>0)  {x1}  else{NULL}
} # End of subset.missing.mt fx



##### Number of length samples (compared to landings) by the stratification schemes providing the finest resolution

# Highest resolution: negear, stat area, mktnm and (year or quarter or semian)
samp.gr.region.mkt.qtr <- merge.land.len.fx(c("QTR", "BSB.GEAR.CAT1", "MKTNM", "REGION"))        
miss.gr.region.mkt.qtr <- subset.missing.mt(samp.gr.region.mkt.qtr)

samp.gr.region.mkt.sem <- merge.land.len.fx(c("SEMESTER", "BSB.GEAR.CAT1", "MKTNM", "REGION"))        
miss.gr.region.mkt.sem <- subset.missing.mt(samp.gr.region.mkt.sem)

samp.gr.region.mkt.yr <- merge.land.len.fx(c("YEAR", "BSB.GEAR.CAT1", "MKTNM", "REGION"))        
miss.gr.region.mkt.yr <- subset.missing.mt(samp.gr.region.mkt.yr)

samp.gr.region.mktcomb.sem <- merge.land.len.fx(c("SEMESTER", "BSB.GEAR.CAT1", "MKTCOMB", "REGION")) %>% arrange(YEAR)        
miss.gr.region.mktcomb.sem <- subset.missing.mt(samp.gr.region.mktcomb.sem)

samp.gr.region.mktcomb.yr <- merge.land.len.fx(c("YEAR", "BSB.GEAR.CAT1", "MKTCOMB", "REGION")) %>% arrange(YEAR)        
miss.gr.region.mktcomb.yr <- subset.missing.mt(samp.gr.region.mktcomb.yr)

samp.mktcomb.region.yr <- merge.land.len.fx(c("YEAR", "MKTCOMB", "REGION")) %>% arrange(YEAR, MKTCOMB)        
miss.mktcomb.region.yr <- subset.missing.mt(samp.gr.region.mktcomb.yr)

# Sample summary by market category and simplified market category

# By market only (MKTNM or MKTCOMB)
samples.mkt <- merge.land.len.fx(c("MKTNM"))
samples.mktcomb <- merge.land.len.fx(c("MKTCOMB"))

mkt.sample.summary <- full_join(
  samples.mkt %>%
    filter(MT>10) %>%
    group_by(MKTNM) %>%
    summarize(nyr.land = n())
  ,
  samples.mkt %>%
    filter(!is.na(NUMLEN)) %>%
    group_by(MKTNM) %>%
    summarize(nyr.len = n())
)

mktcomb.sample.summary <- full_join(
  samples.mktcomb %>%
    filter(MT>10) %>%
    group_by(MKTCOMB) %>%
    summarize(nyr.land = n())
  ,
  samples.mktcomb %>%
    filter(!is.na(NUMLEN)) %>%
    group_by(MKTCOMB) %>%
    summarize(nyr.len = n())
)
mktcomb.sample.summary


# By market and region
samples.mktcomb.reg <- merge.land.len.fx(c("REGION", "MKTCOMB"))

mktcomb.reg.sample.summary <- full_join(
  samples.mktcomb.reg %>%
    filter(MT>10) %>%
    group_by(REGION, MKTCOMB) %>%
    summarize(nyr.land = n())
  ,
  samples.mktcomb.reg %>%
    filter(!is.na(NUMLEN)) %>%
    group_by(REGION, MKTCOMB) %>%
    summarize(nyr.len = n())
) %>%
  filter(REGION != 'SAB')
mktcomb.reg.sample.summary

len.all <- len.all %>%
  mutate(YEAR = as.double(YEAR))

# Evaluate observations with unknown region
unk.region <- full_join(
  land.all %>%
    filter(REGION == 'Unknown') %>%
    group_by(YEAR, AREA) %>%
    summarize(MT = sum(MT))
  ,
  len.all %>%
    filter(REGION == 'Unknown') %>%
    group_by(YEAR, AREA) %>%
    summarize(NUMLEN = sum(NUMLEN))
)
# View(unk.region)

# Unknown region samples from 2019 onward (i.e. since sampling reduced)



##### 2) Do length distributions vary across market categories, regions, quarters and semesters?   #####  


##### List unique factors #####
grs  <- len.all %>% distinct(BSB.GEAR.CAT1) %>% pull()
qtrs <- len.all %>% distinct(QTR) %>% arrange(QTR) %>% pull() 
mkts <- mkt.cat.names %>% distinct(MKTNM) %>% 
  filter(MKTNM %in% unique(len.all$MKTNM)) %>% pull()
mktcombs <- mkt.cat.names %>% distinct(MKTCOMB) %>% 
  filter(MKTCOMB %in% unique(len.all$MKTCOMB)) %>% pull()
regions <- len.all %>% distinct(REGION) %>% filter(!REGION=='Unknown') %>% pull()

n.mkts <- length(mkts)
n.mktcombs <- length(mktcombs)


### A)
# Plot length frequencies by combined market categories

# Ggplot
plot.data <- len.all %>% 
  select(MKTCOMB, LENGTH, NUMLEN) %>%
  uncount(NUMLEN) %>% ungroup() %>%
  mutate(MKTCOMB = factor(MKTCOMB, levels = mktcombs))
nbins <- length(min(plot.data$LENGTH):max(plot.data$LENGTH))
lfplot.mktcomb <- plot.data %>% 
  ggplot() +
  aes(x=LENGTH,y=after_stat(density)) + 
  geom_histogram(
    bins=nbins, 
    fill      = "grey80",
    colour    = "grey20",
    linewidth = 0.3
  ) +
  facet_grid(rows=vars(MKTCOMB), cols=NULL) + 
  scale_x_continuous(
    name   = "Length (cm))",
  ) +
  scale_y_continuous(
    name   = "Density",
    expand = expansion(mult = c(0, 0.05))
  )+ 
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
    plot.margin        = margin(4, 6, 4, 4, "pt")
  )
fname <- 'LenFq.Mktcomb'
if(save.fig=='y'){
  ggsave(
    here("images", "background",
         glue("{fname}.pdf")),
    plot   = lfplot.mktcomb,
    width  = 84,
    height = 150,    # 4 stacked panels; adjust in 5mm increments if strips crowd
    units  = "mm",
    device = cairo_pdf
  )
}











