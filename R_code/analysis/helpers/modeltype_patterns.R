# set data patterns based on modeltype

if(search_type=="Prototype"){
  modeltype=glue("TEST{modeltype}")
}

# You've estimated a few difference models, this sets the 

if (modeltype=="standard"){
  data_pattern<-"data_split"
  tuning_pattern<-"BSB_ranger_tune"
  final_pattern<-"BSB_ranger_results"
  vi_pattern<-glue("BSB_ranger_VI")
  best_param_pattern<-glue("BSB_ranger_best_params")
  
  
} else if (modeltype=="nocluster"){
  data_pattern<-"nocluster_data_split"
  tuning_pattern<-"BSB_ranger_nocluster_tune"
  final_pattern<-"BSB_ranger_nocluster_results"
  vi_pattern<-glue("BSB_ranger_nocluster_VI")
  best_param_pattern<-glue("BSB_ranger_nocluster_best_params")
  
} else if (modeltype=="TESTnocluster"){
  data_pattern<-"TEST_nocluster_data_split"
  tuning_pattern<-"TEST_BSB_ranger_nocluster_tune"
  final_pattern<-"TEST_BSB_ranger_nocluster_results"
  vi_pattern<-"TEST_BSB_ranger_nocluster_VI"
  best_param_pattern<-glue("TEST_BSB_ranger_nocluster_best_params")
  
}else {
  stop("Unknown modeltype")
}

