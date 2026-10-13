### A Pluto.jl notebook ###
# v0.20.24

#> [frontmatter]
#> order = 4
#> title = "Shocks, expectations and policy"
#> layout = "layout.jlhtml"
#> tags = ["tutorial"]

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

# ╔═╡ 2bd3ccb6-aeb1-11f1-b3bc-4d70a471e508
begin
    import Pkg
    Pkg.activate(dirname(@__FILE__))
    import BeforeIT as Bit
    import Random
    using Plots, StatsPlots, PlutoUI, Statistics
end

# ╔═╡ 2c278ede-aeb1-11f1-a840-0d3b6fe012e3
md"""
# Notebook 03 — Shocks, expectations and policy

> **Question:** how does a change to productivity or household spending propagate through a heterogeneous economy?

### Before running anything
Predict which variable moves first, which balance sheets bear the cost, and whether the
change is temporary or persistent. Then compare the prediction with the plots.
The online page shows saved outputs; use Pluto locally to change the controls.

### Lecture 2 slides covered
- *What drives fluctuations? Five exogenous AR(1) processes*
- *Endogenous crises: the bankruptcy cascade*
- *Expectations and fiscal/monetary closure*

### Learning goals
1. Distinguish external disturbances from endogenous propagation.
2. Design a matched shock/baseline comparison and read its units and simulation uncertainty.
3. Test proportionality without mistaking Monte Carlo noise for non-linearity.
4. Compare expectation rules and explain the euro-area policy closure.
"""

# ╔═╡ 2c278f24-aeb1-11f1-af9b-c5924659f871
begin
    nb3_p  = Bit.AUSTRIA2010Q1.parameters
    nb3_ic = Bit.AUSTRIA2010Q1.initial_conditions
    "Calibration loaded ✓"
end

# ╔═╡ 2c278f44-aeb1-11f1-a7d6-0786c7458453
md"""
---
## 1 — Five external processes, several propagation mechanisms

The Poledna ABM models five external processes with AR(1) rules estimated from data.
Their entry points differ; the final GDP effect depends on the economy's response.

| Process | Where it enters | First mechanism to investigate |
|---|---|---|
| Export demand | `model.agg.epsilon_E` | Foreign purchases of domestic output |
| Import supply | `model.agg.epsilon_I` | Availability of imported goods and inputs |
| Government consumption | Government expenditure rule | Demand for goods |
| Euro-area GDP growth | `model.agg.epsilon_Y_EA` | The central bank's Taylor rule |
| Euro-area inflation | `rotw` inflation rule | The central bank's Taylor rule |

The innovations for exports, imports and euro-area output are drawn jointly using
`model.prop.C`, a calibrated 3×3 covariance matrix. Government consumption and euro-area
inflation draw separately from their scalar standard deviations. Random goods-market
matching and innovations in learned forecasts add further simulation randomness.

**Read the dashboard carefully:** these are aggregate outcomes, not plots of the five
innovations themselves. Co-movement in one simulated path does not identify a causal effect.
"""

# ╔═╡ 2c278f56-aeb1-11f1-b435-15c27b8085c2
@bind run_baseline PlutoUI.Button("▶ Run baseline (20 quarters)")

# ╔═╡ 2c278f60-aeb1-11f1-9aef-412714939caf
begin
    run_baseline
    _m_base = Bit.Model(nb3_p, nb3_ic)
    Bit.run!(_m_base, 20)
    "Baseline run complete ✓"
end

# ╔═╡ 2c278f76-aeb1-11f1-a61e-491164534635
begin
    run_baseline
    plot(
        Bit.plot_data(_m_base, quantities = [
            :real_gdp, :real_exports, :real_imports,
            :real_government_consumption, :euribor, :wages
        ])...,
        layout = (2, 3), size = (850, 500),
        title  = ["Real GDP" "Exports" "Imports" "Gov. consumption" "Policy rate (quarterly fraction)" "Nominal wage bill"],
    )
end

