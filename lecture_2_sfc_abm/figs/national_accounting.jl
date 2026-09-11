using BeforeIT
using MAT, FileIO
using Dates
using Statistics

# load data from 1996
nation = "netherlands"

data = matread(("./src/utils/" * "calibration_data/" * nation * "/data/1996.mat"))
data = data["data"]

# load predictions from 2010Q1
year_i = 2014
quarter = 4

width=400
height=800

index = findfirst(year.(BeforeIT.num2date.(data["years_num"])).==year_i)[1] .+ Vector(0:1:3)


x_nums = "years_num"
num_ticks = []
year_ticks = []

for r in data["years_num"]
    # get year of r
    y = year(BeforeIT.num2date(r))
    # save year only if it"s new
    if !(y in year_ticks)
        push!(num_ticks, r)
        push!(year_ticks, y)
    end
end


#model_type = "base"
#model_type = "extended_heuristic"
model_type = "optimal_consumption"
#benchmark_model_type = "ar"



model = load("./src/utils/data/netherlands_households_own_firms/"* model_type * "/abm_predictions/" * string(year_i) * "Q" * string(quarter) * ".jld2")["model_dict"]

production_approach = cumsum(hcat(dropdims(mean(model["nominal_nace10_gva"], dims = 2),dims=2),mean(model["nominal_gdp"].-model["nominal_gva"],dims = 2)),dims=2) * 1e6;
production_approach_data = cumsum(hcat(data["nominal_nace10_gva"],(data["nominal_gdp"].-data["nominal_gva"])),dims=2)* 1e6;



using PlotlyJS

years = Vector(year_i:1:(year_i+3))
integer_ticks = Dict(:tickmode => "array", :tickvals => years)
function generate_color_gradient(n, scheme="grayscale",start_intensity=0.1)
    colors = []
    for i in 0:n-1
        # Start from the specified intensity instead of 0
        intensity = start_intensity + (i * (1 - start_intensity) / (n - 1))
        if scheme == "grayscale"
            push!(colors, "rgb($(round(Int, 255*(1-intensity))),$(round(Int, 255*(1-intensity))),$(round(Int, 255*(1-intensity))))")
        elseif scheme == "white_to_blue"
            push!(colors, "rgb($(round(Int, 255*(1-intensity))),$(round(Int, 255*(1-intensity))),255)")
        elseif scheme == "white_to_red"
            push!(colors, "rgb(255,$(round(Int, 255*(1-intensity))),$(round(Int, 255*(1-intensity))))")
        else
            error("Unknown color scheme. Choose 'grayscale', 'white_to_blue', or 'white_to_red'.")
        end
    end
    return colors
end

# Choose your color scheme here
color_scheme = "grayscale"  # or "white_to_blue" or "white_to_red"

# Generate colors for our 11 areas
fill_colors = generate_color_gradient(11, color_scheme)

legend_names = ["A","B,C,D, and E","F","G,H, and I","J","K","L","M and N","O,P and Q","R and S","Taxes less subsidies"]



