# This scripts calls all scripts to create tables for comparing forecasts of the abm and the baseline models (AR, ARX, VAR, VARX)

# Clear old files
foreach(rm, filter(endswith(".h5"), readdir("./analysis/tabs/",join=true)))
foreach(rm, filter(endswith(".tex"), readdir("./analysis/tabs/",join=true)))

#model_type = "base"
#model_type = "extended_heuristic"
model_type = "optimal_consumption"

#distribution_type = "calibrated"
distribution_type = "empirical"


foreach(rm, filter(endswith(".h5"), readdir("./analysis/tabs/" * model_type * "/" * distribution_type, join=true)))
foreach(rm, filter(endswith(".tex"), readdir("./analysis/tabs/" * model_type * "/" * distribution_type, join=true)))

# Unconditional forecasts
include("error_table_ar.jl")
include("error_table_abm.jl")
include("error_table_ar_nace10.jl") 
include("error_table_abm_nace10.jl") 
include("error_table_validation_var.jl")
include("error_table_validation_abm.jl")
include("error_table_var_nace10.jl")
include("error_table_abm_nace10_var.jl") 

# Conditional forecast
include("error_table_arx.jl")
include("error_table_abmx.jl") 
include("error_table_abmx_uf.jl") 
include("error_table_validation_varx.jl")
include("error_table_validation_abmx.jl")
include("error_table_validation_abmx_uf.jl")