# ╔═╡ 2c278f9c-aeb1-11f1-860a-63e91f994997
md"""
---
## 2 — Design a shock experiment

BeforeIT calls `shock!(model)` every quarter after setting macro expectations and the
policy rate, but before firms' pricing, production and household budgets. Our callable
struct changes a parameter only when `model.agg.t == 1`.

**Timing matters:** the productivity change and the consumption-propensity change below
remain in place after quarter 1. They are persistent parameter interventions, not one-quarter
pulses. The model continues to draw its usual stochastic disturbances.

Change the controls and press **Confirm** together. The Run button repeats the confirmed
experiment. Pluto also evaluates a modest default experiment when the notebook opens.
"""

# ╔═╡ 2c278fb0-aeb1-11f1-a8fa-0331ace63bdd
begin
    nb3_shock_controls = @bind shock_settings PlutoUI.confirm(PlutoUI.combine() do Child
        md"""
        **Shock type:** $(Child("kind", PlutoUI.Select(["Productivity", "Consumption (MPC)"], default="Productivity")))

        **Multiplier (1.0 = no change):** $(Child("multiplier", PlutoUI.Slider(0.80:0.01:1.20, default=0.95, show_value=true)))

        **Monte Carlo paths:** $(Child("paths", PlutoUI.Slider([8, 16, 32], default=8, show_value=true)))
        """
    end)
    shock_type = shock_settings.kind
    shock_size = shock_settings.multiplier
    n_shock_mc = shock_settings.paths
    nb3_shock_controls
end

# ╔═╡ 2c278fc4-aeb1-11f1-b35e-b9290280c086
begin
    struct Nb3ProductivityShock; mult::Float64 end
    struct Nb3ConsumptionShock; mult::Float64 end

    function (s::Nb3ProductivityShock)(model)
        model.agg.t == 1 && (model.firms.alpha_bar_i .*= s.mult)
    end
    function (s::Nb3ConsumptionShock)(model)
        model.agg.t == 1 && (model.prop.psi *= s.mult)
    end

    # Seed each replicate explicitly; serial market matching avoids thread-order noise.
    # Resetting seeds aligns initial random draws. Endogenous branches can later consume
    # different numbers of draws, so it does not guarantee identical future disturbances.
    function nb3_paths(n; shock=Bit.NoShock(), seed=4040, T=20)
        map(1:n) do i
            Random.seed!(seed + i)
            Bit.run!(Bit.Model(nb3_p, nb3_ic), T; shock! = shock, parallel=false)
        end
    end
end

# ╔═╡ 2c278fe2-aeb1-11f1-8f5f-f31c275bbd10
@bind run_shock PlutoUI.Button("▶ Run shocked vs baseline")

# ╔═╡ 2c278ff6-aeb1-11f1-b5b6-39ae723b6717
begin
    run_shock
    chosen_shock = shock_type == "Productivity" ?
        Nb3ProductivityShock(shock_size) : Nb3ConsumptionShock(shock_size)
    _models_base = nb3_paths(n_shock_mc)
    _models_shocked = nb3_paths(n_shock_mc; shock=chosen_shock)
    "Matched shock experiment complete ✓"
end

# ╔═╡ 2c27901e-aeb1-11f1-97bb-0d095ecd46fd
begin
    run_shock
    nb3_dashboard = map([
        (:real_gdp, "Real GDP", "Change (%)"),
        (:wages, "Nominal wage bill", "Change (%)"),
        (:euribor, "Quarterly policy rate", "Difference (percentage points)"),
        (:real_household_consumption, "Real household consumption", "Change (%)"),
    ]) do (field, panel_title, units)
        b = hcat([getfield(m.data, field) for m in _models_base]...)
        s = hcat([getfield(m.data, field) for m in _models_shocked]...)
        effects = field == :euribor ? 100 .* (s .- b) : 100 .* (s ./ b .- 1)
        avg = vec(mean(effects, dims=2))
        se = vec(std(effects, dims=2)) ./ sqrt(n_shock_mc)
        panel = plot(0:20, avg; ribbon=se, fillalpha=0.2, lw=2,
            title=panel_title, xlabel="Quarter", ylabel=units,
            label="Mean paired effect ± 1 MC SE", color=:steelblue)
        hline!(panel, [0.0]; label="No effect", color=:black, ls=:dash, lw=1)
        panel
    end
    plot(nb3_dashboard...; layout=(2, 2), size=(900, 620))
end

