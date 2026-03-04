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

################################################################################
# Emily's adapted markdown code
################################################################################

library(tidyverse)
# Located in /writing but not sure if you need an extra "here" to call it
# Github ignores it, so let me send it to you separately?
load('Landings.lengths.1989-2024.Rdata')

# Random specifications for the size of plots I think
fyr <- 1989
lyr <- 2024
save.fig <- 'y'
fig.type <- 'wmf'
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

windows(record = TRUE)

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
  geom_histogram(aes(x=LENGTH), bins=nbins, fill='white', colour='black') +
  facet_grid(rows=vars(MKTCOMB), cols=NULL, scales = 'free')
lfplot.mktcomb
fname <- 'LenFq.Mktcomb'
if(save.fig=='y') { savePlot(file=file.path(paste(fname,fig.type,sep='.')), type = fig.type) }  

# # Lattice
# len.mktcomb <- len.all %>%
#   group_by(MKTCOMB, LENGTH) %>%
#   summarize(NUMLEN = sum(NUMLEN)) %>%
#   mutate(MKTCOMB = factor(MKTCOMB, levels = mktcombs))
# lfplot.mktcomb.lat <- xyplot(as.numeric(NUMLEN)~as.numeric(LENGTH) | as.factor(MKTCOMB), data=len.mktcomb, layout=c(1,n.mktcombs), type='h', scales=list(x=list(alternating=1, relation="same"), y=list(relation="free")), xlab="Length", ylab="Frequency", as.table=TRUE)
#   print(lfplot.mktcomb.lat)
# fname <- 'LenFq.Mktcomb.lattice'
# if(save.fig=='y') { savePlot(file=file.path(lenfq.dir, paste(fname,fig.type,sep='.')),type=fig.type) }  


### B)
# Plot length frequencies by mktnm
plot.data <- len.all %>%
  select(MKTNM, LENGTH, NUMLEN) %>%
  uncount(NUMLEN) %>% ungroup() %>%
  mutate(MKTNM = factor(MKTNM, levels = mkts)) 
nbins <- length(min(plot.data$LENGTH):max(plot.data$LENGTH))
lfplot.mkt <- plot.data %>% 
  ggplot() +
  geom_histogram(aes(x=LENGTH), bins=nbins, fill='white', colour='black') +
  facet_grid(rows=vars(MKTNM), cols=NULL, scales = 'free')
lfplot.mkt
fname <- 'LenFq.Mkt'
if(save.fig=='y') { savePlot(file=file.path(paste(fname,fig.type,sep='.')),type=fig.type) }  


### C)
# Plot length frequencies by region

# Correct length bins but need to break up into two steps
plot.data <- len.all %>%
  filter(!REGION == 'Unknown') %>%
  select(REGION, LENGTH, NUMLEN) %>%
  uncount(NUMLEN) %>% ungroup() %>%
  mutate(REGION = factor(REGION, levels = regions)) 
nbins <- length(min(plot.data$LENGTH):max(plot.data$LENGTH))
lfplot.region <- plot.data %>%
  ggplot() +
  geom_histogram(aes(x=LENGTH), bins=nbins, fill='white', colour='black') +
  facet_grid(rows=vars(REGION), cols=NULL, scales = 'free')
lfplot.region
fname <- 'LenFq.Region'
if(save.fig=='y') { savePlot(file=file.path(paste(fname,fig.type,sep='.')),type=fig.type) }  


# Keep unknown region
plot.data <- len.all %>%
  select(REGION, LENGTH, NUMLEN) %>%
  uncount(NUMLEN) %>% ungroup() %>%
  mutate(REGION = factor(REGION, levels = c(regions,'Unknown'))) 
nbins <- length(min(plot.data$LENGTH):max(plot.data$LENGTH))
lfplot.region.unk <- plot.data %>%
  ggplot() +
  geom_histogram(aes(x=LENGTH), bins=nbins, fill='white', colour='black') +
  facet_grid(rows=vars(REGION), cols=NULL, scales = 'free')
lfplot.region.unk
fname <- 'LenFq.Region.Unknown'
if(save.fig=='y') { savePlot(file=file.path(paste(fname,fig.type,sep='.')),type=fig.type) }  


