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
number_years = 7
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
number_variables = 5
presample = 4


data = matread(("./src/utils/" * "calibration_data/" * nation * "/data/1996.mat"))
data = data["data"]

for k = 1:3

    global forecast = fill(NaN, number_quarters, number_horizons, number_variables)
    global actual = fill(NaN, number_quarters, number_horizons, number_variables)

    for i in 1:number_quarters
        quarter_num = quarters_num[i]

        for j in 1:number_horizons
            global horizon = horizons[j]
            forecast_quarter_num = BIT.date2num(lastdayofmonth(BIT.num2date(quarter_num) + Month(3 * horizon)))

            if BIT.num2date(forecast_quarter_num) > Date(max_year, 12, 31)
                break
            end

            actual[i, j, :] = hcat(collect([
                log.(data["real_gdp_quarterly"][data["quarters_num"] .== forecast_quarter_num]),
                log.(1 .+ data["gdp_deflator_growth_quarterly"][data["quarters_num"] .== forecast_quarter_num]),
                log.(data["real_household_consumption_quarterly"][data["quarters_num"] .== forecast_quarter_num]),
                log.(data["real_fixed_capitalformation_quarterly"][data["quarters_num"] .== forecast_quarter_num]),
                (1 .+ data["euribor"][data["quarters_num"] .== forecast_quarter_num]).^(1/4)
                ])...)

            X = hcat(collect([
                log.(data["real_exports_quarterly"][data["quarters_num"] .<= forecast_quarter_num]),
                log.(data["real_imports_quarterly"][data["quarters_num"] .<= forecast_quarter_num]),
                log.(data["real_government_consumption_quarterly"][data["quarters_num"] .<= forecast_quarter_num])
                ])...)

            Y0 = hcat(collect([
                log.(data["real_gdp_quarterly"][data["quarters_num"] .<= quarter_num]),
                log.(data["gdp_deflator_quarterly"][data["quarters_num"] .<= quarter_num]),
                log.(data["real_household_consumption_quarterly"][data["quarters_num"] .<= quarter_num]),
                log.(data["real_fixed_capitalformation_quarterly"][data["quarters_num"] .<= quarter_num]),
                cumsum((1 .+ data["euribor"][data["quarters_num"] .<= quarter_num]).^(1/4))
            ])...)

            Y = zeros(horizon, number_variables)

            Y0_diff = diff(Y0[presample - k:end,:]; dims = 1)
            X_diff = diff(X[presample - k:end,:]; dims = 1)

            for l in 1:number_variables
                Y[:,l] = BIT.forecast_k_steps_VARX(Y0_diff[:,l], X_diff, horizon, intercept = true, lags = k)
            end

            Y[end, [1, 3, 4]] = Y0[end, [1, 3, 4]]' + sum(Y[:, [1, 3, 4]], dims=1)
            forecast[i, j, :] = Y[end, :]
        end
    end

    if k == 1
        h5open(dir * "/forecast_arx.h5", "w") do file
            write(file, "forecast", forecast)
        end
        rmse_arx = dropdims(100 * sqrt.(nanmean((forecast - actual).^2,1)), dims=1)
        bias_arx = dropdims(nanmean(forecast - actual, 1), dims=1)
        error_arx = forecast - actual
    else
        h5open(dir * "/forecast_arx_$(k).h5", "w") do file
            write(file, "forecast", forecast)
        end
        rmse_arx_k = dropdims(100 * sqrt.(nanmean((forecast - actual).^2,1)), dims=1)
        bias_arx_k = dropdims(nanmean(forecast - actual, 1), dims=1)
        error_arx_k = forecast - actual

        forecast = h5read(dir * "/forecast_arx.h5","forecast")
        rmse_arx = dropdims(100 * sqrt.(nanmean((forecast - actual).^2,1)), dims=1)
        error_arx = forecast - actual
    end


    if k == 1
        global input_data = round.(rmse_arx, digits=2)
        global input_data_S = string.(input_data)
    else
        input_data = - round.(100 * (rmse_arx .- rmse_arx_k) ./ rmse_arx, digits=1)
        input_data_S = fill("", size(input_data))
        for j in 1:length(horizons)
            h = horizons[j]
            for l in 1:number_variables
                dm_error_arx_k = view(error_arx_k, :, j, l)[map(!,isnan.(view(error_arx_k, :, j, l)))]
                dm_error_arx = view(error_arx, :, j, l)[map(!,isnan.(view(error_arx, :, j, l)))]
                _, p_value = BIT.dmtest_modified(dm_error_arx,dm_error_arx_k, h)
                input_data_S[j, l] = string(input_data[j, l]) * "(" * string(round(p_value, digits=2)) *", "* string(stars(p_value)) * ")"
            end
        end
    end

    global tableRowLabels = ["1q", "2q", "4q", "8q", "12q"]
    global dataFormat = "%.2f"
    global tableColumnAlignment = "r"
    global tableBorders = false
    global booktabs = false
    global makeCompleteLatexDocument = false
    
    global latex = BIT.latexTableContent(input_data_S, tableRowLabels, dataFormat, tableColumnAlignment, tableBorders, booktabs, makeCompleteLatexDocument)

    if k == 1
        open(dir * "/rmse_arx.tex", "w") do fid
            for line in latex
                write(fid, line * "\n")
            end
        end
    else
        open(dir * "/rmse_arx_$(k).tex", "w") do fid
            for line in latex
                write(fid, line * "\n")
            end
        end
    end
    
    if k == 1
        input_data = round.(bias_arx, digits=4)
        input_data_S = fill("", size(input_data))

        for j in 1:length(horizons)
            
            h = horizons[j]
            for l in 1:number_variables
                mz_forecast = (view(error_arx, :, j, l) + view(actual, :, j, l))[map(!,isnan.(view(error_arx, :, j, l) + view(actual, :, j, l)))]
                mz_actual = view(actual, :, j, l)[map(!,isnan.(view(actual, :, j, l)))]
                _, _, p_value = BIT.mztest(mz_actual, mz_forecast)
                input_data_S[j, l] = string(input_data[j, l]) * " (" * string(round(p_value, digits=3)) *", "* stars(p_value) * ")"
            end
        end
        
        latex = BIT.latexTableContent(input_data_S, tableRowLabels, dataFormat, tableColumnAlignment, tableBorders, booktabs, makeCompleteLatexDocument)

        open(dir * "/bias_arx.tex", "w") do fid
            for line in latex
                write(fid, line * "\n")
            end
        end
    
    end
end
