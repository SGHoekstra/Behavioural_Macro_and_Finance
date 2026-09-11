import BeforeIT as Bit
using Dates
using DelimitedFiles
using Statistics
using Printf
using LaTeXStrings
using CSV
using HDF5
using JLD2
using FileIO
using MAT
using StatsBase
using StatsPlots
using Statistics

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
number_years = 2
number_quarters = 4 * number_years
quarters_num = []
year_m = year_
max_year = 2019

for month in 4:3:((number_years + 1) * 12 + 1)

    global year_m = year_ + (month ÷ 12)
    mont_m = month % 12
    date = DateTime(year_m, mont_m, 1) - Day(1)

    push!(quarters_num, Bit.date2num(date))

end
horizon = 30
number_variables = 4
number_of_seeds = 10


data = matread(("./src/utils/" * "calibration_data/" * nation * "/data/1996.mat"))
data = data["data"]


cycles = fill(NaN, number_quarters, number_of_seeds, horizon + 1, number_variables)
actual = fill(NaN, number_quarters, number_of_seeds, horizon + 1, number_variables)

country = "netherlands_households_own_firms"

#model_type = "base"
#model_type = "extended_heuristic"
model_type = "optimal_consumption"

calibration_type = "calibrated"
#calibration_type = "empirical"

unconditional_forecasts = false
abmx = true

# Define the list of cycle names as an array of strings
fn = [
    "real_capitalformation_quarterly", 
    "wages_quarterly", 
    "real_household_consumption_quarterly", 
    "operating_surplus_quarterly",
    "gdp_deflator_quarterly",
    "real_gdp_quarterly"
]
data["gdp_deflator_quarterly"] = 1 ./ data["gdp_deflator_quarterly"]

# Initialize trends and cycles as dictionaries
trends = Dict{String, Matrix{Float64}}()
cycles = Dict{String, Matrix{Float64}}()
series = Dict{String, Matrix{Float64}}()
series_std = Dict{String, Float64}()
data_std = Dict{String, Float64}()

lambda = 1600 # Recommended value for lambda for quarterly data

# Loop over each cycle name
for n = eachindex(fn)
    # Initialize zero matrices for each cycle name
    trends[fn[n]] = zeros(horizon+1, number_quarters * number_of_seeds)
    cycles[fn[n]] = zeros(horizon+1, number_quarters * number_of_seeds)
    series[fn[n]] = zeros(horizon+1, number_quarters * number_of_seeds)
    series_std[fn[n]] = 0.0
    data_std[fn[n]] = 0.0
end

filename = "predictions"* (abmx ? "_abmx" : "_abm")*(unconditional_forecasts ? "_uf" : "")*"_lr"

# Loop over each column
for i in 1:number_quarters
    quarter_num = quarters_num[i]

    global model = load("./src/utils/data/" * country * "/" *model_type * "/" * calibration_type * "/" * filename * "/" * string(year(Bit.num2date(quarter_num))) * "Q" * string(Dates.quarterofyear(Bit.num2date(quarter_num))) *".jld2","model_dict");
    for n = eachindex(fn)
        data_col = model[fn[n]]

        for j = 1 : number_of_seeds
            trends[fn[n]][:, (i-1) * number_of_seeds + j ], cycles[fn[n]][:, (i-1) * number_of_seeds + j ] = Bit.hpfilter_with_cycle(data_col[:,j], lambda, true)
            cycles[fn[n]][:, (i-1) * number_of_seeds + j ] = cycles[fn[n]][:, (i-1) * number_of_seeds + j ]./trends[fn[n]][:, (i-1) * number_of_seeds + j ]
            series[fn[n]][:, (i-1) * number_of_seeds + j ] = data_col[:,j]
        end
    end

end

# Create subplots with titles, ensuring they fit properly and have the same y-axis scale
p1 = plot(cycles["real_gdp_quarterly"][1:20,1:10], title="Real GDP (De-trended)", xlabel="Time", ylabel="Value", legend=false, ylim=(-0.15, 0.15));
p2 = plot(cycles["gdp_deflator_quarterly"][1:20,1:10], title="GDP Deflator Growth (De-trended)", xlabel="Time", ylabel="Value", legend=false, ylim=(-0.15, 0.15));
p3 = plot(cycles["real_household_consumption_quarterly"][1:20,1:10], title="Real Household Consumption (De-trended)", xlabel="Time", ylabel="Value", legend=false, ylim=(-0.15, 0.15));
p4 = plot(cycles["real_capitalformation_quarterly"][1:20,1:10], title="Real Capital Formation (De-trended)", xlabel="Time", ylabel="Value", legend=false, ylim=(-0.15, 0.15));


# Arrange the plots in a 2x2 grid layout
cycles_plot = plot(p1, p2, p3, p4, layout=(2, 2), size=(800, 600), titlefontsize=8)


# Initialize dictionaries to store the matrices
crosscorr_model = Dict{String, Matrix{Float64}}()
autocorr_model = Dict{String, Matrix{Float64}}()
crosscorr_data = Dict{String, Vector{Float64}}()
autocorr_data = Dict{String, Vector{Float64}}()
plot_dict_autocor = Dict{String, Plots.Plot{Plots.GRBackend}}()
plot_dict_crosscor = Dict{String, Plots.Plot{Plots.GRBackend}}()

