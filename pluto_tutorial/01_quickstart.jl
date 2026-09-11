### A Pluto.jl notebook ###
# v0.20.24

using Markdown
using InteractiveUtils

# This Pluto notebook uses @bind for interactivity. When running this notebook outside of Pluto, the following 'mock version' of @bind gives bound variables a default value (instead of an error).
macro bind(def, element)
    #! format: off
    return quote
        local iv = try Base.loaded_modules[Base.PkgId(Base.UUID("6e696c72-6542-2067-7265-42206c756150"), "AbstractPlutoDingetjes")].Bonds.initial_value catch; b -> missing; end
        local el = $(esc(element))
        global $(esc(def)) = Core.applicable(Base.get, el) ? Base.get(el) : iv(el)
        el
    end
    #! format: on
end

# ╔═╡ 01000000-0000-0000-0000-000000000001
begin
    import Pkg
    Pkg.activate(dirname(@__FILE__))
    import BeforeIT as Bit
    import Random
    using Plots, StatsPlots, PlutoUI, Statistics
end

# ╔═╡ 01000000-0000-0000-0000-000000000002
md"""
# Notebook 01 — Hello, BeforeIT

> **Question this notebook answers:** what does the Austrian macro economy look like over the next 5 years, according to the Poledna et al. (2019) agent-based model?

### Lecture 2 slides covered
- *Model overview* (slide: "What are agent-based model typical elements again?")
- *Sequence of events in each quarter* (slide: "(i) Expectations → … → (v) Accounting")
- *How big is the model?* (agent count table)

### Learning goals
After this notebook you will be able to:
1. Initialise and run the BeforeIT model.
2. Plot any time series from the output.
3. Interpret stochasticity across Monte Carlo runs.
4. Build a simple fan chart from an ensemble.
"""

# ╔═╡ 01000000-0000-0000-0000-000000000003
md"""
---
## Step 1 — Load the Austria 2010:Q1 calibration

The model ships with a fully pre-calibrated parametrisation of the Austrian economy at the start of Q1 2010. All 50+ parameters are read directly from Eurostat national accounts — no free parameters to tune.

Recall from Lecture 2 the full parameter table: VAT = 15.29%, MPC $\psi$ = 93.94%, corporate tax = 7.62%, etc.
"""

# ╔═╡ 01000000-0000-0000-0000-000000000004
begin
    nb01_p  = Bit.AUSTRIA2010Q1.parameters
    nb01_ic = Bit.AUSTRIA2010Q1.initial_conditions
    "Parameters and initial conditions loaded ✓"
end

# ╔═╡ 01000000-0000-0000-0000-000000000005
md"""
---
## Step 2 — Initialise the model

`Bit.Model` creates all ~9.9 million agents and wires up the full stock-flow-consistent balance sheet structure.
"""

# ╔═╡ 01000000-0000-0000-0000-000000000006
nb01_model = Bit.Model(nb01_p, nb01_ic);

# ╔═╡ 01000000-0000-0000-0000-000000000007
md"""
Inspect what's inside the model. Each field is a container of agents or an aggregate tracker:
"""

# ╔═╡ 01000000-0000-0000-0000-000000000008
fieldnames(typeof(nb01_model))

# ╔═╡ 01000000-0000-0000-0000-000000000009
md"""
For example, the `bank` agent holds:
"""

# ╔═╡ 01000000-0000-0000-0000-00000000000a
fieldnames(typeof(nb01_model.bank))

# ╔═╡ 01000000-0000-0000-0000-00000000000b
md"""
---
## Step 3 — Run the model

Each call to `Bit.step!` advances the model by **one quarter**, running the full sequence from Lecture 2:

| Step | What happens |
|------|-------------|
| (i) | Agents OLS-update their AR(1) inflation and growth forecasts |
| (ii) | Exogenous shocks drawn from 5 AR(1) processes |
| (iii) | Credit and labour markets solved (search-and-matching) |
| (iv) | Goods markets solved (search-and-matching) |
| (v) | Accounting: update balance sheets, check insolvencies, compute profits, taxes, transfers |

We can step manually to see this:
"""