# ╔═╡ 2c279032-aeb1-11f1-93a6-310284d02e04
md"""
**First check:** confirm a multiplier of **1.0**. All four differences should be zero,
up to numerical tolerance. A GDP effect of −2 means GDP is 2% below its matched baseline;
a policy-rate difference of 0.1 means 0.1 **percentage points**, not 10% higher rates.

Next use 0.95. A lower productivity norm can tighten production capacity; a lower `psi`
reduces planned consumption relative to expected income. Trace the outcomes rather than
assuming that both changes operate through the same mechanism.
"""

# ╔═╡ 2c279050-aeb1-11f1-9ab8-f37ad5c40d3b
md"""
**Reading the four panels:**
- GDP and consumption show real quantity effects relative to their baselines.
- `data.wages` is the **total nominal wage bill**: employment, wage rates and prices can all change it.
- The policy rate responds to **euro-area**, not domestic, conditions. A domestic shock does not directly trigger an ECB rate cut in this model. Later rate differences can arise if the simulations' random draws diverge.
- The ribbon is one standard error of the mean paired simulation effect. It measures Monte Carlo precision, not parameter uncertainty or an empirical confidence interval.

A persistent GDP loss alone does not prove a bankruptcy cascade. Inspect firm insolvency,
bank equity or input shortages to distinguish mechanisms. Insolvent firms are refinanced
in the baseline model; they are not simply removed forever. Nonlinear DSGE models can also
contain financial constraints, so this plot is not a general ABM-versus-DSGE verdict.
"""

# ╔═╡ 2c27906e-aeb1-11f1-b728-01a680a89df4
md"""
---
## 3 — Is the response proportional to the intervention?

Vary the productivity multiplier and compare real GDP at **quarter 20** with one shared
baseline ensemble. Each replicate uses the same seed across settings, and the no-change
case reuses the baseline itself. This supplies a useful zero-effect check.

The plot reports the mean of paired percentage changes, with a one-Monte-Carlo-standard-error
ribbon. It is the terminal response, not the deepest recession within the horizon.
A curved relationship is evidence to investigate, but a jagged small-sample line is not
by itself evidence of economic non-linearity. Increase the number of paths before drawing
that conclusion. The scan has seven settings to keep the default runtime manageable.
"""

# ╔═╡ 2c279078-aeb1-11f1-90c0-ddb27eeda0a6
@bind run_nonlinear PlutoUI.Button("▶ Scan seven productivity settings")

# ╔═╡ 2c2790a0-aeb1-11f1-80f1-9736724f909d
begin
    run_nonlinear
    shock_mults = [0.80, 0.90, 0.95, 1.0, 1.05, 1.10, 1.20]
    _scan_base = nb3_paths(n_shock_mc; seed=4042)
    scan_base_mat = hcat([m.data.real_gdp for m in _scan_base]...)
    terminal_effects = Float64[]
    terminal_se = Float64[]
    for mult in shock_mults
        _scan_shocked = mult == 1.0 ? _scan_base :
            nb3_paths(n_shock_mc; shock=Nb3ProductivityShock(mult), seed=4042)
        shocked_mat = hcat([m.data.real_gdp for m in _scan_shocked]...)
        effects = 100 .* (shocked_mat[end, :] ./ scan_base_mat[end, :] .- 1)
        push!(terminal_effects, mean(effects))
        push!(terminal_se, std(effects) / sqrt(n_shock_mc))
    end
    plot(shock_mults, terminal_effects; ribbon=terminal_se, fillalpha=0.2,
        xlabel="Productivity multiplier", ylabel="GDP change at quarter 20 (%)",
        title="Proportionality check: persistent productivity change",
        marker=:circle, lw=2, color=:steelblue, label="Mean paired effect ± 1 MC SE")
    hline!([0.0]; label="Baseline", color=:grey, ls=:dash)
    vline!([1.0]; label="No change", color=:grey, ls=:dot)
end

# ╔═╡ 2c2790be-aeb1-11f1-9dfc-195170ee5996
md"""
**Test a prediction:** under a locally linear response, a −10% intervention would give
approximately twice the effect of −5%. Compare the 0.90 and 0.95 points and their ribbons.
Do not call any departure a bankruptcy threshold without checking the underlying firm
and bank outcomes. The graph combines all model mechanisms.
"""

