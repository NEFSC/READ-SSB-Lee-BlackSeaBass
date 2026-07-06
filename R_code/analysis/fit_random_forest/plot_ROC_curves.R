# Code to Compute ROC curves after fitting the model.


# Probabilty calibration does not change the ROC curves, so we will only plot after
# applying the predictions. There's not need to load in the calibration data.


# Inputs
# data_split  -- estimation dataset that was split into 3 parts (train, validation, test)
# prepped_recipe -- the recipe after prep
# final_ranger_fit -- the final trained model

#
# Outputs 
#
## Images 
### roc_training_dataset_ a rough, un-counted ROC curve
### roc_testing_dataset_ pub-read ROC curve, on uncounted data



search_type<-"Advanced"
modeltype<-"nocluster"


library("here")

# load tidyverse and related
library("tidyverse")
library("scales")
library("ggrepel")
# load tidyverse and related
library("tidymodels")

# load machine learning and estimation tools
library("nnet")
library("ranger")
library("bonsai")
library("probably")
library("discrim")

# load utilities
library("knitr")
library("kableExtra")
library("viridis")
library("glue")

#3d plots
library("htmlwidgets")
library("plotly")

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
conflicts_prefer(vip::vi)

here::i_am("R_code/analysis/fit_random_forest/weighted_calibration.R")

# modeltype_patterns.R defines all file-naming pattern variables (data_pattern,
# tuning_pattern, final_pattern, vi_pattern, prepped_recipe string, prob_names, etc.)
# predict_byhand.R defines the predict_byhand() wrapper used throughout.
source(here("R_code","analysis","helpers","modeltype_patterns.R"))
source(here("R_code","analysis","helpers","predict_byhand.R"))



lbs_per_mt<-2204.62
#############################################################################
my_images<-here("images")
descriptive_images<-here("images","descriptive")
exploratory_images<-here("images","exploratory")


###############################################################
# Vintage resolution: scan results and data directories to identify the most
# recent versioned file for each object type. For each object type , matching
# filenames are listed, the known prefix and ".Rds" suffix are stripped, and
# max() of the remaining date/version strings picks the latest.
# finalfit_vintage and VI_vintage are set equal to tuning_vintage by
# construction; the upstream tuning/training code guarantees they are in sync.
###############################################################
data_vintage_string<-list.files(here("results","ranger"), pattern=glob2rx(glue("{data_pattern}*Rds")))
data_vintage_string<-gsub(data_pattern,"",data_vintage_string)
data_vintage_string<-gsub(".Rds","",data_vintage_string)
data_vintage_string<-max(data_vintage_string)

tuning_vintage<-list.files(here("results","ranger"), pattern=glob2rx(glue("{tuning_pattern}*Rds")))
tuning_vintage<-gsub(tuning_pattern,"",tuning_vintage)
tuning_vintage<-gsub(".Rds","",tuning_vintage)
tuning_vintage<-max(tuning_vintage)

# Tuning, training, VI code guarantees that the finalfit and VI vintages are the same as the tuning vintages.  

finalfit_vintage<-tuning_vintage
VI_vintage<-tuning_vintage


final_fit_file_name<-glue("{final_pattern}{tuning_vintage}.Rds")
vi_file_name<-glue("{vi_pattern}{tuning_vintage}.Rds")
prepped_recipe_file_name<-glue("{prepped_recipe}{tuning_vintage}.Rds")


vintage_string<-list.files(here("data_folder","main","commercial"), pattern=glob2rx("BSB_estimation_dataset*Rds"))

raw_oos_data_vintage_string<-list.files(here("data_folder","main","commercial"), pattern=glob2rx("BSB_unclassified_dataset*Rds"))
raw_oos_data_vintage_string<-gsub("BSB_unclassified_dataset","",raw_oos_data_vintage_string)
raw_oos_data_vintage_string<-gsub(".Rds","",raw_oos_data_vintage_string)
raw_oos_data_vintage_string<-max(raw_oos_data_vintage_string)

###############################################################
# Load in data
###############################################################
# # this was created with data_prep_ml.Rmd
data_split<-readr::read_rds(file=here("results","ranger",glue("{data_pattern}{data_vintage_string}.Rds")))
# Onlyneed the test and validation 
train_data <- training(data_split)
validation_data <- validation(data_split)
test_data <- testing(data_split)

# recreate the frequency weights variables
# lndlb (landed pounds per transaction) serves as a frequency/case weight
# throughout; high-volume transactions receive proportionally more influence
# in all subsequent weighted metrics.
validation_data<-validation_data %>%
  mutate(weighting=frequency_weights(lndlb))
test_data<-test_data %>%
  mutate(weighting=frequency_weights(lndlb))

prepped_recipe<-read_rds(file=here("results","ranger",prepped_recipe_file_name))

final_ranger_fit<-read_rds(file=here("results","ranger",glue("{final_pattern}{tuning_vintage}.Rds")))



################################################################################
# Generate class-probability predictions on the TRAINING set via the custom
# predict_byhand() wrapper (applies prepped_recipe before calling ranger).
# The modal predicted class is extracted by finding the column with the highest
# probability for each row, then bound back alongside the raw probabilities
# and original validation data.

# looking at the training set is a nice quick sanity check, but not needed for publication. So I won't take the
# time/trouble to make it very pretty.



class_levels <- c("Jumbo", "Large", "Medium", "Small")
train_preds<-predict_byhand(new_data=train_data,
                           prepped_recipe = prepped_recipe,
                           ranger_fitted_model  = final_ranger_fit)

train_class <- colnames(train_preds)[max.col(train_preds, ties.method = "first")]