# ╔═╡ 01000000-0000-0000-0000-00000000000c
begin
    model_demo = Bit.Model(nb01_p, nb01_ic)
    Bit.step!(model_demo; parallel = true)   # one quarter
    Bit.collect_data!(model_demo)            # save the time series
    "Stepped one quarter. GDP = $(round(model_demo.data.real_gdp[1], digits=2))"
end

# ╔═╡ 01000000-0000-0000-0000-00000000000d
md"""
---
## Step 4 — Simulate for T quarters

`Bit.run!` is the convenient wrapper that calls `step!` + `collect_data!` in a loop.

Use the slider below to set the horizon, then press **Run** to simulate.

> ⚠️ Each run takes ~10–30 seconds depending on your machine. Do not move the slider during a run.
"""

# ╔═╡ 01000000-0000-0000-0000-00000000000e
@bind T_horizon PlutoUI.Slider(4:4:40, default=20, show_value=true)

# ╔═╡ 01000000-0000-0000-0000-00000000000f
@bind rng_seed PlutoUI.Slider(1:100, default=42, show_value=true)

# ╔═╡ 01000000-0000-0000-0000-000000000010
@bind run_single PlutoUI.Button("▶ Run simulation")

# ╔═╡ 01000000-0000-0000-0000-000000000011
md"""
Horizon: **$(T_horizon) quarters** ($(T_horizon ÷ 4) years)  |  RNG seed: **$(rng_seed)**
"""

# ╔═╡ 01000000-0000-0000-0000-000000000012
begin
    run_single   # re-runs only when button is pressed
    Random.seed!(rng_seed)
    _m = Bit.Model(nb01_p, nb01_ic)
    Bit.run!(_m, T_horizon)
    _m
end

# ╔═╡ 01000000-0000-0000-0000-000000000013
md"""
---
## Step 5 — Plot the results

`Bit.plot_data` knows how to plot any of the tracked time series. The 9-panel dashboard below shows the same quantities reported in Poledna et al. (2019) Table 4.
"""

# ╔═╡ 01000000-0000-0000-0000-000000000014
begin
    ps = Bit.plot_data(
        begin run_single; _m end,
        quantities = [
            :real_gdp,
            :real_household_consumption,
            :real_government_consumption,
            :real_capitalformation,
            :real_exports,
            :real_imports,
            :wages,
            :euribor,
            :gdp_deflator,
        ],
    )
    plot(ps..., layout = (3, 3), size = (900, 700))
end

# ╔═╡ 01000000-0000-0000-0000-000000000015
md"""
Try different seeds (slider above) and click **Run** again. Notice that:
- The **trend** is similar across seeds — driven by the five exogenous AR(1) processes.
- The **fluctuations** differ — driven by agent-level stochasticity in search-and-matching.

This is what Monte Carlo simulation quantifies.
"""

# ╔═╡ 01000000-0000-0000-0000-000000000016
md"""
---
## Step 6 — Monte Carlo ensemble

To properly characterise uncertainty, run the model N times with different seeds and aggregate. BeforeIT provides `ensemblerun!` for this.

> This takes ~1–5 minutes for 20 paths. Press the button once.
"""

# ╔═╡ 01000000-0000-0000-0000-000000000017
@bind n_mc PlutoUI.Slider([5, 10, 20, 50], default=10, show_value=true)

# ╔═╡ 01000000-0000-0000-0000-000000000018
@bind run_mc PlutoUI.Button("▶ Run Monte Carlo")

# ╔═╡ 01000000-0000-0000-0000-000000000019
begin
    run_mc
    _models_mc = Bit.ensemblerun!(
        (Bit.Model(nb01_p, nb01_ic) for _ in 1:n_mc),
        T_horizon,
    )
    "Monte Carlo complete: $(n_mc) paths × $(T_horizon) quarters ✓"
end

# ╔═╡ 01000000-0000-0000-0000-00000000001a
begin
    run_mc   # depends on the MC run
    ps_mc = Bit.plot_data_vector(_models_mc)
    plot(ps_mc..., layout = (3, 3), size = (900, 700))
end

# ╔═╡ 01000000-0000-0000-0000-00000000001b
md"""
The shaded ribbon shows the 10–90th percentile range across Monte Carlo paths. Wider ribbons indicate more uncertainty about that variable.
"""