### D)
# Plot length frequencies by quarter

plot.data <- len.all %>%
  select(QTR, LENGTH, NUMLEN) %>%
  uncount(NUMLEN) %>% ungroup() %>%
  mutate(QTR = factor(QTR, levels = sort(qtrs)))
nbins <- length(min(plot.data$LENGTH):max(plot.data$LENGTH))
lfplot.qtr <- plot.data %>% 
  ggplot() +
  geom_histogram(aes(x=LENGTH), bins=nbins, fill='white', colour='black') +
  facet_grid(rows=vars(QTR), cols=NULL, scales = 'free')
lfplot.qtr
fname <- 'LenFq.Qtr'
if(save.fig=='y') { savePlot(file=file.path(paste(fname,fig.type,sep='.')),type=fig.type) }  


### E)
# Plot length frequencies by semester

plot.data <- len.all %>%
  select(SEMESTER, LENGTH, NUMLEN) %>%
  uncount(NUMLEN) %>% ungroup() %>%
  mutate(SEMESTER = factor(SEMESTER, levels = c(1,2))) 
nbins <- length(min(plot.data$LENGTH):max(plot.data$LENGTH))
lfplot.sem <- plot.data %>% 
  ggplot() +
  geom_histogram(aes(x=LENGTH), bins=nbins, fill='white', colour='black') +
  facet_grid(rows=vars(SEMESTER), cols=NULL, scales = 'free')
lfplot.sem
fname <- 'LenFq.Sem'
if(save.fig=='y') { savePlot(file=file.path(paste(fname,fig.type,sep='.')),type=fig.type) }  



##### 3) Do the trends across market categories and regions hold when they are analyzed over groups of years and not the entire time series? #####
#    Create separate figures for each year bin using lapply; Create one figure that uses fill to plot by year bin


################!!!!!!!!!!!!!!!!! Here is where we can change the breakdown by years and just plot those years of interest
# Create year bins
yr.bins <- bind_cols(YEAR = as.integer(yrs), 
                     bins = cut_width(yrs, width=5, labels=FALSE)
) %>%
  group_by(bins) %>%
  mutate( yr.bin = str_c(min(YEAR), max(YEAR), sep='-') ) %>%
  ungroup() %>%
  select(-bins)
uniq.yr.bins <- yr.bins %>% distinct(yr.bin) %>% pull()

# Merge year bins with len.all
dim(len.all)
len.all <- len.all %>%
  left_join(., yr.bins)
dim(len.all)
unique(len.all$yr.bin)

# Split by yr bin into list for plotting
len.all.yrbin <- split(len.all, len.all$yr.bin)


### For each year bin, plot length frequencies by:



# Test with fill instead of lapply/creating different figures for each yearbin
fig.data <- len.all %>%
  select(MKTCOMB, yr.bin, LENGTH, NUMLEN) %>%
  uncount(NUMLEN) %>% ungroup() %>%
  mutate(MKTCOMB = factor(MKTCOMB, levels = mktcombs),
         yr.bin = factor(yr.bin, levels = uniq.yr.bins))
nbins <- length(min(fig.data$LENGTH):max(fig.data$LENGTH))
windows()
lfplot.mktcomb.yrbin <- fig.data %>%
  ggplot() +
  geom_histogram(aes(x=LENGTH, fill=yr.bin), alpha=0.6, bins=nbins, colour='black', position='identity') +
  facet_grid(rows=vars(MKTCOMB), cols=NULL, scales = 'free')
print(lfplot.mktcomb.yrbin)
fname <- 'LenFq.MktComb.YrBin'
if(save.fig=='y') { savePlot(file=file.path(paste(fname,fig.type,sep='.')),type=fig.type) }


