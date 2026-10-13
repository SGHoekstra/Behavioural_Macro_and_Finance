### A Pluto.jl notebook ###
# v0.20.4

using Markdown
using InteractiveUtils

# ╔═╡ c5000000-0000-0000-0000-000000000001
begin
    import Pkg
    Pkg.activate(dirname(@__FILE__))
    import BeforeIT as Bit
    using Plots, Statistics, Dates, Random
end

# ╔═╡ c5000000-0000-0000-0000-000000000002
md"""
# BeforeIT.jl — Quick-Reference Cheatsheet

Keep this notebook open in a separate Pluto tab while working through the tutorials.
"""

# ╔═╡ c5000000-0000-0000-0000-000000000003
md"""
---
## Choose the task

| I want to… | Use | Notebook |
|---|---|---|
| Inspect agents and the quarter sequence | `fieldnames`, `Bit.step!` | 01 |
| Calibrate, forecast or compare paths | Fresh models, `Bit.ensemblerun!` | 02 |
| Compare a shock with its baseline | Same seed, distinct fresh models | 03 |
| Change one behavioural mechanism | A specialised model type and method | 04 |
| Estimate unknown coefficients | Simulator → synthetic recovery → diagnostics | 05, local only |

All code below is a reference to copy into your own cells. A trailing `!` means that a function **changes its arguments**; do not reuse a previously run model as a fresh baseline.

## 1 — Set up a small model

```julia
import BeforeIT as Bit
using Dates, Random, Statistics, Plots

parameters, initial_conditions = Bit.get_params_and_initial_conditions(
    Bit.AUSTRIA_CALIBRATION, DateTime(2010, 3, 31); scale=0.001
)
# For Italy, use Bit.ITALY_CALIBRATION.
Random.seed!(123)
model = Bit.Model(parameters, initial_conditions)
```

`scale` reduces the agent population for classroom runs. It changes finite-population noise, so it is part of the simulation design. The constructor initialises agents and records period 0.

## 2 — Find a field before changing it

```julia
fieldnames(typeof(model))        # top-level containers
fieldnames(typeof(model.bank))   # bank fields
fieldnames(typeof(model.firms))  # arrays, one entry per firm
fieldnames(typeof(model.w_act))  # active workers
fieldnames(typeof(model.prop))   # policy and behavioural parameters
length(model.firms.G_i)          # actual number of firms
```

Use `model.firms.P_i[1]` for one firm's price and `model.firms.P_i` for all prices. Use `.=` or `.*=` to change array entries in place; `x = y` merely changes the binding.

## 3 — Step, record and run

```julia
Bit.step!(model; parallel=false)   # one quarter; changes the state
Bit.collect_data!(model)           # record that quarter

# Start fresh before a separate T-quarter experiment:
T = 4
model = Bit.Model(parameters, initial_conditions)
Bit.run!(model, T; parallel=false) # steps AND records each quarter
```

Equivalent loop, **on another fresh model**:

```julia
model = Bit.Model(parameters, initial_conditions)
for _ in 1:T
    Bit.step!(model; parallel=false)
    Bit.collect_data!(model)
end
```

Do not add `collect_data!` after each `run!` step: `run!` already records it. A fresh `T`-quarter run has `T+1` observations including period 0.

| Function | Default `parallel` | What changes? |
|---|---|---|
| `Bit.step!` | `false` | Model state |
| `Bit.run!` | `false` | Model state and recorded data |
| `Bit.ensemblerun!` | `true` | Every supplied model |
| `Bit.ensemblerun` | `true` | Runs copies of a supplied model |

## 4 — Compare simulated paths

```julia
Random.seed!(123)
n_sims = 10
models = Bit.ensemblerun!(
    (Bit.Model(parameters, initial_conditions) for _ in 1:n_sims),
    T; parallel=false
)
```

Specify `parallel=false` when using this seeded classroom example. Ten paths give a quick comparison; quantiles based on so few paths are coarse. Increase the number only after the small run works.

## 5 — Read levels and calculate rates

```julia
model.data.real_gdp
model.data.real_household_consumption
model.data.real_government_consumption
model.data.real_capitalformation
model.data.real_exports
model.data.real_imports
model.data.wages
model.data.euribor

deflator = model.data.nominal_gdp ./ model.data.real_gdp
inflation = diff(deflator) ./ deflator[1:end-1]
gdp_growth = diff(model.data.real_gdp) ./ model.data.real_gdp[1:end-1]
```

The rates above are fractions: multiply by 100 for a plot labelled `%`. Differencing `T+1` levels gives `T` quarterly rates. Nominal GDP divided by real GDP gives the GDP deflator, not a consumer price index.

## 6 — Plot a variable or an ensemble

```julia
ps = Bit.plot_data(model; quantities=[:real_gdp, :wages, :euribor])
plot(ps..., layout=(1,3))

ps = Bit.plot_data_vector(models)
plot(ps..., layout=(3,3))
```

A transparent fan chart from scratch:

```julia
gdp_mat = hcat([m.data.real_gdp for m in models]...) # (T+1) × n_sims
gdp_median = [median(gdp_mat[t,:]) for t in axes(gdp_mat,1)]
gdp_p10 = [quantile(gdp_mat[t,:],0.10) for t in axes(gdp_mat,1)]
gdp_p90 = [quantile(gdp_mat[t,:],0.90) for t in axes(gdp_mat,1)]
plot(0:T, gdp_median,
     ribbon=(gdp_median .- gdp_p10, gdp_p90 .- gdp_median),
     fillalpha=0.2, xlabel="Quarter", label="Median; 10–90% path band")
```

This band describes dispersion across simulated paths conditional on the model and parameters. It is not a confidence interval for the mean or a calibrated empirical prediction interval.

## 7 — Apply a one-time shock with a lasting level effect

```julia
struct ProductivityShock
    mult::Float64
end
function (s::ProductivityShock)(model)
    if model.agg.t == 1
        model.firms.alpha_bar_i .*= s.mult
    end
    return nothing
end

Random.seed!(123)
baseline = Bit.Model(parameters, initial_conditions)
Bit.run!(baseline,T; parallel=false)

Random.seed!(123)
shocked = Bit.Model(parameters, initial_conditions)
Bit.run!(shocked,T; parallel=false, shock! = ProductivityShock(0.95))
```

**Write the keyword with spaces in Julia:** `shock! = ProductivityShock(0.95)`. Without the space, `shock!=...` can be read as the inequality operator. The callback is called every quarter; the `t==1` guard prevents a repeated 5% reduction each quarter. Compare the shocked path with a fresh baseline, never with its own earlier state. Matching seeds reduces variation in a comparison but does not guarantee identical random choices once paths diverge.

## 8 — Locate policy and behavioural parameters

```julia
model.prop.psi       # household consumption share in the behavioural rule
model.prop.tau_INC   # income tax
model.prop.tau_VAT   # VAT
model.prop.tau_FIRM  # corporate tax
model.prop.zeta      # bank capital ratio
model.prop.theta_UB  # unemployment benefit rate
model.prop.a_sg      # input–output coefficients
model.prop.C         # covariance for three external innovations
```

Some property fields are constant after construction. Use copied calibration dictionaries to set them before building a new model. Setting `C` to zero suppresses those external innovations; it does not remove all randomness from the economy.

## 9 — Extend a model with a specialised method

```julia
Bit.@object mutable struct MyModel(Bit.Model) <: Bit.AbstractModel end

function Bit.firms_expectations_and_decisions(model::MyModel)
    decisions = @invoke Bit.firms_expectations_and_decisions(model::Bit.AbstractModel)
    return decisions  # unchanged fallback; replace components for your rule
end

p, ic = parameters, initial_conditions
model = MyModel((Bit.Workers(p,ic)..., Bit.Firms(p,ic),
                 Bit.Bank(p,ic), Bit.CentralBank(p,ic),
                 Bit.Government(p,ic), Bit.RestOfTheWorld(p,ic),
                 Bit.Aggregates(p,ic), Bit.Properties(p,ic), Bit.Data()))
```

The **tuple constructor** performs BeforeIT's worker–firm matching, aggregate initialisation and period-0 data collection. The specialised method is used for `MyModel`; ordinary `Bit.Model` instances retain the default method. Notebook 04 supplies a complete pricing extension.

To change expectations only for this model type:

```julia
function Bit.growth_inflation_expectations(model::MyModel)
    k = model.prop.T_prime + model.agg.t - 1
    Y_last = model.agg.Y[k]
    pi_last = model.agg.pi_[k] # log gross inflation in this history
    return Y_last, 0.0, exp(pi_last)-1
end
```

This rule expects the last GDP **level**, hence zero GDP growth, and the last inflation rate. It differs from extrapolating the last observed GDP growth rate. Keep the override in its own cell so you can compare it with the default forecasting rule.

## 10 — Forecast an AR(1) benchmark recursively

```julia
# y_hist: historical observations on the same variable/transformation
# as the forecast you will compare. At least three observations are needed.
y_lag = y_hist[1:end-1]
y_now = y_hist[2:end]
intercept, persistence = hcat(ones(length(y_lag)),y_lag) \\ y_now
forecast = Vector{Float64}(undef,T+1)
forecast[1] = y_hist[end]    # observed starting value, not an estimated forecast
for h in 1:T
    forecast[h+1] = intercept + persistence*forecast[h]
end
```

Fit using pre-forecast observations only. Compare the same horizon, units and dates; a forecast of log GDP is not directly a forecast of GDP growth. Recursive point forecasts do not include an uncertainty band.

## 11 — Infer parameters without a likelihood *(Notebook 05)*

**Specify the experiment → simulate pairs → fit → diagnose.**

- **ABC:** retain prior draws with outputs within a chosen tolerance.
- **NPE:** learn a conditional density of parameters given outputs.
- **NRE-B:** learn a likelihood-to-evidence ratio through contrastive classification; the example samples with MCMC.
- **Sequential inference:** add proposal-focused simulation rounds, with NPE proposal correction.

Observations and training must use the same observation protocol. Separate parameter-draw RNGs from simulation seeds, report failed simulations, and distinguish recovery under a known model from repeated-experiment coverage and independent model/policy validation. A narrower posterior alone does not establish accuracy.
"""

# ╔═╡ Cell order:
# ╟─c5000000-0000-0000-0000-000000000002
# ╠═c5000000-0000-0000-0000-000000000001
# ╟─c5000000-0000-0000-0000-000000000003
