import BeforeIT as BIT
using Dates
using DelimitedFiles
using Statistics
using Printf
using LaTeXStrings
using CSV
using HDF5
using FileIO
using MAT

nanmean(x) = mean(filter(!isnan,x))
nanmean(x,y) = mapslices(nanmean,x; dims = y)

# Helper functions for LaTeX table creation and stars notation
function stars(p_value)
    if p_value < 0.01
        return "***"
    elseif p_value < 0.05
        return "**"
    elseif p_value < 0.1
        return "*"
    else
        return ""
    end
end


dir = @__DIR__

nation = "netherlands"

# Load calibration data (with figaro input-output tables)


year_ = 2010
number_years = 10
number_quarters = 4 * number_years
quarters_num = []
year_m = year_
max_year = 2019

for month in 4:3:((number_years + 1) * 12 + 1)

    global year_m = year_ + (month ÷ 12)
    mont_m = month % 12
    date = DateTime(year_m, mont_m, 1) - Day(1)

    push!(quarters_num, BIT.date2num(date))

end
horizons = [1, 2, 4, 8, 12]
number_horizons = length(horizons)
number_variables = 10
presample = 4


data = matread(("./src/utils/" * "calibration_data/" * nation * "/data/1996.mat"))
data = data["data"]

country = "netherlands_households_own_firms"

if !@isdefined model_type
    model_type = "base"
end
if !@isdefined distribution_type
    distribution_type = "calibrated"
end
forecast = fill(NaN, number_quarters, number_horizons, number_variables)
actual = fill(NaN, number_quarters, number_horizons, number_variables)


quarter_num = quarters_num[1]
model = load("./src/utils/data/" * country * "/" * model_type* "/" * distribution_type *"/predictions_abm/" * string(year(BIT.num2date(quarter_num))) * "Q" * string(Dates.quarterofyear(BIT.num2date(quarter_num))) *".jld2","model_dict");
number_of_seeds = size(model["real_gdp_quarterly"],2)

for i in 1:number_quarters
    quarter_num = quarters_num[i]

    global model = load("./src/utils/data/" * country * "/" * model_type* "/" * distribution_type *"/predictions_abm/" * string(year(BIT.num2date(quarter_num))) * "Q" * string(Dates.quarterofyear(BIT.num2date(quarter_num))) *".jld2","model_dict");

    for j in 1:number_horizons
        horizon = horizons[j]
        forecast_quarter_num = BIT.date2num(lastdayofmonth(BIT.num2date(quarter_num) + Month(3 * horizon)))

        if BIT.num2date(forecast_quarter_num) > Date(max_year, 12, 31)
            break
        end

        actual[i, j, :] = log.(data["nominal_nace10_gva_quarterly"][repeat(data["quarters_num"] .== forecast_quarter_num,1,10)])

        forecast[i, j, :] = log.(mean(reshape(model["nominal_nace10_gva_quarterly"][repeat(model["quarters_num"] .== forecast_quarter_num,1,number_of_seeds,10)],(number_of_seeds,10)),dims = 1))

        
    end
end

h5open(dir * "/" * model_type* "/" * distribution_type *"/forecast_abm_nace10.h5", "w") do file
    write(file, "forecast", forecast)
end

rmse_abm_nace10 = dropdims(100 * sqrt.(nanmean((forecast - actual).^2,1)), dims=1)
bias_abm_nace10 = dropdims(nanmean(forecast - actual, 1), dims=1)
error_abm_nace10 = forecast - actual

file_path = dir * "/forecast_var_nace10.h5"
forecast = h5open(file_path, "r") do file
    forecast = read(file["forecast"])
end

rmse_var_nace10 = dropdims(100 * sqrt.(nanmean((forecast - actual).^2,1)), dims=1)
error_var_nace10 = forecast - actual



input_data = - round.(100 * (rmse_abm_nace10 .- rmse_var_nace10) ./ rmse_var_nace10, digits=1)
input_data_S = fill("", size(input_data))

for j in 1:length(horizons)
    h = horizons[j]
    for l in 1:number_variables
        dm_error_abm_nace10 = view(error_abm_nace10, :, j, l)[map(!,isnan.(view(error_abm_nace10, :, j, l)))]
        dm_error_var_nace10 = view(error_var_nace10, :, j, l)[map(!,isnan.(view(error_var_nace10, :, j, l)))]
        _, p_value = BIT.dmtest_modified(dm_error_abm_nace10,dm_error_var_nace10, h)
        input_data_S[j, l] = string(input_data[j, l]) * "(" * string(round(p_value, digits=2)) *", "* string(stars(p_value)) * ")"
    end
end

tableRowLabels = ["1q", "2q", "4q", "8q", "12q"]
dataFormat = "%.2f"
tableColumnAlignment = "r"
tableBorders = false
booktabs = false
makeCompleteLatexDocument = false

latex = BIT.latexTableContent(input_data_S, tableRowLabels, dataFormat, tableColumnAlignment, tableBorders, booktabs, makeCompleteLatexDocument)

open(dir * "/" * model_type* "/" * distribution_type *"/rmse_abm_nace10_var.tex", "w") do fid
    for line in latex
        write(fid, line * "\n")
    end
end