### B)  Region
# lapply
windows(record = TRUE)
lapply(seq_along(len.all.yrbin), function(x) {
  fig.data <- len.all.yrbin[[x]] %>%
    select(yr.bin, REGION, LENGTH, NUMLEN) %>%
    filter(!REGION=='Unknown') %>%
    uncount(NUMLEN) %>% ungroup() %>%
    mutate(REGION = factor(REGION, levels = regions))
  nbins <- length(min(fig.data$LENGTH):max(fig.data$LENGTH))
  fig <- fig.data %>%
    ggplot() +
    geom_histogram(aes(x=LENGTH), bins=nbins, fill='white', colour='black') +
    facet_grid(rows=vars(REGION), cols=NULL, scales = 'free') +
    ggtitle(names(len.all.yrbin)[x])
  assign( paste("lfplot.region",x,sep='.'), fig, envir = .GlobalEnv)
  print(get(paste("lfplot.region",x,sep='.')))
  fname <- paste('LenFq.Region',names(len.all.yrbin)[x],sep='.')
  if(save.fig=='y') { savePlot(file=file.path(paste(fname,fig.type,sep='.')),type=fig.type) }
})

# fill
fig.data <- len.all %>%
  select(yr.bin, REGION, LENGTH, NUMLEN) %>%
  filter(!REGION=='Unknown') %>%
  uncount(NUMLEN) %>% ungroup() %>%
  mutate(REGION = factor(REGION, levels = regions),
         yr.bin = factor(yr.bin, levels = uniq.yr.bins) )
nbins <- length(min(fig.data$LENGTH):max(fig.data$LENGTH))
windows()
lfplot.mktcomb.region <- fig.data %>%
  ggplot() +
  geom_histogram(aes(x=LENGTH, fill=REGION), alpha=0.4, bins=nbins, colour='black', position='identity') +
  facet_grid(rows=vars(yr.bin), cols=NULL, scales = 'free')
print(lfplot.mktcomb.region)
fname <- 'LenFq.Region.YrBin'
if(save.fig=='y') { savePlot(file=file.path(paste(fname,fig.type,sep='.')),type=fig.type) }



##### 4) Across all years, do combined market category length distributions vary across regions and do region length distributions vary across market category? #####


dim(len.all)
dim(len.all%>%filter(REGION=='Unknown'))
dim(len.all%>%filter(!REGION=='Unknown'))

plot.data <- len.all %>% 
  filter(REGION %in% regions) %>%
  select(MKTCOMB, REGION, LENGTH, NUMLEN) %>%
  uncount(NUMLEN) %>% ungroup() %>%
  mutate(MKTCOMB = factor(MKTCOMB, levels = mktcombs),
         REGION = factor(REGION, levels = regions))
nbins <- length(min(plot.data$LENGTH):max(plot.data$LENGTH))

windows(record = TRUE)

# A) Facet = market, fill = region


lfplot.region.mktcomb <- plot.data %>% 
  ggplot() +
  geom_histogram(aes(x=LENGTH, fill=REGION), alpha=0.4, bins=nbins, colour='black', position='identity') +
  facet_grid(rows=vars(MKTCOMB), cols=NULL, scales = 'free')
print(lfplot.region.mktcomb)
fname <- 'LenFq.Region.Mktcomb'
if(save.fig=='y') { savePlot(file=file.path(paste(fname,fig.type,sep='.')),type=fig.type) }

# B) Facet = region, fill = market

lfplot.mktcomb.region <- plot.data %>% 
  ggplot() +
  geom_histogram(aes(x=LENGTH, fill=MKTCOMB), alpha=0.6, bins=nbins, colour='black', position='identity') +
  facet_grid(rows=vars(REGION), cols=NULL, scales = 'free')
print(lfplot.mktcomb.region)
fname <- 'LenFq.Mktcomb.Region'
if(save.fig=='y') { savePlot(file=file.path(paste(fname,fig.type,sep='.')),type=fig.type) }



##### 5) For each region, does market category length distribution vary across years? #####
# Separate plot for each region; market category is facet, fill is year


# Split by region into list for plotting and remove unknown region
len.all.region <- split(len.all, len.all$REGION)
len.all.region <- len.all.region[regions]