train_class<-as_tibble(train_class) %>%
  rename(.pred_class=value) %>%
  mutate(.pred_class=str_remove(.pred_class,".pred_" ) # Removes all matches
  )

train_class<-train_class %>%
  mutate(.pred_class=factor(.pred_class)) %>%
  mutate(.pred_class=fct_relevel(.pred_class,class_levels)
  )

# Bind cols
train_data<-bind_cols(train_class,train_preds,train_data)

train_data<-train_data%>%
  mutate(weighting=hardhat::frequency_weights(lndlb)) 

############ 
# uncount the data and then do the ROC curve

train_data_uncount<- train_data  %>%
  uncount(weights = weighting)

# pull the probability names
prob_names<-colnames(train_data_uncount) 
prob_names<-grep("^\\.pred_", prob_names, value=TRUE)
prob_names<-grep("^\\.pred_class", prob_names, value=TRUE, invert=TRUE)

roc_training_set<-test_data_uncount %>%
  roc_curve(truth=market_desc, 
            any_of(prob_names)
  ) %>% autoplot()


roc_training_set


# --- 5. Save at ICES JMS specifications ---
ggsave(here("results","ranger","tune",glue("roc_training_dataset_{modeltype}{finalfit_vintage}.pdf")),
       plot   = roc_training_set,
       width  = 174,   # mm — double-column, suits 4 facets in a row
       height = 65,
       units  = "mm",
       device = cairo_pdf)













################################################################################
# Generate class-probability predictions on the test set via the custom
# predict_byhand() wrapper (applies prepped_recipe before calling ranger).
# The modal predicted class is extracted by finding the column with the highest
# probability for each row, then bound back alongside the raw probabilities
# and original validation data.


class_levels <- c("Jumbo", "Large", "Medium", "Small")
test_preds<-predict_byhand(new_data=test_data,
                          prepped_recipe = prepped_recipe,
                            ranger_fitted_model  = final_ranger_fit)

test_class <- colnames(test_preds)[max.col(test_preds, ties.method = "first")]

test_class<-as_tibble(test_class) %>%
  rename(.pred_class=value) %>%
  mutate(.pred_class=str_remove(.pred_class,".pred_" ) # Removes all matches
  )

test_class<-test_class %>%
  mutate(.pred_class=factor(.pred_class)) %>%
  mutate(.pred_class=fct_relevel(.pred_class,class_levels)
  )

# Bind cols
test_data<-bind_cols(test_class,test_preds,test_data)

test_data<-test_data%>%
  mutate(weighting=hardhat::frequency_weights(lndlb)) 






############ 
# uncount the data and then do the ROC curve


test_data_uncount<- test_data  %>%
  uncount(weights = weighting)



#rm(tune_res)

# pull the probability names
prob_names<-colnames(test_data_uncount) 
prob_names<-grep("^\\.pred_", prob_names, value=TRUE)
prob_names<-grep("^\\.pred_class", prob_names, value=TRUE, invert=TRUE)

roc_data<-test_data_uncount %>%
  roc_curve(truth=market_desc, 
            any_of(prob_names)
  )

# --- 3. Colour palette — four classes ---

class_colours <- c(
  "Jumbo"  = "#1B6CA8",   # deep blue
  "Large"  = "#E05C2A",   # burnt orange
  "Medium" = "#2E8B57",   # sea green
  "Small"  = "#7B3F9E"    # purple
)

roc_mean <- roc_data %>%
  group_by(.level, specificity) %>%
  summarise(sensitivity = mean(sensitivity), .groups = "drop")


# --- 4. Build the figures ---
p_facet <- ggplot(roc_data,
                  aes(x = 1 - specificity, y = sensitivity)) +
  geom_abline(slope = 1, intercept = 0,
              linetype = "dashed", colour = "grey50", linewidth = 0.4) +
  geom_path(aes(colour = .level, group = interaction(.level, id)),
            linewidth = 0.8, alpha = 1, show.legend = FALSE) +
#  geom_path(data = roc_mean,
 #        aes(colour = "grey92"),
  #      linewidth = 0.25, alpha = 1.0, show.legend = FALSE) +
  facet_wrap(~ .level, ncol = 4) +
  scale_colour_manual(values = class_colours) +
  scale_x_continuous(
    name   = "1 \u2212 Specificity (False Positive Rate)",
    limits = c(0, 1),
    breaks = seq(0, 1, 0.25),
    expand = expansion(mult = 0.01)
  ) +
  scale_y_continuous(
    name   = "Sensitivity (True Positive Rate)",
    limits = c(0, 1),
    breaks = seq(0, 1, 0.25),
    expand = expansion(mult = 0.01)
  ) +
  coord_equal() +
  theme_bw(base_size = 9) +
  theme(
    strip.background = element_rect(fill = "grey92", colour = "grey40"),
    strip.text       = element_text(size = 8, face = "bold"),
    panel.grid.major = element_line(colour = "grey88", linewidth = 0.3),
    panel.grid.minor = element_blank(),
    axis.title       = element_text(size = 8),
    axis.text        = element_text(size = 7, colour = "grey20"),
    plot.margin      = margin(4, 6, 4, 4, "pt")
  )
# --- 5. Save at ICES JMS specifications ---
ggsave(here("results","ranger","tune",glue("roc_testing_dataset_{modeltype}{finalfit_vintage}.pdf")),
       plot   = p_facet,
       width  = 174,   # mm — double-column, suits 4 facets in a row
       height = 65,
       units  = "mm",
       device = cairo_pdf)




cat("plot_ROC_curves.R completed successfully.")