p1 = plot([
    scatter(x = years, y = production_approach[:,1], fill="tozeroy", mode="none", fillcolor=fill_colors[1], name=legend_names[1]),
    scatter(x = years, y = production_approach[:,2], fill="tonexty", mode="none", fillcolor=fill_colors[2], name=legend_names[2]),
    scatter(x = years, y = production_approach[:,3], fill="tonexty", mode="none", fillcolor=fill_colors[3], name=legend_names[3]),
    scatter(x = years, y = production_approach[:,4], fill="tonexty", mode="none", fillcolor=fill_colors[4], name=legend_names[4]),
    scatter(x = years, y = production_approach[:,5], fill="tonexty", mode="none", fillcolor=fill_colors[5], name=legend_names[5]),
    scatter(x = years, y = production_approach[:,6], fill="tonexty", mode="none", fillcolor=fill_colors[6], name=legend_names[6]),
    scatter(x = years, y = production_approach[:,7], fill="tonexty", mode="none", fillcolor=fill_colors[7], name=legend_names[7]),
    scatter(x = years, y = production_approach[:,8], fill="tonexty", mode="none", fillcolor=fill_colors[8], name=legend_names[8]),
    scatter(x = years, y = production_approach[:,9], fill="tonexty", mode="none", fillcolor=fill_colors[9], name=legend_names[9]),
    scatter(x = years, y = production_approach[:,10], fill="tonexty", mode="none", fillcolor=fill_colors[10], name=legend_names[10]),
    scatter(x = years, y = production_approach[:,11], fill="tonexty", mode="none", fillcolor=fill_colors[11], name=legend_names[11]),
    scatter(x = years, y = production_approach_data[index,1], mode="lines", line=attr(color="black", width=2, dash="dash"), showlegend=false),
    scatter(x = years, y = production_approach_data[index,2], mode="lines", line=attr(color="black", width=2, dash="dash"), showlegend=false),
    scatter(x = years, y = production_approach_data[index,3], mode="lines", line=attr(color="black", width=2, dash="dash"), showlegend=false),
    scatter(x = years, y = production_approach_data[index,4], mode="lines", line=attr(color="black", width=2, dash="dash"), showlegend=false),
    scatter(x = years, y = production_approach_data[index,5], mode="lines", line=attr(color="black", width=2, dash="dash"), showlegend=false),
    scatter(x = years, y = production_approach_data[index,6], mode="lines", line=attr(color="black", width=2, dash="dash"), showlegend=false),
    scatter(x = years, y = production_approach_data[index,7], mode="lines", line=attr(color="black", width=2, dash="dash"), showlegend=false),
    scatter(x = years, y = production_approach_data[index,8], mode="lines", line=attr(color="black", width=2, dash="dash"), showlegend=false),
    scatter(x = years, y = production_approach_data[index,9], mode="lines", line=attr(color="black", width=2, dash="dash"), showlegend=false),
    scatter(x = years, y = production_approach_data[index,10], mode="lines", line=attr(color="black", width=2, dash="dash"), showlegend=false),
    scatter(x = years, y = production_approach_data[index,11], mode="lines", line=attr(color="black", width=2, dash="dash"), showlegend=false),
],
Layout(
    width=width, height=height,
    xaxis=integer_ticks,  # Ensure x-axis shows integers only
))

relayout!(
    p1, 
    legend = attr(
        orientation = "v", 
        yanchor = "bottom", 
        y = 0.0,  # Move slightly above the bottom (inside the plot)
        xanchor = "right", 
        x = 1.0   # Move slightly away from the left edge
    )
)

savefig(p1,pwd() * "/analysis/figs/optimal_consumption/Production_approach.png", width=width, height=height)

income_approach= cumsum(hcat(mean(model["wages"]; dims =2),mean(model["compensation_employees"];dims =2)-mean(model["wages"];dims =2),mean(model["operating_surplus"];dims =2), mean(model["nominal_gva"]-model["compensation_employees"]-model["operating_surplus"];dims =2),mean(model["nominal_gdp"]-model["nominal_gva"];dims =2)),dims =2) * 1e6;
income_approach_data= cumsum(hcat(data["wages"],data["compensation_employees"].-data["wages"],data["operating_surplus"], data["nominal_gva"].-data["compensation_employees"].-data["operating_surplus"],data["nominal_gdp"].-data["nominal_gva"]),dims =2) * 1e6;

legend_names = ["Wages","Social contributions","Gross operating surplus","Taxes less subsidies on production","Taxes less subsidies on products","Location","southeast"];

# Choose your color scheme here
color_scheme = "white_to_blue" #or "white_to_red"

# Generate colors for our 11 areas
fill_colors = generate_color_gradient(5, color_scheme)