windows(record = TRUE)
lapply(seq_along(len.all.region), function(x) {
  # x <- 1
  reg <- names(len.all.region)[x]
  fig.data <- len.all.region[[x]] %>%
    select(yr.bin, REGION, MKTCOMB, LENGTH, NUMLEN) %>%
    uncount(NUMLEN) %>% ungroup() %>%
    mutate(MKTCOMB = factor(MKTCOMB, levels = mktcombs),
           yr.bin = factor(yr.bin, levels = uniq.yr.bins) )
  nbins <- length(min(fig.data$LENGTH):max(fig.data$LENGTH))
  
  fig <- fig.data %>%
    ggplot() +
    geom_histogram(aes(x=LENGTH, fill=yr.bin), alpha=0.6, bins=nbins, colour='black', position='identity') +
    facet_grid(rows=vars(MKTCOMB), cols=NULL, scales = 'free') +
    ggtitle(reg)
  assign( paste("lfplot.mktcomb.yrbin",reg,sep='.'), fig, envir = .GlobalEnv)
  print(get(paste("lfplot.mktcomb.yrbin",reg,sep='.')))
  fname <- paste('LenFq.MktComb.Yrbin', reg, sep='.')
  if(save.fig=='y') { savePlot(file=file.path(paste(fname,fig.type,sep='.')),type=fig.type) }
})



##### 6) For each year bin, does market category length distribution vary by region? #####
# Separate plot for each year bin; market category is facet, fill is region


windows(record = TRUE)
lapply(seq_along(len.all.yrbin), function(x) {
  # x <- 1
  bin <- names(len.all.yrbin)[x]
  fig.data <- len.all.yrbin[[x]] %>%
    select(yr.bin, REGION, MKTCOMB, LENGTH, NUMLEN) %>%
    filter(REGION %in% regions) %>%
    uncount(NUMLEN) %>% ungroup() %>%
    mutate(MKTCOMB = factor(MKTCOMB, levels = mktcombs),
           REGION = factor(REGION, levels = regions) )
  nbins <- length(min(fig.data$LENGTH):max(fig.data$LENGTH))
  
  fig <- fig.data %>%
    ggplot() +
    geom_histogram(aes(x=LENGTH, fill=REGION), alpha=0.4, bins=nbins, colour='black', position='identity') +
    facet_grid(rows=vars(MKTCOMB), cols=NULL, scales = 'free') +
    ggtitle(bin)
  assign( paste("lfplot.mktcomb.region",x,sep='.'), fig, envir = .GlobalEnv)
  print(get(paste("lfplot.mktcomb.region",x,sep='.')))
  fname <- paste('LenFq.MktComb.Region', bin, sep='.')
  if(save.fig=='y') { savePlot(file=file.path(paste(fname,fig.type,sep='.')),type=fig.type) }
})



##### 7) For each region, do market category length distributions vary by gear? #####
# Separate plot for each region; market category is facet, fill is gear

windows(record = TRUE)
lapply(seq_along(len.all.region), function(x) {
  # x <- 1
  reg <- names(len.all.region)[x]
  fig.data <- len.all.region[[x]] %>%
    select(yr.bin, REGION, MKTCOMB, BSB.GEAR.CAT1, LENGTH, NUMLEN) %>%
    uncount(NUMLEN) %>% ungroup() %>%
    mutate(MKTCOMB = factor(MKTCOMB, levels = mktcombs),
           yr.bin = factor(yr.bin, levels = uniq.yr.bins),
           BSB.GEAR.CAT1 = factor(BSB.GEAR.CAT1, levels = grs) )
  nbins <- length(min(fig.data$LENGTH):max(fig.data$LENGTH))
  
  fig <- fig.data %>%
    ggplot() +
    geom_histogram(aes(x=LENGTH, fill=BSB.GEAR.CAT1), alpha=0.6, bins=nbins, colour='black', position='identity') +
    facet_grid(rows=vars(MKTCOMB), cols=NULL, scales = 'free') +
    ggtitle(reg)
  assign( paste("lfplot.mktcomb.gr",reg,sep='.'), fig, envir = .GlobalEnv)
  print(get(paste("lfplot.mktcomb.gr",reg,sep='.')))
  fname <- paste('LenFq.MktComb.Gr', reg, sep='.')
  if(save.fig=='y') { savePlot(file=file.path(paste(fname,fig.type,sep='.')),type=fig.type) }
})



##### 8) For each gear, do market category length distributions vary by region? ##### 