# ╔═╡ 2c2790c8-aeb1-11f1-b03c-d1ce6d30fdbb
md"""
---
# Part 2 — Expectations and policy

Separate two mechanisms: domestic expectations feed production and pricing decisions,
while the policy rate is set from euro-area conditions. The second mechanism does not
provide direct feedback from Austrian inflation to the ECB in this calibration.
"""

# ╔═╡ 2c400cd6-aeb1-11f1-8bd9-e3408cd87a3a
md"""
> **Question:** how do forecast rules and the monetary-policy closure shape the simulated path?

### Learning goals
1. Read the learned AR(1) rule in the units used by the implementation.
2. Compare it with a last-observation rule without calling either rational expectations.
3. Change one Taylor-rule parameter at a time under the same initial seed.
4. Distinguish one illustrative trajectory from evidence across many simulations.
"""

# ╔═╡ 2c400cf2-aeb1-11f1-ae5a-436dbaaa2fe5
md"""
---
## 4 — Learned AR(1) forecasts

For a history `z`, `Bit.estimate_next_value(z)` fits an AR(1) with an intercept and returns

$$z^e_{t+1} = \alpha_t z_t + \beta_t + \varepsilon^e_{t+1}.$$

The coefficients are re-estimated by OLS each quarter. The implementation also draws a
forecast innovation from the fitted residual variance: this is a **stochastic learned
forecast**, not just the conditional mean and not perfect foresight.

`Bit.growth_inflation_expectations` applies the rule to **log GDP** and stored **log price
changes**. It exponentiates the forecasts to obtain a GDP level and simple inflation rate;
expected growth is forecast GDP divided by the latest GDP, minus one.
OLS fits the chosen forecasting rule to its history. It does not establish that the rule
is optimal for the evolving economy or that expectations are rational.
"""

# ╔═╡ 2c400d08-aeb1-11f1-a996-8bbad67ea5d0
md"""
---
## 5 — Learned AR(1) versus last-observation forecasts

- **Learned AR(1):** the default fitted rule, including its forecast innovation.
- **Last observation:** expect no GDP growth and repeat the last observed inflation rate.

Both use past observations. “Forward-looking” versus “backward-looking” would obscure that
shared information set. The last-observation rule also removes the default forecast
innovation, so this comparison changes both the forecast rule and its noise.

We specialise `Bit.growth_inflation_expectations` on a new model type rather than replacing
a package-wide function. That keeps the default rule intact for the other experiments.
"""

# ╔═╡ 2c400d10-aeb1-11f1-a78b-15b23274db5d
begin
    Bit.@object mutable struct Nb3LastValueModel(Bit.Model) <: Bit.AbstractModel end

    function Bit.growth_inflation_expectations(model::Nb3LastValueModel)
        idx = model.prop.T_prime + model.agg.t - 1
        last_output = model.agg.Y[idx]
        last_inflation = expm1(model.agg.pi_[idx])
        return last_output, zero(last_output), last_inflation
    end

    @bind run_expectations PlutoUI.Button("▶ Compare expectation rules (40 quarters)")
end

# ╔═╡ 2c400d1a-aeb1-11f1-a677-2582c519bb0e
begin
    run_expectations
    Random.seed!(1234)
    nb3_model_ar1 = Bit.Model(nb3_p, nb3_ic)
    Bit.run!(nb3_model_ar1, 40; parallel=false)

    Random.seed!(1234)
    nb3_const_initial = Bit.Model(nb3_p, nb3_ic)
    # Wrap components that Bit.Model has ALREADY initialised. Reinitialising the
    # tuple here would apply the shared balance-sheet normalisation twice.
    nb3_model_const = Nb3LastValueModel(
        nb3_const_initial.w_act, nb3_const_initial.w_inact, nb3_const_initial.firms,
        nb3_const_initial.bank, nb3_const_initial.cb, nb3_const_initial.gov,
        nb3_const_initial.rotw, nb3_const_initial.agg, nb3_const_initial.prop,
        nb3_const_initial.data)
    Bit.run!(nb3_model_const, 40; parallel=false)
    "Illustrative expectations comparison complete ✓"
end

