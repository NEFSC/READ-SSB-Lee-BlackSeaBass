# set data patterns based on modeltype
# You've estimated a few difference models, this sets the 

if (modeltype=="standard"){
  data_pattern<-"data_split"
  tuning_pattern<-"BSB_ranger_tune"
  final_pattern<-"BSB_ranger_results"
  vi_pattern<-glue("BSB_ranger_nocluster")
  
} else if (modeltype=="nocluster"){
  data_pattern<-"nocluster_data_split"
  tuning_pattern<-"BSB_ranger_nocluster_tune"
  final_pattern<-"BSB_ranger_nocluster_results"
  vi_pattern<-glue("BSB_ranger_nocluster_VI")
  
} else if (modeltype=="noclusterTEST"){
  data_pattern<-"nocluster_data_split_TEST"
  tuning_pattern<-"BSB_ranger_nocluster_tune_TEST"
  final_pattern<-"BSB_ranger_nocluster_results_TEST"
  vi_pattern<-glue("BSB_ranger_nocluster_VI_TEST")
  
}else {
  stop("Unknown modeltype")
}