# Split by gear into list for plotting
len.all.gr <- split(len.all, len.all$BSB.GEAR.CAT1)

len.nsamp.gr <- len.all %>%
  group_by(BSB.GEAR.CAT1) %>%
  summarize(NUMLEN = sum(NUMLEN),
            nsamples = length(unique(SampleID)))

len.nsamp.gr.yr <- len.all %>%
  group_by(BSB.GEAR.CAT1, YEAR) %>%
  summarize(NUMLEN = sum(NUMLEN),
            nsamples = length(unique(SampleID)))

windows(record = TRUE)
lapply(seq_along(len.all.gr), function(x) {
  # x <- 1
  gr <- names(len.all.gr)[x]
  fig.data <- len.all.gr[[x]] %>%
    select(yr.bin, REGION, MKTCOMB, BSB.GEAR.CAT1, LENGTH, NUMLEN) %>%
    filter(REGION %in% regions) %>%
    uncount(NUMLEN) %>% ungroup() %>%
    mutate(MKTCOMB = factor(MKTCOMB, levels = mktcombs),
           yr.bin = factor(yr.bin, levels = uniq.yr.bins),
           REGION = factor(REGION, levels = regions) )
  nbins <- length(min(fig.data$LENGTH):max(fig.data$LENGTH))
  
  fig <- fig.data %>%
    ggplot() +
    geom_histogram(aes(x=LENGTH, fill=REGION), alpha=0.6, bins=nbins, colour='black', position='identity') +
    facet_grid(rows=vars(MKTCOMB), cols=NULL, scales = 'free') +
    ggtitle(gr)
  print(fig)
  assign( paste("lfplot.mktcomb.reg",gr,sep='.'), fig, envir = .GlobalEnv)
  print(get(paste("lfplot.mktcomb.reg",gr,sep='.')))
  fname <- paste('LenFq.MktComb.Region', gr, sep='.')
  if(save.fig=='y') { savePlot(file=file.path(paste(fname,fig.type,sep='.')),type=fig.type) }
})



##### 9) For each gear and year bin, do market category length distributions vary by region? ##### 


grs.sub <- c('HANDLINE', 'POTS.TRAPS', 'TRAWL')
len.all.gr.sub <- len.all.gr[grs.sub]
len.all.gr.yrbin <- lapply(len.all.gr.sub, function(x) {split(x, x$yr.bin)})

lapply(seq_along(len.all.gr.yrbin), function(g) {
  # g <- 1
  gr <- names(len.all.gr.yrbin)[g]
  data.sub <- len.all.gr.yrbin[[g]]
  
  windows(record = TRUE)
  lapply(seq_along(data.sub), function(y) {
    # y <- 1
    bin <- names(data.sub)[y]
    fig.data <- data.sub[[y]] %>%
      select(yr.bin, REGION, MKTCOMB, BSB.GEAR.CAT1, LENGTH, NUMLEN) %>%
      filter(REGION %in% regions) %>%
      uncount(NUMLEN) %>% ungroup() %>%
      mutate(MKTCOMB = factor(MKTCOMB, levels = mktcombs),
             yr.bin = factor(yr.bin, levels = uniq.yr.bins),
             BSB.GEAR.CAT1 = factor(BSB.GEAR.CAT1, levels = grs.sub),
             REGION = factor(REGION, levels = regions)
      )
    nbins <- length(min(fig.data$LENGTH):max(fig.data$LENGTH))
    
    fig <- fig.data %>%
      ggplot() +
      geom_histogram(aes(x=LENGTH, fill=REGION), alpha=0.6, bins=nbins, colour='black', position='identity') +
      facet_grid(rows=vars(MKTCOMB), cols=NULL, scales = 'free') +
      ggtitle(paste(gr,bin,sep=': '))
    print(fig)
    assign( paste("lfplot.mktcomb.reg",gr,y,sep='.'), fig, envir = .GlobalEnv)
    print(get(paste("lfplot.mktcomb.reg",gr,y,sep='.')))
    fname <- paste('LenFq.MktComb.Region', gr, bin, sep='.')
    if(save.fig=='y') { savePlot(file=file.path(paste(fname,fig.type,sep='.')),type=fig.type) }
  }) # end of y lapply
}) # end of g lapply