# ╔═╡ 2c400d24-aeb1-11f1-a52a-91454431a7e5
begin
    run_expectations
    p_exp_gdp = plot(
        0:40, nb3_model_ar1.data.real_gdp, label = "Learned AR(1)",
        lw = 2, color = :steelblue, title = "Real GDP",
        xlabel = "Quarter",
    )
    plot!(p_exp_gdp, 0:40, nb3_model_const.data.real_gdp, label = "Last observation",
          lw = 2, color = :tomato, ls = :dash)

    p_exp_defl = plot(
        0:40, nb3_model_ar1.data.nominal_gdp ./ nb3_model_ar1.data.real_gdp, label = "Learned AR(1)",
        lw = 2, color = :steelblue, title = "GDP deflator",
        xlabel = "Quarter",
    )
    plot!(p_exp_defl, 0:40, nb3_model_const.data.nominal_gdp ./ nb3_model_const.data.real_gdp, label = "Last observation",
          lw = 2, color = :tomato, ls = :dash)

    plot(p_exp_gdp, p_exp_defl, layout = (1, 2), size = (800, 350))
end

# ╔═╡ 2c400d36-aeb1-11f1-9d4d-bd47b9b16653
md"""
**What does this comparison establish?** The two rules can generate different paths, but
one path does not establish which forecasts better or creates more volatility. The same
initial seed gives the same starting draws; removing forecast innovations changes subsequent
random-number use, so later external disturbances need not match.

For a stronger comparison, measure forecast errors and outcome dispersion across many
seeds, and explicitly replay the same external disturbances. Distinguish uncertainty across
simulations from fluctuations over time within one simulation.
"""

# ╔═╡ 2c400d42-aeb1-11f1-9d9d-4ba30acda0d6
md"""
---
## 6 — The Taylor rule

The implemented rule includes a real-rate intercept and a zero lower bound:

$$\bar r_t = \max\!\left\{0,\;\rho\bar r_{t-1} + (1-\rho)
\left[r^* + \pi^* + \xi^\pi(\pi^{EA}_t-\pi^*) + \xi^\gamma\gamma^{EA}_t\right]\right\}.$$

It responds to **euro-area** inflation and output growth, not Austrian conditions.
Rates, growth and inflation are quarterly fractions in the code. Multiplying a rate by
100 displays its quarterly percentage; it does not annualise it.

The sliders start at this notebook's actual calibration values. Confirm a change to one
coefficient, keeping the others fixed, then compare policy rates and domestic outcomes.
"""

# ╔═╡ 2c400d4c-aeb1-11f1-bacf-29a092bcd5b0
begin
    nb3_taylor_controls = @bind taylor_settings PlutoUI.confirm(PlutoUI.combine() do Child
        md"""
        **Smoothing ρ:** $(Child("rho", PlutoUI.Slider(sort(unique(vcat(collect(0.0:0.05:0.95), [0.99, Float64(nb3_p["rho"])]))); default=Float64(nb3_p["rho"]), show_value=true)))

        **Inflation weight ξπ:** $(Child("pi", PlutoUI.Slider(sort(unique(vcat(collect(0.0:0.1:3.0), [Float64(nb3_p["xi_pi"])]))); default=Float64(nb3_p["xi_pi"]), show_value=true)))

        **Growth weight ξγ:** $(Child("gamma", PlutoUI.Slider(sort(unique(vcat(collect(0.0:0.1:3.0), [Float64(nb3_p["xi_gamma"])]))); default=Float64(nb3_p["xi_gamma"]), show_value=true)))
        """
    end)
    rho_val = taylor_settings.rho
    xi_pi_val = taylor_settings.pi
    xi_gamma_val = taylor_settings.gamma
    nb3_taylor_controls
end

# ╔═╡ 2c400d56-aeb1-11f1-a60d-03f69defb6bb
@bind run_taylor PlutoUI.Button("▶ Run Taylor rule experiment (20 quarters)")

