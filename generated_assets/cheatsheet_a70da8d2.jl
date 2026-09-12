### A Pluto.jl notebook ###
# v0.20.4

#> [frontmatter]
#> title = "BeforeIT cheatsheet"
#> order = 7
#> layout = "layout.jlhtml"
#> tags = ["tutorial"]

using Markdown
using InteractiveUtils

# ╔═╡ c5000000-0000-0000-0000-000000000001
begin
    import Pkg
    Pkg.activate(joinpath(@__DIR__, "..", "..", "pluto_tutorial"); io=devnull)
    import BeforeIT as Bit
    using Plots, Statistics
end

# ╔═╡ c5000000-0000-0000-0000-000000000002
md"""
# BeforeIT.jl — Quick-Reference Cheatsheet

Keep this notebook open in a separate Pluto tab while working through the tutorials.
"""

# ╔═╡ c5000000-0000-0000-0000-000000000003
md"""
---
## Setup
```julia
import BeforeIT as Bit
parameters         = Bit.AUSTRIA2010Q1.parameters
initial_conditions = Bit.AUSTRIA2010Q1.initial_conditions
# Also available: Bit.ITALY2010Q1
```

## Initialise model
```julia
model = Bit.Model(parameters, initial_conditions)
```

## Inspect structure
```julia
fieldnames(typeof(model))          # top-level fields
fieldnames(typeof(model.bank))     # fields of the bank agent
fieldnames(typeof(model.firms))    # fields of all firms (struct-of-arrays)
fieldnames(typeof(model.w_act))    # fields of active workers
fieldnames(typeof(model.prop))     # model properties / parameters
```

## Step and run
```julia
Bit.step!(model; parallel = true)  # one quarter
Bit.collect_data!(model)           # save time series

Bit.run!(model, T)                 # T quarters, in-place

# Equivalent explicit loop. Note run! defaults to parallel = false,
# so pass it explicitly to match:
for _ in 1:T
    Bit.step!(model; parallel = false)
    Bit.collect_data!(model)
end
```

Watch the `parallel` defaults — they differ by function:

| Call | default |
|---|---|
| `Bit.run!(model, T)` | `parallel = false` |
| `Bit.ensemblerun!(models, T)` | `parallel = true` |
| `Bit.ensemblerun(model, T, n)` | `parallel = true` |

The shock keyword is `shock!` (with the bang) on all of them.

## Monte Carlo
```julia
n_sims = 50
models = Bit.ensemblerun!(
    (Bit.Model(parameters, initial_conditions) for _ in 1:n_sims),
    T
)

# With a shock:
models = Bit.ensemblerun!(
    (Bit.Model(parameters, initial_conditions) for _ in 1:n_sims),
    T;
    shock! = my_shock
)
```

## Access time series
```julia
model.data.real_gdp
model.data.real_household_consumption
model.data.real_government_consumption
model.data.real_capitalformation
model.data.real_exports
model.data.real_imports
model.data.wages
model.data.euribor
# GDP deflator (not stored directly — derive it):
# deflator = model.data.nominal_gdp ./ model.data.real_gdp
```

## Built-in plotting
```julia
# Single model — 9-panel or custom panel
ps = Bit.plot_data(model, quantities = [:real_gdp, :wages, :euribor])
plot(ps..., layout = (1, 3))

# Ensemble — fan chart for each variable
ps = Bit.plot_data_vector(models)
plot(ps..., layout = (3, 3))
```

## Shocks
```julia
# Define a shock as a callable struct
struct ProductivityShock; mult::Float64 end
function (s::ProductivityShock)(model)
    model.firms.alpha_bar_i .*= s.mult   # permanent
end

# Apply at t=1 only (permanent shock applied once):
struct WageShock; mult::Float64 end
function (s::WageShock)(model)
    model.agg.t == 1 && (model.firms.w_i .*= s.mult)
end

shock = ProductivityShock(0.95)
Bit.run!(model, T; shock! = shock)
```

## Key parameters (model.prop)
```julia
model.prop.psi          # MPC
model.prop.tau_INC      # income tax
model.prop.tau_VAT      # VAT
model.prop.tau_FIRM     # corporate tax
model.prop.zeta         # bank capital ratio
model.prop.theta_UB     # unemployment benefit rate
model.prop.a_sg         # I-O matrix (sector × product)
model.prop.C            # shock covariance matrix (set to 0 to kill shocks)
```

## Model extensions (multiple dispatch)
```julia
Bit.@object struct MyModel(Bit.Model) <: Bit.AbstractModel end

# Override a specific function:
function Bit.firms_expectations_and_decisions(model::MyModel)
    # your pricing logic here ...
    # call the default for anything you don't change:
    return @invoke Bit.firms_expectations_and_decisions(model::Bit.AbstractModel)
end

# Build the model:
model = MyModel(Bit.Workers(p,ic)..., Bit.Firms(p,ic),
                Bit.Bank(p,ic), Bit.CentralBank(p,ic),
                Bit.Government(p,ic), Bit.RestOfTheWorld(p,ic),
                Bit.Aggregates(p,ic), Bit.Properties(p,ic), Bit.Data())
```

## Change expectations
```julia
# Override globally for all models (use with care!)
function Bit.estimate_next_value(data)
    return data[end]   # backward-looking: always expect last value
end
```

## Fan chart from scratch
```julia
gdp_mat = hcat([m.data.real_gdp for m in models]...)   # (T+1) × n_sims
gdp_mean = mean(gdp_mat, dims=2)[:]
gdp_p10  = [quantile(gdp_mat[t,:], 0.10) for t in axes(gdp_mat, 1)]
gdp_p90  = [quantile(gdp_mat[t,:], 0.90) for t in axes(gdp_mat, 1)]

plot(gdp_mean, ribbon = (gdp_mean .- gdp_p10, gdp_p90 .- gdp_mean),
     fillalpha = 0.2, label = "mean ± 10–90%")
```

## AR(1) benchmark
```julia
y_lag = y_hist[1:end-1]
y_now = y_hist[2:end]
β, α  = hcat(ones(length(y_lag)), y_lag) \\ y_now   # OLS
forecast = [y_hist[end]; [β + α * forecast[t-1] for t in 2:T+1]]
```
"""

# ╔═╡ Cell order:
# ╟─c5000000-0000-0000-0000-000000000002
# ╠═c5000000-0000-0000-0000-000000000001
# ╟─c5000000-0000-0000-0000-000000000003