##### 10) For each gear and region, do market category length distributions vary across years? ##### 


len.all.gr.region <- lapply(len.all.gr.sub, function(x) {split(x, x$REGION)[regions]})

lapply(seq_along(len.all.gr.region), function(g) {
  # g <- 3
  gr <- names(len.all.gr.region)[g]
  data.sub <- len.all.gr.region[[g]]
  
  windows(record = TRUE)
  lapply(seq_along(data.sub), function(r) {
    # r <- 1
    reg <- names(data.sub)[r]
    fig.data <- data.sub[[r]] %>%
      select(yr.bin, REGION, MKTCOMB, BSB.GEAR.CAT1, LENGTH, NUMLEN) %>%
      uncount(NUMLEN) %>% ungroup() %>%
      mutate(MKTCOMB = factor(MKTCOMB, levels = mktcombs),
             yr.bin = factor(yr.bin, levels = uniq.yr.bins),
             BSB.GEAR.CAT1 = factor(BSB.GEAR.CAT1, levels = grs.sub),
             REGION = factor(REGION, levels = regions)
      )
    nbins <- length(min(fig.data$LENGTH):max(fig.data$LENGTH))
    
    fig <- fig.data %>%
      ggplot() +
      geom_histogram(aes(x=LENGTH, fill=yr.bin), alpha=0.6, bins=nbins, colour='black', position='identity') +
      facet_grid(rows=vars(MKTCOMB), cols=NULL, scales = 'free') +
      ggtitle(paste(gr,reg,sep=': '))
    assign( paste("lfplot.mktcomb.yrbin", reg, gr, sep='.'), fig, envir = .GlobalEnv)
    print(get(paste("lfplot.mktcomb.yrbin", reg, gr, sep='.')))
    fname <- paste('LenFq.MktComb.Yrbin', reg, gr, sep='.')
    if(save.fig=='y') { savePlot(file=file.path(paste(fname,fig.type,sep='.')),type=fig.type) }
  }) # end of y lapply
}) # end of g lapply



##### 11) For each region and year bin, do market category length distributions vary by gear? ##### 


len.all.region.yrbin <- lapply(len.all.region, function(x) {split(x, x$yr.bin)})

lapply(seq_along(len.all.region.yrbin), function(r) {
  # r <- 1
  reg <- names(len.all.region.yrbin)[r]
  data.sub <- len.all.region.yrbin[[r]]
  
  windows(record = TRUE)
  lapply(seq_along(data.sub), function(y) {
    # y <- 1
    bin <- names(data.sub)[y]
    fig.data <- data.sub[[y]] %>%
      select(yr.bin, REGION, MKTCOMB, BSB.GEAR.CAT1, LENGTH, NUMLEN) %>%
      filter(BSB.GEAR.CAT1 %in% grs.sub) %>%
      uncount(NUMLEN) %>% ungroup() %>%
      mutate(MKTCOMB = factor(MKTCOMB, levels = mktcombs),
             yr.bin = factor(yr.bin, levels = uniq.yr.bins),
             BSB.GEAR.CAT1 = factor(BSB.GEAR.CAT1, levels = grs.sub),
             REGION = factor(REGION, levels = regions)
      )
    nbins <- length(min(fig.data$LENGTH):max(fig.data$LENGTH))
    
    fig <- fig.data %>%
      ggplot() +
      geom_histogram(aes(x=LENGTH, fill=BSB.GEAR.CAT1), alpha=0.6, bins=nbins, colour='black', position='identity') +
      facet_grid(rows=vars(MKTCOMB), cols=NULL, scales = 'free') +
      ggtitle(paste(reg,bin,sep=': '))
    assign( paste("lfplot.mktcomb.gr", reg, y, sep='.'), fig, envir = .GlobalEnv)
    print(get(paste("lfplot.mktcomb.gr", reg, y, sep='.')))
    fname <- paste('LenFq.MktComb.Gr', reg, bin, sep='.')
    if(save.fig=='y') { savePlot(file=file.path(paste(fname,fig.type,sep='.')),type=fig.type) }
  }) # end of y lapply
}) # end of g lapply