# ╔═╡ 2c400d60-aeb1-11f1-8282-0b6670bfafa2
begin
    run_taylor
    Random.seed!(42)

    # Default calibration
    nb3_m_default = Bit.Model(nb3_p, nb3_ic)
    Bit.run!(nb3_m_default, 20)

    # Custom Taylor rule via parameter modification
    nb3_params_custom = deepcopy(nb3_p)
    nb3_params_custom["rho"] = rho_val
    nb3_params_custom["xi_pi"] = xi_pi_val
    nb3_params_custom["xi_gamma"] = xi_gamma_val

    Random.seed!(42)
    nb3_m_custom = Bit.Model(nb3_params_custom, nb3_ic)
    Bit.run!(nb3_m_custom, 20)

    "Taylor experiment complete ✓"
end

# ╔═╡ 2c400d68-aeb1-11f1-8eaa-75087f418d06
begin
    run_taylor
    nb3_p1 = plot(
        0:20, nb3_m_default.data.euribor .* 100, label = "Calibrated rule",
        lw = 2, color = :steelblue,
        title = "Quarterly policy rate", xlabel = "Quarter", ylabel = "% per quarter",
    )
    plot!(nb3_p1, 0:20, nb3_m_custom.data.euribor .* 100,
          label = "Custom (ρ=$(rho_val), ξᵖ=$(xi_pi_val), ξᵞ=$(xi_gamma_val))",
          lw = 2, color = :tomato, ls = :dash)

    nb3_p2 = plot(
        0:20, nb3_m_default.data.real_gdp, label = "Default", lw = 2, color = :steelblue,
        title = "Real GDP", xlabel = "Quarter",
    )
    plot!(nb3_p2, 0:20, nb3_m_custom.data.real_gdp, label = "Custom", lw = 2, color = :tomato, ls = :dash)

    nb3_p3 = plot(
        nb3_m_default.data.nominal_gdp ./ 0:20, nb3_m_default.data.real_gdp, label = "Default", lw = 2, color = :steelblue,
        title = "GDP deflator", xlabel = "Quarter",
    )
    plot!(nb3_p3, 0:20, nb3_m_custom.data.nominal_gdp ./ nb3_m_custom.data.real_gdp, label = "Custom", lw = 2, color = :tomato, ls = :dash)

    plot(nb3_p1, nb3_p2, nb3_p3, layout = (1, 3), size = (900, 320), legend = :bottomright)
end

# ╔═╡ 2c400d7e-aeb1-11f1-9eae-8ba00ee10b4c
md"""
**Guided experiment:** first confirm the calibrated settings. The default and custom paths
should coincide. Next change only ρ, then only ξπ, returning to the calibration between trials.

- Lower ρ reduces interest-rate smoothing; check the rate panel before interpreting GDP.
- Higher ξπ increases the response to **euro-area** inflation, conditional on the lower bound.
- ξγ = 0 removes the growth term; it leaves the intercept, inflation response and smoothing.

Record the quarterly-rate difference in percentage points and the quarter-20 GDP difference
in percent. One seed illustrates a mechanism; repeat seeds before ranking policy rules.
"""

# ╔═╡ 2c400d92-aeb1-11f1-8cb4-5f0af2b94c90
md"""
**Fiscal closure:** taxes, transfers, government purchases and interest payments enter the
stock-flow accounts. Accounting consistency tells us where a payment goes; it does not by
itself show that fiscal behaviour is empirically correct. These plots do not decompose taxes
or government debt, so answering a fiscal question requires inspecting those series separately.
"""