for n = eachindex(fn)
    crosscorr_model[fn[n]] = zeros(horizon+1,number_of_seeds * number_quarters)
    autocorr_model[fn[n]] =  zeros(20,number_of_seeds * number_quarters)
    crosscorr_data[fn[n]] = zeros(horizon+1)
    autocorr_data[fn[n]] = zeros(20)
end
#TODO Apply bootstrap or rolling estimate of autocorrelation function
# Loop over the function names
gdpsize = size(model["real_gdp_quarterly"]);

for i in 1:number_quarters
    quarter_num = quarters_num[i]

    global model = load("./src/utils/data/" * country * "/" *model_type *  "/" * calibration_type *  "/" * filename * "/" * string(year(Bit.num2date(quarter_num))) * "Q" * string(Dates.quarterofyear(Bit.num2date(quarter_num))) *".jld2","model_dict");
    for n = eachindex(fn)
        for j in 1:number_of_seeds
            data_col = model[fn[n]][:,j]
            if fn[n] == "gdp_deflator_quarterly"
                data_col = 1 ./ data_col
            end
            gdptrend, gdpcycle = Bit.hpfilter_with_cycle(model["real_gdp_quarterly"][:,j], lambda, true);
            trend, cycle = Bit.hpfilter_with_cycle(data_col, lambda, true)

            #cyclesvar[fn[n]][(i - 1) * number_of_seeds + j]  = std(data_col)
            crosscorr_model[fn[n]][:, (i - 1) * number_of_seeds + j] = crosscor(cycle,gdpcycle,Vector(-15:1:15))
            autocorr_model[fn[n]][:,(i - 1) * number_of_seeds + j] = autocor(cycle,Vector(1:20))
        end
    end

end

for n = eachindex(fn)
    data_col = data[fn[n]]

    gdptrend, gdpcycle = Bit.hpfilter_with_cycle(vec(data["real_gdp_quarterly"]), lambda, true);
    trend, cycle = Bit.hpfilter_with_cycle(vec(data_col), lambda, true)

    crosscorr_data[fn[n]] = crosscor(cycle,gdpcycle,Vector(-15:1:15))
    autocorr_data[fn[n]]= autocor(cycle,Vector(1:20))
end

function format_title(title::String)
    # Remove underscores and capitalize each word
    return uppercasefirst(replace(title, "_" => " "))
end

counter = 1
for n = eachindex(fn)
    if counter == 1
        p = errorline(Vector(-15:1:15),crosscorr_model[fn[n]], errorstyle=:stick, title=format_title(fn[n]), label = "model",legend=false);
    else
        p = errorline(Vector(-15:1:15),crosscorr_model[fn[n]], errorstyle=:stick, title=format_title(fn[n]), label = "model",legend=false);
    end
    plot!(Vector(-15:1:15),crosscorr_data[fn[n]], label = "data");

    plot_dict_crosscor[fn[n]] = p
    counter+=1
end

counter = 1

for n = eachindex(fn)
    if counter == 1
        p = errorline(autocorr_model[fn[n]], errorstyle=:stick, title=format_title(fn[n]), label = "model",legend=false);
    else
        p = errorline(autocorr_model[fn[n]], errorstyle=:stick, title=format_title(fn[n]), label = "model",legend=false);
    end
    plot!(autocorr_data[fn[n]], label = "data");

    plot_dict_autocor[fn[n]] = p
    counter+=1
end



# Extract the first four plots from the dictionary
plots_to_display = collect(values(plot_dict_crosscor))

# Arrange the extracted plots in a 2x2 grid layout

crosscorr_plot =plot(plots_to_display..., layout=(2, 3), size=(1200, 800), titlefontsize=8)

# Extract the first four plots from the dictionary
plots_to_display = collect(values(plot_dict_autocor))
# Arrange the extracted plots in a 2x2 grid layout

autocorr_plot = plot(plots_to_display..., layout=(2, 3), size=(1200, 800), titlefontsize=8)


file_appendix = (abmx ? "_abmx" : "_abm")*(unconditional_forecasts ? "_uf" : "")


savefig(autocorr_plot, pwd() * "/analysis/figs/" *model_type *  "/" * calibration_type * "/autocorr" * file_appendix * ".svg");
savefig(crosscorr_plot, pwd() * "/analysis/figs/" *model_type *  "/" * calibration_type *  "/crosscorr" * file_appendix * ".svg");
savefig(cycles_plot, pwd() * "/analysis/figs/" *model_type *  "/" * calibration_type *  "/cycles" * file_appendix * ".svg");

for n = eachindex(fn)
    data_trend, data_cycle = Bit.hpfilter_with_cycle(vec(data[fn[n]]), lambda, true)
    data_cycle = data_cycle./data_trend
    data_std[fn[n]] = std(data_cycle)

    series_std[fn[n]] = mean(std(cycles[fn[n]][1:20,:],dims =1))
end