# ╔═╡ 01000000-0000-0000-0000-00000000001c
md"""
---
## Step 7 — Manual fan chart for GDP

`plot_data_vector` is a shortcut. Here is how to build a custom fan chart from scratch — useful for Notebook 06 (forecasting).
"""

# ╔═╡ 01000000-0000-0000-0000-00000000001d
begin
    run_mc
    # Stack GDP series: T+1 rows × n_mc columns
    nb01_gdp_matrix = hcat([m.data.real_gdp for m in _models_mc]...)
    nb01_quarters   = 0:T_horizon   # quarter 0 = initial condition

    nb01_gdp_mean   = mean(nb01_gdp_matrix, dims = 2)[:]
    nb01_gdp_p10    = [quantile(nb01_gdp_matrix[t, :], 0.10) for t in 1:T_horizon+1]
    nb01_gdp_p90    = [quantile(nb01_gdp_matrix[t, :], 0.90) for t in 1:T_horizon+1]

    plot(nb01_quarters, nb01_gdp_mean,
         ribbon   = (nb01_gdp_mean .- nb01_gdp_p10, nb01_gdp_p90 .- nb01_gdp_mean),
         fillalpha = 0.25,
         label    = "Mean ± 10–90%",
         xlabel   = "Quarter",
         ylabel   = "Real GDP (index)",
         title    = "Austria: $(n_mc)-path MC forecast ($(T_horizon) quarters)",
         lw       = 2,
         color    = :steelblue)
end

# ╔═╡ 01000000-0000-0000-0000-00000000001e
md"""
---
## ✔ What you learned

- `Bit.Model(parameters, initial_conditions)` — builds the full agent population.
- `Bit.step!(model; parallel=true)` + `Bit.collect_data!(model)` — one quarter at a time.
- `Bit.run!(model, T)` — convenience wrapper for T steps.
- `Bit.ensemblerun!(models_iter, T)` — MC ensemble over an iterator of models.
- `Bit.plot_data(model, quantities=[...])` — built-in 9-panel dashboard.
- `model.data.real_gdp` — access any tracked time series.

---
## Exercises
**Exercise 01.1** — Compute the standard deviation of real GDP at `T = 20` across 20 MC paths.
How does it compare to the mean?

**Exercise 01.2** *(stretch)* — Run two ensembles of 20 paths: one starting at Austria 2010:Q1,
one starting at Italy (`Bit.ITALY2010Q1`). Plot the GDP fan charts side-by-side and comment on
any structural differences you see.
"""

# ╔═╡ Cell order:
# ╟─01000000-0000-0000-0000-000000000002
# ╠═01000000-0000-0000-0000-000000000001
# ╟─01000000-0000-0000-0000-000000000003
# ╠═01000000-0000-0000-0000-000000000004
# ╟─01000000-0000-0000-0000-000000000005
# ╠═01000000-0000-0000-0000-000000000006
# ╠═01000000-0000-0000-0000-000000000007
# ╠═01000000-0000-0000-0000-000000000008
# ╠═01000000-0000-0000-0000-000000000009
# ╠═01000000-0000-0000-0000-00000000000a
# ╟─01000000-0000-0000-0000-00000000000b
# ╠═01000000-0000-0000-0000-00000000000c
# ╟─01000000-0000-0000-0000-00000000000d
# ╠═01000000-0000-0000-0000-00000000000e
# ╠═01000000-0000-0000-0000-00000000000f
# ╠═01000000-0000-0000-0000-000000000010
# ╟─01000000-0000-0000-0000-000000000011
# ╠═01000000-0000-0000-0000-000000000012
# ╟─01000000-0000-0000-0000-000000000013
# ╠═01000000-0000-0000-0000-000000000014
# ╟─01000000-0000-0000-0000-000000000015
# ╟─01000000-0000-0000-0000-000000000016
# ╠═01000000-0000-0000-0000-000000000017
# ╠═01000000-0000-0000-0000-000000000018
# ╠═01000000-0000-0000-0000-000000000019
# ╠═01000000-0000-0000-0000-00000000001a
# ╟─01000000-0000-0000-0000-00000000001b
# ╟─01000000-0000-0000-0000-00000000001c
# ╠═01000000-0000-0000-0000-00000000001d
# ╟─01000000-0000-0000-0000-00000000001e