# ╔═╡ 2c400d9a-aeb1-11f1-93cd-73e608b43691
md"""
---
## ✔ What you learned

- Persistent parameter changes differ from temporary shocks; the model still draws other disturbances.
- A paired no-change experiment should have zero effect. Seed each replicate and keep units explicit.
- Small ensembles can look nonlinear because of simulation noise; a GDP path alone does not identify a cascade.
- The default AR(1) rule is learned and stochastic. Our alternative is scoped to a new model type.
- The Taylor rule reacts to euro-area conditions, includes a real-rate intercept and floors rates at zero.

---
## Exercises — predict, run, explain, check

**03.1 — A diagnostic, not a result.** Set the shock multiplier to 1.0 and confirm.
Check all four panels. Why would independent unpaired simulations fail to give exact zero?
*Hint:* compare each baseline path with its own unchanged copy before averaging.

**03.2 — Intervention timing.** Compare productivity multipliers 0.95 and 0.90 at quarter 20.
Is the larger effect twice the smaller one, within simulation precision?
*Check:* use the same seeds and increase paths before interpreting curvature. Explain why
this is a persistent productivity change even though the hook mutates the parameter once.

**03.3 — Policy closure.** Set ξπ = 0, leaving other coefficients calibrated.
Before running, identify the external series the central bank now ignores.
*Check:* distinguish a GDP-deflator level from an inflation rate and a quarterly rate from
an annual rate. Do not infer a direct response to Austrian inflation.

**03.4 — Two meanings of volatility.** Run each expectation rule under at least eight seeds.
Compute GDP's standard deviation **across runs at quarter 20**, then compare it with the
standard deviation **over time within a run**. They answer different questions.
*Hint:* `data.real_gdp[21]` is quarter 20 because index 1 is the initial observation.
Report the seed count and avoid a universal ranking from one trajectory.

**03.5 — Stretch: a different monetary institution.** Create a custom model type and
specialise `Bit.central_bank_rate(model::YourModel)`. Use domestic inflation in the rule,
converting stored log inflation with `expm1`, and retain its intercept and zero lower bound.
*Check:* this changes the monetary closure; it is no longer Austria taking the ECB rate as given.
"""

# ╔═╡ Cell order:
# ╠═2bd3ccb6-aeb1-11f1-b3bc-4d70a471e508
# ╟─2c278ede-aeb1-11f1-a840-0d3b6fe012e3
# ╠═2c278f24-aeb1-11f1-af9b-c5924659f871
# ╟─2c278f44-aeb1-11f1-a7d6-0786c7458453
# ╠═2c278f56-aeb1-11f1-b435-15c27b8085c2
# ╠═2c278f60-aeb1-11f1-9aef-412714939caf
# ╠═2c278f76-aeb1-11f1-a61e-491164534635
# ╟─2c278f9c-aeb1-11f1-860a-63e91f994997
# ╟─2c278fb0-aeb1-11f1-a8fa-0331ace63bdd
# ╟─2c278fc4-aeb1-11f1-b35e-b9290280c086
# ╠═2c278fe2-aeb1-11f1-8f5f-f31c275bbd10
# ╠═2c278ff6-aeb1-11f1-b5b6-39ae723b6717
# ╠═2c27901e-aeb1-11f1-97bb-0d095ecd46fd
# ╟─2c279032-aeb1-11f1-93a6-310284d02e04
# ╟─2c279050-aeb1-11f1-9ab8-f37ad5c40d3b
# ╟─2c27906e-aeb1-11f1-b728-01a680a89df4
# ╠═2c279078-aeb1-11f1-90c0-ddb27eeda0a6
# ╠═2c2790a0-aeb1-11f1-80f1-9736724f909d
# ╟─2c2790be-aeb1-11f1-9dfc-195170ee5996
# ╟─2c2790c8-aeb1-11f1-b03c-d1ce6d30fdbb
# ╟─2c400cd6-aeb1-11f1-8bd9-e3408cd87a3a
# ╟─2c400cf2-aeb1-11f1-ae5a-436dbaaa2fe5
# ╟─2c400d08-aeb1-11f1-a996-8bbad67ea5d0
# ╠═2c400d10-aeb1-11f1-a78b-15b23274db5d
# ╠═2c400d1a-aeb1-11f1-a677-2582c519bb0e
# ╠═2c400d24-aeb1-11f1-a52a-91454431a7e5
# ╟─2c400d36-aeb1-11f1-9d4d-bd47b9b16653
# ╟─2c400d42-aeb1-11f1-9d9d-4ba30acda0d6
# ╟─2c400d4c-aeb1-11f1-bacf-29a092bcd5b0
# ╠═2c400d56-aeb1-11f1-a60d-03f69defb6bb
# ╠═2c400d60-aeb1-11f1-8282-0b6670bfafa2
# ╠═2c400d68-aeb1-11f1-8eaa-75087f418d06
# ╟─2c400d7e-aeb1-11f1-9eae-8ba00ee10b4c
# ╟─2c400d92-aeb1-11f1-8cb4-5f0af2b94c90
# ╟─2c400d9a-aeb1-11f1-93cd-73e608b43691