p2 = plot([
    scatter(x = years, y = income_approach[:,1], fill="tozeroy", mode="none", fillcolor=fill_colors[1], name=legend_names[1]),
    scatter(x = years, y = income_approach[:,2], fill="tonexty", mode="none", fillcolor=fill_colors[2], name=legend_names[2]),
    scatter(x = years, y = income_approach[:,3], fill="tonexty", mode="none", fillcolor=fill_colors[3], name=legend_names[3]),
    scatter(x = years, y = income_approach[:,4], fill="tonexty", mode="none", fillcolor=fill_colors[4], name=legend_names[4]),
    scatter(x = years, y = income_approach[:,5], fill="tonexty", mode="none", fillcolor=fill_colors[5], name=legend_names[5]),
    scatter(x = years, y = income_approach_data[index,1], mode="lines", line=attr(color="black", width=2, dash="dash"), showlegend=false),
    scatter(x = years, y = income_approach_data[index,2], mode="lines", line=attr(color="black", width=2, dash="dash"), showlegend=false),
    scatter(x = years, y = income_approach_data[index,3], mode="lines", line=attr(color="black", width=2, dash="dash"), showlegend=false),
    scatter(x = years, y = income_approach_data[index,4], mode="lines", line=attr(color="black", width=2, dash="dash"), showlegend=false),
    scatter(x = years, y = income_approach_data[index,5], mode="lines", line=attr(color="black", width=2, dash="dash"), showlegend=false),
],
Layout(
    width=width, height=height,
    xaxis=integer_ticks,  # Ensure x-axis shows integers only
))

relayout!(
    p2, 
    legend = attr(
        orientation = "v", 
        yanchor = "bottom", 
        y = 0.0,  # Move slightly above the bottom (inside the plot)
        xanchor = "right", 
        x = 1.0   # Move slightly away from the left edge
    )
)
savefig(p2,pwd() * "/analysis/figs/optimal_consumption/income_approach.png", width=width, height=height)

expenditure_approach=cumsum(hcat(mean(model["nominal_household_consumption"]; dims = 2),mean(model["nominal_government_consumption"]; dims = 2), mean(model["nominal_capitalformation"]; dims = 2), mean(model["nominal_exports"]-model["nominal_imports"];dims = 2));dims =2);
expenditure_approach_data=cumsum(hcat(data["nominal_household_consumption"],data["nominal_government_consumption"], data["nominal_capitalformation"], data["nominal_exports"]-data["nominal_imports"]);dims =2);

legend_names = ["Household consumption","Government consumption","Capital formation","Net exports"];

# Choose your color scheme here
color_scheme = "white_to_red"

# Generate colors for our 11 areas
fill_colors = generate_color_gradient(4, color_scheme)


p3 = plot([
    scatter(x = years, y = expenditure_approach[:,1], fill="tozeroy", mode="none", fillcolor=fill_colors[1], name=legend_names[1]),
    scatter(x = years, y = expenditure_approach[:,2], fill="tonexty", mode="none", fillcolor=fill_colors[2], name=legend_names[2]),
    scatter(x = years, y = expenditure_approach[:,3], fill="tonexty", mode="none", fillcolor=fill_colors[3], name=legend_names[3]),
    scatter(x = years, y = expenditure_approach[:,4], fill="tonexty", mode="none", fillcolor=fill_colors[4], name=legend_names[4]),
    scatter(x = years, y = expenditure_approach_data[index,1], mode="lines", line=attr(color="black", width=2, dash="dash"), showlegend=false),
    scatter(x = years, y = expenditure_approach_data[index,2], mode="lines", line=attr(color="black", width=2, dash="dash"), showlegend=false),
    scatter(x = years, y = expenditure_approach_data[index,3], mode="lines", line=attr(color="black", width=2, dash="dash"), showlegend=false),
    scatter(x = years, y = expenditure_approach_data[index,4], mode="lines", line=attr(color="black", width=2, dash="dash"), showlegend=false),
],
Layout(
    xaxis=integer_ticks,  # Ensure x-axis shows integers only
    width=width, height=height,
))

relayout!(
    p3, 
    legend = attr(
        orientation = "v", 
        yanchor = "bottom", 
        y = 0.0,  # Move slightly above the bottom (inside the plot)
        xanchor = "right", 
        x = 1.0   # Move slightly away from the left edge
    )
)

savefig(p3,pwd() * "/analysis/figs/optimal_consumption/expenditure_approach.png", width=width, height=height)