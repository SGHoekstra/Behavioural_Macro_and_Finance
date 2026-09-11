using BeforeIT
using MAT, FileIO, Plots, StatsPlots
using Dates

# load data from 1996

real_data = BeforeIT.NETHERLANDS_CALIBRATION.data

# load predictions from 2010Q1
#year_i = 2014
#quarter = 1

year_i = 2014
quarter = 4


model_type = "base"
#model_type = "extended_heuristic"
#model_type = "optimal_consumption"
benchmark_model_type = "arx"

model = load("./src/utils/data/netherlands_households_own_firms/"* model_type * "/abmx_predictions/" * string(year_i) * "Q" * string(quarter) * ".jld2")["model_dict"]
benchmark_model = load("./src/utils/data/netherlands_households_own_firms/"* benchmark_model_type * "/" *string(year_i) * "Q" * string(quarter) * ".jld2")["model_dict"]


function plot_model_vs_real(model, real, varname; crop = true, scale = 1e6, title_overload = missing, benchmark_model = missing)

    if length(varname) > 9
        if varname[(end - 8):end] == "quarterly"
            x_nums = "quarters_num"
            title = varname[1:(end - 10)]
        else
            x_nums = "years_num"
            title = varname
        end
    else
        x_nums = "years_num"
        title = varname
    end

    if !ismissing(title_overload)
        title = title_overload
    end

    if crop
        min_x = minimum(model[x_nums])
        max_x = maximum(model[x_nums])
        xlimits = (min_x, max_x)
        min_y = minimum(real[varname][min_x .<= real[x_nums] .<= max_x])
        max_y = maximum(real[varname][min_x .<= real[x_nums] .<= max_x])
        min_y = minimum((min_y, minimum(model[varname]))) * 0.95
        max_y = maximum((max_y, maximum(model[varname]))) * 1.05
        ylimits = (min_y, max_y) .* scale
    else
        ylimits = :auto
        xlimits = :auto
    end


    if crop
        all_tick_numbers = model[x_nums]
    else
        all_tick_numbers = real[x_nums]
    end


    num_ticks = []
    year_ticks = []
    for r in all_tick_numbers
        # get year of r
        y = year(BeforeIT.num2date(r))
        # save year only if it's new
        if !(y in year_ticks)
            push!(num_ticks, r)
            push!(year_ticks, y)
        end
    end


    p = plot(
        real[x_nums],
        scale * real[varname],
        label = "real",
        title = title,
        titlefontsize = 12,
        xlimits = xlimits,
        ylimits = ylimits,
        xticks = (num_ticks, year_ticks),
        xrotation = 20,
        tickfontsize = 9,
        size = (1200, 800)
    )
    StatsPlots.errorline!(model[x_nums], scale * model[varname], errorstyle = :ribbon, label = "model", errortype = :std)
    if !ismissing(benchmark_model)
        StatsPlots.errorline!(model[x_nums], scale * benchmark_model[varname], errorstyle = :ribbon, label = "benchmark", errortype = :std)
    end
    return p
end


num_ticks = []
year_ticks = []
for r in real_data["years_num"]
    # get year of r
    y = year(BeforeIT.num2date(r))
    # save year only if it's new
    if !(y in year_ticks)
        push!(num_ticks, r)
        push!(year_ticks, y)
    end
end


#Yearly plots
# plot real gdp
p1 = plot_model_vs_real(model, real_data, "real_gdp"; title_overload = "GDP (annual)",benchmark_model = benchmark_model)

# plot real household consumption
p2 = plot_model_vs_real(model, real_data, "real_household_consumption"; title_overload = "Consumption (annual)",benchmark_model = benchmark_model)

# plot real fixed capital formation
p3 = plot_model_vs_real(model, real_data, "real_fixed_capitalformation"; title_overload = "Investment (annual)",benchmark_model = benchmark_model)

# plot real government consumption
p4 = plot_model_vs_real(model, real_data, "real_government_consumption"; title_overload = "Government (annual)");

# plot real exports
p5 = plot_model_vs_real(model, real_data, "real_exports"; title_overload = "Exports (annual)");

# plot real imports
p6 = plot_model_vs_real(model, real_data, "real_imports"; title_overload = "Imports (annual)");


yearly_fig = plot(p1, p2, p3, p4, p5, p6, layout = (2,3), legend = false)
savefig(yearly_fig, pwd() * "/analysis/figs/" * model_type * "/abmx_yearly_fig.svg" )

### quarterly plots ###

# plot real gdp quarterly
p1 = plot_model_vs_real(model, real_data, "real_gdp_quarterly"; title_overload = "GDP (quarterly)",benchmark_model = benchmark_model)

# plot real household consumption quarterly
p2 = plot_model_vs_real(model, real_data, "real_household_consumption_quarterly"; title_overload = "Consumption (quarterly)",benchmark_model = benchmark_model)

# plot real fixed capital formation quarterly
p3 = plot_model_vs_real(model, real_data, "real_fixed_capitalformation_quarterly"; title_overload = "Investment (quarterly)",benchmark_model = benchmark_model)

# plot real government consumption quarterly
p4 = plot_model_vs_real(model, real_data, "real_government_consumption_quarterly"; title_overload = "Government (quarterly)")

# plot real exports quarterly
p5 = plot_model_vs_real(model, real_data, "real_exports_quarterly"; title_overload = "Exports (quarterly)")

# plot real imports quarterly
p6 = plot_model_vs_real(model, real_data, "real_imports_quarterly"; title_overload = "Imports (quarterly)")

quarterly_fig = plot(p1, p2, p3, p4, p5, p6, layout = (2, 3), legend = false)
savefig(quarterly_fig, pwd() * "/analysis/figs/" * model_type * "/abmx_quarterly_fig.svg" )


# plot real gdp growth
p1 = plot_model_vs_real(model, real_data, "real_gdp_growth"; scale = 1, title_overload = "GDP growth (annual)",benchmark_model = benchmark_model)

# plot gdp_deflator
p2 = plot_model_vs_real(model, real_data, "gdp_deflator"; scale = 1, title_overload = "Inflation (annual)",benchmark_model = benchmark_model)

# plot real gdp growth quarterly
p3 = plot_model_vs_real(model, real_data, "real_gdp_growth_quarterly"; scale = 1, title_overload = "GDP growth (quarterly)",benchmark_model = benchmark_model)

# plot gdp_deflator quarterly
p4 = plot_model_vs_real(model, real_data, "gdp_deflator_growth_quarterly"; scale = 1, title_overload = "Inflation (quarterly)",benchmark_model = benchmark_model)
 

growth_fig = plot(p1, p2, p3, p4, layout = (2, 2), legend = false)
savefig(growth_fig, pwd() * "/analysis/figs/" * model_type * "/abmx_growth_fig.svg" )

