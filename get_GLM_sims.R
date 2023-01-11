library(GLM3r)
library(glmtools)
library(reshape2)
library(dplyr)

# you need to be in this dir
# setwd("C:/Users/Maike/Box Sync/DEEP_LEARNING/SurrogateModeling/Important_code/GLM_related/GLM/NOAA_forecast_GLM")

# function to make MONTH/DAY/DOY dataframe for merging w/ GLM sims
make_ymd = function(){
  month_table = data.frame(MONTH = 1:12, freq = c(31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31))
  MONTH = rep(1:12, month_table$freq)
  DAY = unlist(Map(function(start_num, stop_num) seq(start_num,stop_num ),1,month_table$freq ))
  DOY = 1:366
  ymd = data.frame(MONTH = MONTH, DAY = DAY, DOY = DOY)
}


# need this to handle errors due to glmtools not being able to interpolate or something
check_GLM_output <- function(nml_file, output_file){
  tryCatch(
    # This is what I want to do...
    {
      surface_temp = glmtools::get_var(file = output_file,
                                       var_name = "temp",
                                       reference = "surface",
                                       z_out = nml_file$init_profiles$the_depths)
      return(surface_temp)
    },
    # ... but if an error occurs, tell me what happened: 
    error=function(error_message) {
      message("glmtools is being dumb and doesn't want to interpolate temps to depths! Skipping this 
              ensemble member.")

      return(NA)
    }
  )
}


#curr_results_dir = "Results1"
# if hourly = TRUE, then .nml file is saving every hour, so we average over hour
# if hourly = FALSE, then .nml specifies saving one hour per day, so no averaging
get_GLM_sims = function(curr_results_dir, hourly = TRUE, coeff_list, initial_temps, start_date = NULL){
  Kw = coeff_list$Kw
  coeff_mix_hyp = coeff_list$coeff_mix_hyp
  sw_factor = coeff_list$sw_factor
  lw_factor = coeff_list$lw_factor
  sed_temp_mean = coeff_list$sed_temp_mean
 # initial_temps = inputs_param_list$initial_temps
  
 # initial_temps = initial_temps not sure how to work this in yet
  
  if (hourly){
    print("hourly simulations--will average over hour")
  }
  ymd = make_ymd()
  df = data.frame()
  for (i in 1:30){
    GLM_sim_dir = paste0("GLM_sim_", i)
    output_file = file.path(curr_results_dir, GLM_sim_dir, "output/output.nc", sep = "")
    nml_file = read_nml(nml_file = file.path(curr_results_dir, GLM_sim_dir, "glm3.nml", sep = ""))
    
    surface_temp = check_GLM_output(nml_file, output_file)
    if (!is.data.frame(surface_temp)){
      next
    }else{
    
    # surface_temp = glmtools::get_var(file = output_file,
    #                        var_name = "temp",
    #                        reference = "surface",
    #                        z_out = nml_file$init_profiles$the_depths)
    surface_melt = reshape2::melt(surface_temp, id.vars = "DateTime")
    colnames(surface_melt)[2:3] = c("depth_int", "Temp_C")
    surface_melt$ensemble_number = i
    x = surface_melt$depth
    levels(x) = as.character(0:9) 
    x_char = as.character(x)
    x_int = as.numeric(x_char)
    surface_melt$depth_int = x_int
    date_time = surface_melt$DateTime
    Date_char = gsub("\\s+\\d{1,2}:\\d{1,2}:\\d{1,2}", "", date_time)
    Date_char = strsplit(Date_char, "-")
    dates_df = as.data.frame(do.call("rbind", Date_char))
    names(dates_df) = c("YEAR", "MONTH", "DAY")
    dates_df$YEAR = as.numeric(dates_df$YEAR)
    dates_df$MONTH = as.numeric(dates_df$MONTH)
    dates_df$DAY = as.numeric(dates_df$DAY)
    surface_melt = cbind(surface_melt, dates_df)
    surface_melt = dplyr::right_join(ymd, surface_melt, by = c("MONTH", "DAY"))
  
    df = rbind(df, surface_melt)
    }
  }

  if (hourly == TRUE){
    sim_aves = df %>% group_by(ensemble_number, YEAR, MONTH, DAY, depth_int) %>%
      summarise(mean_Temp_C = mean(Temp_C))
    sim_aves = dplyr::right_join(ymd, sim_aves, by = c("MONTH", "DAY"))
    sim_aves_wide = sim_aves #%>%
    #tidyr::pivot_wider(names_from = ensemble_number, values_from = mean_Temp_C) 
    #colnames(sim_aves_wide)[6:36] = paste0("ensemble_member_",1:31)
    
    sim_aves_wide$Kw = Kw
    sim_aves_wide$coeff_mix_hyp = coeff_mix_hyp
    sim_aves_wide$sw_factor = sw_factor
    sim_aves_wide$lw_factor = lw_factor
    sim_aves_wide$sed_temp_mean_1 = sed_temp_mean[1]
    sim_aves_wide$sed_temp_mean_2 = sed_temp_mean[2]
    init_sim_wide = data.frame(matrix(rep(initial_temps, each = nrow(sim_aves_wide)), 
                                     ncol = length(initial_temps)))
    colnames(init_sim_wide) = paste0("init",0:9)
    sim_aves_wide = cbind(sim_aves_wide, init_sim_wide)
    sim_aves_wide$start_date = start_date
    # 
   
    df_wide = df #%>% tidyr::pivot_wider(names_from = ensemble_number, values_from = Temp_C) 
    #colnames(df_wide)[7:37] = paste0("ensemble_member_",1:31)
    df_wide$Kw = Kw
    df_wide$coeff_mix_hyp = coeff_mix_hyp
    df_wide$sw_factor = sw_factor
    df_wide$lw_factor = lw_factor
    df_wide$sed_temp_mean_1 = sed_temp_mean[1]
    df_wide$sed_temp_mean_2 = sed_temp_mean[2]
    
    init_df_wide = data.frame(matrix(rep(initial_temps, each = nrow(df_wide)), 
                                    ncol = length(initial_temps)))
    colnames(init_df_wide) = paste0("init",0:9)
    df_wide = cbind(df_wide, init_df_wide)
    df_wide$start_date = start_date
    
    return(list(df_wide = df_wide, sim_aves_wide = sim_aves_wide))
  }else{
    
    df_wide = df# %>% tidyr::pivot_wider(names_from = ensemble_number, values_from = Temp_C) 
    #colnames(df_wide)[7:37] = paste0("ensemble_member_",1:31)
    df_wide$Kw = Kw
    df_wide$coeff_mix_hyp = coeff_mix_hyp
    df_wide$sw_factor = sw_factor
    df_wide$lw_factor = lw_factor
    df_wide$sed_temp_mean_1 = sed_temp_mean[1]
    df_wide$sed_temp_mean_2 = sed_temp_mean[2]
    init_df_wide = data.frame(matrix(rep(initial_temps, each = nrow(df_wide)), 
                                     ncol = length(initial_temps)))
    colnames(init_df_wide) = paste0("init",0:9)
    df_wide = cbind(df_wide, init_df_wide)
    df_wide$start_date = start_date
    return(list(df = df, df_wide = df_wide))
  }
}


