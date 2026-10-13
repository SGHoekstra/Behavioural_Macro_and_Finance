### A Pluto.jl notebook ###
# v0.20.24

#> [frontmatter]
#> order = 3
#> title = "Calibration, no-burn-in and forecasting"
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

# ╔═╡ b25815ec-aeb8-11f1-9f19-c1af47b3dc37
begin
    import Pkg
    Pkg.activate(dirname(@__FILE__))
    import BeforeIT as Bit
    import Random
    using Plots, PlutoUI, DataFrames, Statistics, StatsBase
end

# ╔═╡ b293063e-aeb8-11f1-9e88-8b4fe9232048
md"""
# Notebook 02 — Calibration, no-burn-in and forecasting

> **Economic question:** how does a model start from an observed economy, and what evidence would make its forecasts credible?

First inspect the calibration and balance sheets, then compare two initialisation experiments
and two countries. Next build a Monte Carlo forecast and an AR(1) benchmark. Their final
comparison shows **forecast disagreement**, not accuracy: there are no held-out outcomes in it.

### Lecture 2 slides covered
- *Data-based initialisation & no burn-in*, *Data Sources* and *How big is the model?*
- *Calibration Process* and *The full parameter set: (almost) no free parameters*
- *Out-of-sample forecast performance* and *Quarterly out-of-sample GDP forecast decomposition*

### Learning goals
1. Distinguish data-derived quantities, estimated coefficients and calibration choices.
2. Read initial sector balance sheets and recognise their units.
3. Test whether GDP remains near its initial level under different exogenous processes.
4. Compare country calibrations without attributing every difference to one parameter.
5. Build and interpret a fan chart, an AR(1) forecast and a horizon comparison table.

### How to work through this notebook
Predict an effect before running an experiment, inspect the plot, and explain any surprise using
the model's mechanisms. Defaults run when the notebook opens so the online version contains plots.
For the expensive Monte Carlo section, change settings together and press **Apply**. Repeat buttons
rerun the current settings; they do not pause other reactive cells.
"""

# ╔═╡ b293067c-aeb8-11f1-ad5a-6b89548f4a6b
begin
    nb2_p_AT  = Bit.AUSTRIA2010Q1.parameters
    nb2_ic_AT = Bit.AUSTRIA2010Q1.initial_conditions
    nb2_p_IT  = Bit.ITALY2010Q1.parameters
    nb2_ic_IT = Bit.ITALY2010Q1.initial_conditions
    "Calibrations loaded: Austria and Italy ✓"
end

# ╔═╡ b2930690-aeb8-11f1-b26d-7d15154cf812
md"""
---
## 1 — Where do the parameters come from?

The lecture groups the calibration into census/business demography, input-output tables,
government statistics, regulatory or behavioural choices, and estimated time-series blocks.
The table below is a **selection**, not the complete dictionary. Some quantities live in
`model.prop`; firm characteristics and central-bank coefficients live in their own objects.

Counts are **simulated agents**, shares and tax rates are fractions, and the inflation target
is a quarterly rate. Tax rates derived from accounts are effective rates rather than necessarily
statutory rates. The consumption propensity `ψ` is a behavioural rule calibrated from income
and consumption; its label does not imply an independently identified causal marginal propensity.

**Before inspecting the values:** which quantities describe the initial economy, and which tell
agents how to behave? Explore the full dictionary with `sort(collect(keys(nb2_p_AT)))`.
"""

# ╔═╡ b29306b8-aeb8-11f1-b039-b9a728d6c227
begin
    _nb03_m_p = Bit.Model(nb2_p_AT, nb2_ic_AT)
    p = _nb03_m_p.prop

    param_table = DataFrame(
        "Source / block" => [
            "Census / scaled counts", "Census / scaled counts", "Census / scaled counts", "Scaled counts",
            "I-O tables", "I-O / sector accounts", "I-O tables",
            "Government / sector accounts", "Government / sector accounts", "Government / sector accounts",
            "Government / sector accounts", "Government / sector accounts", "Government / sector accounts",
            "Regulatory / calibration choice", "Regulatory / calibration choice", "Benefit calibration",
            "Estimated (export AR(1))", "Estimated (export AR(1))", "Estimated (government AR(1))",
            "Policy target (Taylor rule)", "Estimated (Taylor rule)", "Estimated (Taylor rule)", "Estimated (Taylor rule)",
        ],
        "Quantity" => [
            "H_act", "H_inact", "I (firms)", "J (government entities)",
            "a_sg (matrix dimensions)", "ᾱ_i (mean labour productivity)", "b_HH_g (mean consumption share)",
            "τ^INC", "τ^VAT", "τ^FIRM", "τ^SIF", "ψ (consumption propensity)", "θ^DIV (payout share)",
            "ζ (capital requirement)", "ζ_LTV", "θ_UB (benefit replacement rate)",
            "α_E (export persistence)", "β_E (export intercept)", "σ_G (government innovation scale)",
            "π* (quarterly target)", "ρ (rate smoothing)", "ξ^π (inflation response)", "ξ^γ (growth response)",
        ],
        "Value" => [
            p.H_act, p.H_inact, p.I, p.J,
            "$(size(p.a_sg))", round(mean(_nb03_m_p.firms.alpha_bar_i), digits=4), round(mean(p.b_HH_g), digits=4),
            round(p.tau_INC, digits=4), round(p.tau_VAT, digits=4), round(p.tau_FIRM, digits=4),
            round(p.tau_SIF, digits=4), round(p.psi, digits=4), round(p.theta_DIV, digits=4),
            round(p.zeta, digits=4), round(p.zeta_LTV, digits=4), round(p.theta_UB, digits=4),
            round(nb2_p_AT["alpha_E"], digits=4), round(nb2_p_AT["beta_E"], digits=4), round(nb2_p_AT["sigma_G"], digits=4),
            round(_nb03_m_p.cb.pi_star, digits=4), round(_nb03_m_p.cb.rho, digits=4),
            round(_nb03_m_p.cb.xi_pi, digits=4), round(_nb03_m_p.cb.xi_gamma, digits=4),
        ],
    )
    param_table
end

# ╔═╡ b29306cc-aeb8-11f1-b9dd-1760a9f7c6e4
md"""
**Read the table critically.** Data discipline many quantities, but the calibration also includes
estimated exogenous processes, a policy rule and adopted behavioural/regulatory choices.
The last rows are examples of estimated blocks, not all estimated coefficients. Initialising
from data does not by itself validate forecasts or policy experiments.

The mean consumption share hides composition because shares sum to one: inspect `p.b_HH_g`
itself. An unweighted mean of firm productivity also hides its sectoral distribution. Matching
an aggregate need not reproduce the heterogeneity relevant to an economic mechanism.
"""

# ╔═╡ b29306e0-aeb8-11f1-b7a4-3dd934fc3956
md"""
---
## 2 — Initial balance sheets

National and sector accounts supply aggregate stocks, which initialisation allocates across
simulated agents. This is a data-consistent construction, not an observed balance sheet for every
individual household. The household sector includes active and inactive workers, firm owners
and the bank owner; counting active workers alone would omit some household deposits.

**Units matter:** deposits, loans and equity are stocks in the calibration's monetary units,
whereas the policy rate is a fraction per quarter. Do not interpret a raw value as an individual
amount in euros, or compare a rate with a monetary stock.
"""

# ╔═╡ b29306f4-aeb8-11f1-b90e-27a20a09c353
begin
    model_AT = Bit.Model(nb2_p_AT, nb2_ic_AT)
    nb2_household_deposits = sum(model_AT.w_act.D_h) + sum(model_AT.w_inact.D_h) +
                             sum(model_AT.firms.D_h) + model_AT.bank.D_h

    bs_table = DataFrame(
        "Quantity" => ["Household deposits (all household types)", "Firm deposits (sum)",
                       "Firm debt (sum)", "Bank equity", "Government debt", "Initial policy rate"],
        "Value" => [round(nb2_household_deposits, sigdigits=5), round(sum(model_AT.firms.D_i), sigdigits=5),
                    round(sum(model_AT.firms.L_i), sigdigits=5), round(model_AT.bank.E_k, sigdigits=5),
                    round(model_AT.gov.L_G, sigdigits=5), round(model_AT.cb.r_bar, digits=5)],
        "Unit" => [fill("Calibration monetary units", 5); "Fraction per quarter"],
    )
    bs_table
end

# ╔═╡ b2930714-aeb8-11f1-abe4-5d52a2a3d662
md"""
---
## 3 — Testing the no-burn-in idea

A burn-in discards an initial stretch of simulation because the starting state creates artificial
transients. Data-based initialisation aims to make the model useful from the reference quarter.
The lecture's stronger diagnostic suppresses growth processes and asks whether the model
fluctuates around its initial conditions. The experiment below is narrower: it changes three
correlated innovations while retaining the empirical histories used to form expectations.

Compare two scenarios over **20 quarters (five years)**:
1. **Baseline:** Austria 2010:Q1 with its normal stochastic processes.
2. **Correlated innovations off (`C=0`):** zero the covariance matrix for euro-area GDP,
   export demand and import supply. Their deterministic AR(1) terms remain. Government
   consumption and euro-area inflation still draw innovations using separate scalar `σ` values.

**A no-growth comparison needs an expectations rule too.** `Bit.STEADY_STATE2010Q1` fixes
exogenous processes and policy, and flattens the histories used by adaptive expectations.
A constant history cannot identify an AR(1) slope and intercept separately; the default
refitting can fail numerically. That calibration is therefore not simulated in this exercise.
An initial accounting balance alone does not establish a dynamically stable steady state.
The horizontal line in the plot marks initial GDP, not a simulated steady-state path.

**Predict, then inspect:** should removing these innovations reduce drift? Why is `C=0` not a
complete no-growth experiment? Compare the paths, but do not treat either as a full test of the
lecture's no-burn-in claim or a proof that the calibrated economy is an exact fixed point.
"""

# ╔═╡ b293071c-aeb8-11f1-acbf-7f82e962da0c
@bind run_noburn PlutoUI.CounterButton("↻ Repeat initialisation comparison (2 × 20 quarters)")

# ╔═╡ b293074e-aeb8-11f1-b819-abbb938d2334
begin
    run_noburn
    Random.seed!(42)
    model_shocks_on = Bit.Model(nb2_p_AT, nb2_ic_AT)
    Bit.run!(model_shocks_on, 20)

    # C silences three correlated innovations, not all stochasticity.
    Random.seed!(42)
    model_no_shocks = Bit.Model(nb2_p_AT, nb2_ic_AT)
    model_no_shocks.prop.C .= 0.0
    Bit.run!(model_no_shocks, 20)

    "Two 20-quarter simulations complete. A fixed seed aids reproducibility; each scenario has different dynamics."
end

# ╔═╡ 0a77cff2-b9b5-4b86-b669-9bdb8a262131
begin
    gdp_on = model_shocks_on.data.real_gdp
    gdp_off = model_no_shocks.data.real_gdp
    # Index each simulated scenario to its own initial value.
    nb2_index_on = 100 .* gdp_on ./ first(gdp_on)
    nb2_index_off = 100 .* gdp_off ./ first(gdp_off)
    nothing
end

# ╔═╡ b2930762-aeb8-11f1-a537-7fa2dec3ab68
begin

    p3 = plot(0:20, nb2_index_on, label="Baseline", lw=2, color=:steelblue,
              title="Initialisation comparison: real GDP", xlabel="Quarters after initialisation",
              ylabel="Index (own t=0 = 100)")
    plot!(p3, 0:20, nb2_index_off, label="Correlated innovations off (C=0)", lw=2, color=:crimson, ls=:dash)
    hline!(p3, [100], label="Initial GDP (reference)", color=:grey, ls=:dot)

    p4 = plot(0:20, nb2_index_on .- 100, label="Baseline", color=:steelblue, lw=2,
              title="GDP deviation from each scenario's initial value", xlabel="Quarters after initialisation",
              ylabel="Percent deviation")
    plot!(p4, 0:20, nb2_index_off .- 100, label="Correlated innovations off (C=0)", color=:crimson, lw=2, ls=:dash)
    hline!(p4, [0], color=:black, lw=1, label="")
    plot(p3, p4, layout=(2, 1), size=(750, 580))
end

# ╔═╡ b2930778-aeb8-11f1-87c2-fdbcbfda5da2
begin
    dev_on = maximum(abs.(nb2_index_on .- 100))
    dev_off = maximum(abs.(nb2_index_off .- 100))
    Markdown.parse("""
    | Scenario | Maximum absolute GDP deviation from own t=0 (20 quarters) |
    |---|---|
    | Baseline | **$(round(dev_on, digits=2))%** |
    | Correlated innovations off (`C=0`) | **$(round(dev_off, digits=2))%** |

    The table measures the largest departure along each single path. It is neither a forecast
    error nor an across-path standard deviation. In the `C=0` run, deterministic terms,
    the two remaining exogenous innovations and market matching can still move GDP.

    **Interpretation task:** does the observed ordering agree with your prediction? Explain
    remaining movement before generalising. These paths illustrate initialisation under two
    stochastic specifications. Fixed seeds make the examples reproducible; a difference between
    single paths does not measure an isolated causal effect. Neither establishes that every
    country or policy experiment starts at an exact fixed point.
    """)
end

# ╔═╡ b293078a-aeb8-11f1-84ec-4bfed0885b59
md"""
---
## 4 — Austria vs Italy

Compare the Austria and Italy 2010:Q1 calibrations. Counts refer to the scaled simulation,
not literal national populations. Taxes, spending rules, industry structure, initial stocks
and exogenous processes all change together.

**Prediction:** select one row and explain how it could affect demand or income. The country
comparison shows joint differences; identifying that row's effect would require changing it
alone while holding the rest of the calibration fixed.
"""

# ╔═╡ b29307a6-aeb8-11f1-b3c2-a98e06704a0e
begin
    pAT = Bit.Model(nb2_p_AT, nb2_ic_AT).prop
    pIT = Bit.Model(nb2_p_IT, nb2_ic_IT).prop

    comparison = DataFrame(
        "Parameter"   => ["Consumption propensity ψ", "τ^INC", "τ^VAT", "τ^FIRM",
                          "θ^UB (unempl. benefit)", "θ^DIV (dividend payout)",
                          "ζ (min. capital ratio)", "H_act", "I (firms)"],
        "Austria"     => [pAT.psi, pAT.tau_INC, pAT.tau_VAT, pAT.tau_FIRM,
                          pAT.theta_UB, pAT.theta_DIV, pAT.zeta,
                          pAT.H_act, pAT.I],
        "Italy"       => [pIT.psi, pIT.tau_INC, pIT.tau_VAT, pIT.tau_FIRM,
                          pIT.theta_UB, pIT.theta_DIV, pIT.zeta,
                          pIT.H_act, pIT.I],
    )
    comparison
end

# ╔═╡ b29307bc-aeb8-11f1-96ec-19bde3d822a6
@bind run_countries PlutoUI.CounterButton("↻ Repeat Austria–Italy comparison (20 quarters each)")

# ╔═╡ b293080c-aeb8-11f1-9991-eb2293054cd3
begin
    run_countries
    Random.seed!(42)
    _m_AT = Bit.Model(nb2_p_AT, nb2_ic_AT)
    Bit.run!(_m_AT, 20)
    Random.seed!(42)
    _m_IT = Bit.Model(nb2_p_IT, nb2_ic_IT)
    Bit.run!(_m_IT, 20)

    gdp_AT_norm = _m_AT.data.real_gdp ./ first(_m_AT.data.real_gdp) .* 100
    gdp_IT_norm = _m_IT.data.real_gdp ./ first(_m_IT.data.real_gdp) .* 100
    inf_AT = _m_AT.data.nominal_gdp ./ _m_AT.data.real_gdp
    inf_IT = _m_IT.data.nominal_gdp ./ _m_IT.data.real_gdp

    p1 = plot(0:20, gdp_AT_norm, label="Austria", lw=2, color=:steelblue,
              title="Real GDP", xlabel="Quarters after initialisation", ylabel="Index (own t=0 = 100)")
    plot!(p1, 0:20, gdp_IT_norm, label="Italy", lw=2, color=:tomato)
    p2 = plot(0:20, inf_AT, label="Austria", lw=2, color=:steelblue,
              title="GDP deflator", xlabel="Quarters after initialisation", ylabel="Price index (t=0 = 1)")
    plot!(p2, 0:20, inf_IT, label="Italy", lw=2, color=:tomato)
    plot(p1, p2, layout=(1, 2), size=(800, 350), legend=:topright)
end

# ╔═╡ b2930820-aeb8-11f1-8e85-51d538e6971f
md"""
**Read both panels:** GDP is indexed to compare growth paths, not country size. The deflator is
`nominal_gdp / real_gdp`, a price-level index, **not an inflation rate**. Quarter-on-quarter
inflation would be `100 .* diff(deflator) ./ deflator[1:end-1]`.

Different paths do not establish that an MPC, tax or benefit parameter caused the whole
difference. Even with the same seed, differing calibrations do not imply identical shocks.
"""

# ╔═╡ b293083e-aeb8-11f1-8891-598f6f05cbd2
md"""
---
# Part 2 — Forecasting

Data-based initialisation gives the forecast an observed reference point without discarding
an artificial spin-up. It does not guarantee forecast accuracy. We now separate three questions:
where does the model predict GDP will go, how dispersed are its paths, and what held-out data
would be needed to decide whether it forecasts well?
"""

# ╔═╡ b2afa2fa-aeb8-11f1-b9b3-f75d094ff641
md"""
### Forecasting learning goals
1. Build a multi-path Monte Carlo forecast and distinguish path quantiles from confidence intervals.
2. Estimate a simple AR(1) benchmark using only the pre-forecast history.
3. Compare forecasts in the same units at horizons that were actually simulated.
4. Explain how conditional forecasting changes the available information.

The lecture's forecast comparisons refer to the Poledna et al. study, published in 2023
(earlier drafts appear in the slides). This short experiment teaches the workflow; it does
not reproduce the published forecast evaluation.
"""

# ╔═╡ b2afa318-aeb8-11f1-9a41-b1574df0a926
md"""
---
## 5 — Monte Carlo fan chart

A fan chart summarises simulated paths **conditional on the same calibration and initial state**.
The published forecasting exercise uses hundreds of paths per reference quarter. Start here
with **10 paths over eight quarters**, then increase the budget only when you need a more stable
estimate of the mean or quantiles.

All paths start from Austria's **2010:Q1** calibration. One quarter is one model step, and array
entry `h+1` is horizon `h` because the first entry is the initial state. We index each path to
100 at that point. The 10–90% and 25–75% bands describe model-generated dispersion; they are
not confidence intervals for the ensemble mean or empirically verified coverage probabilities.

**Make a prediction:** will increasing the number of paths remove economic uncertainty, or
only make its simulation estimate less noisy? Change settings below, then press **Apply** once.
"""

# ╔═╡ b2afa322-aeb8-11f1-86b7-7996bf33c307
@bind nb2_fc_settings PlutoUI.confirm(PlutoUI.combine() do Child
    md"""
    **Forecast settings**

    Paths: $(Child("paths", PlutoUI.Slider([5, 10, 20, 50, 100, 200], default=10, show_value=true)))

    Quarters ahead: $(Child("horizon", PlutoUI.Slider(4:4:40, default=8, show_value=true)))

    Random seed: $(Child("seed", PlutoUI.Slider(1:3000, default=2019, show_value=true, max_steps=3000)))
    """
end)

# ╔═╡ b2afa322-aeb8-11f1-9614-65079b45f80c
begin
    n_mc_fc = nb2_fc_settings.paths
    T_fc = nb2_fc_settings.horizon
    seed_fc = nb2_fc_settings.seed
    Markdown.parse("Applied budget: **$(n_mc_fc) paths × $(T_fc) quarters**; seed **$(seed_fc)**. The initial state adds one observation to every path.")
end

# ╔═╡ b2afa32c-aeb8-11f1-8898-c1cd175b3425
@bind run_fc PlutoUI.CounterButton("↻ Repeat forecast with the applied settings and seed")

# ╔═╡ b2afa336-aeb8-11f1-a55b-e75364320332
begin
    run_fc
    Random.seed!(seed_fc)
    # Serial execution makes this small teaching example reproducible independently of thread count.
    _mc_models = Bit.ensemblerun!(
        (Bit.Model(nb2_p_AT, nb2_ic_AT) for _ in 1:n_mc_fc),
        T_fc; parallel=false,
    )
    "Forecast complete: $(n_mc_fc) paths × $(T_fc) quarters."
end

# ╔═╡ 80f08e04-b55e-47b7-8c86-fd45195df8bd
begin
    # Rows are horizons 0:T_fc; columns are Monte Carlo paths.
    nb2_gdp_mat = hcat([m.data.real_gdp for m in _mc_models]...)
    nb2_gdp_index_mat = 100 .* nb2_gdp_mat ./ nb2_gdp_mat[1:1, :]
    nb2_gdp_mean = vec(mean(nb2_gdp_index_mat, dims=2))
    nb2_gdp_p10 = [quantile(nb2_gdp_index_mat[t, :], 0.10) for t in 1:(T_fc+1)]
    nb2_gdp_p25 = [quantile(nb2_gdp_index_mat[t, :], 0.25) for t in 1:(T_fc+1)]
    nb2_gdp_p75 = [quantile(nb2_gdp_index_mat[t, :], 0.75) for t in 1:(T_fc+1)]
    nb2_gdp_p90 = [quantile(nb2_gdp_index_mat[t, :], 0.90) for t in 1:(T_fc+1)]
    nothing
end

# ╔═╡ b2afa340-aeb8-11f1-8dd6-d3320810d4d9
begin

    # Draw bands by their endpoints: a skewed distribution's mean need not lie inside every band.
    p_fan = plot(0:T_fc, nb2_gdp_p10, fillrange=nb2_gdp_p90, fillalpha=0.15,
                 color=:steelblue, lw=0, label="10–90% of paths",
                 title="ABM real GDP forecast ($(n_mc_fc) paths)", xlabel="Quarters ahead",
                 ylabel="Index (2010:Q1 = 100)")
    plot!(p_fan, 0:T_fc, nb2_gdp_p25, fillrange=nb2_gdp_p75, fillalpha=0.25,
          color=:steelblue, lw=0, label="25–75% of paths")
    plot!(p_fan, 0:T_fc, nb2_gdp_mean, color=:steelblue, lw=2, label="Ensemble mean")
end

# ╔═╡ b2afa340-aeb8-11f1-bb47-d38b51bec0f3
md"""
**Reading the fan:** the darker band contains the central half of simulated paths at each horizon;
the lighter band contains the central 80%. The mean is a separate line. Dispersion comes from
the model's stochastic processes and matching, with parameters fixed.

Longer horizons often have wider bands, but mean reversion, nonlinear dynamics and a small
Monte Carlo sample can make widths non-monotonic. More paths stabilise estimated quantiles;
they need not systematically narrow the underlying forecast distribution.
"""

# ╔═╡ b2afa34c-aeb8-11f1-af46-291c0386f1cf
md"""
---
## 6 — Historical trajectory and forecast overlay

The history in `initial_conditions["Y"]` follows the historical real-GDP trajectory,
rescaled to the model's output units during calibration. Its raw level is therefore not the
same object as the model's value-added measure `data.real_gdp`. Index each series to **100
at its own 2010:Q1 value** before overlaying them.

The black line ends at the forecast origin. It supplies information available for fitting the
benchmark; it is **not** a held-out future trajectory against which accuracy can be assessed.
"""

# ╔═╡ b2afa354-aeb8-11f1-a065-3f7be16f752a
begin
    Y_hist_raw = vec(nb2_ic_AT["Y"])
    T_hist = length(Y_hist_raw)
    Y_hist_norm = 100 .* Y_hist_raw ./ last(Y_hist_raw)
    fc_norm_mean = nb2_gdp_mean
    fc_norm_p10 = nb2_gdp_p10
    fc_norm_p90 = nb2_gdp_p90
    x_hist = (-(T_hist-1)):0
    x_fc = 0:T_fc

    p_hist = plot(x_hist, Y_hist_norm, lw=2, color=:black, label="Historical trajectory (indexed)",
                  title="History and forecast: Austria 2010:Q1", xlabel="Quarters relative to 2010:Q1",
                  ylabel="Index (2010:Q1 = 100)")
    plot!(p_hist, x_fc, fc_norm_p10, fillrange=fc_norm_p90, fillalpha=0.15,
          color=:steelblue, lw=0, label="ABM 10–90% path band")
    plot!(p_hist, x_fc, fc_norm_mean, color=:steelblue, lw=2, label="ABM ensemble mean")
    vline!(p_hist, [0], lw=1.5, ls=:dash, color=:grey, label="Forecast origin")
end

# ╔═╡ b2afa372-aeb8-11f1-8640-1fe8cf76ca5c
md"""
**Check the join:** both history and forecast equal 100 at horizon zero. Indexing preserves
relative movements but removes differences in level and units. It is useful for this teaching
comparison; it does not establish equality of the original accounting quantities.

The fan reflects stochastic paths at a fixed parameter calibration, including random matching,
rather than parameter uncertainty. A proper out-of-sample evaluation repeats the forecast at
multiple reference quarters and compares predictions with subsequently observed GDP. The
published application evaluates a sequence of reference quarters rather than this single origin.
"""

# ╔═╡ b2afa390-aeb8-11f1-9b7c-6dcb8a3b7349
md"""
---
## 7 — A simple AR(1) benchmark

Construct an intentionally simple benchmark using only the history up to the forecast origin:
`y_t = β + α*y_(t-1) + ε_t`. OLS chooses the intercept `β` and persistence `α`.
Recursively applying `β + α*y` gives a point forecast; no random innovation is added to it.

Follow the code in three steps:
1. Align `y_lag` and `y_now` so each row contains adjacent observations.
2. Add a column of ones for the intercept, then solve the least-squares system with `X \\ y_now`.
3. Start the recursive forecast at the last historical value, then index it to 100 for comparison.

This is an AR(1) in **levels**, not an exact replication of the lecture's benchmark scripts,
which use log differences for GDP and other variables. Transformations, estimation windows
and data vintages matter when comparing forecast accuracy. A levels estimate near or above
unit persistence can imply drifting or explosive long-horizon paths; inspect `α`.
"""

# ╔═╡ b2afa39a-aeb8-11f1-b8bc-e9c07f6758d2
begin
    Y_hist = vec(nb2_ic_AT["Y"])
    @assert length(Y_hist) >= 3 && all(isfinite, Y_hist) "AR(1) needs a finite historical series."
    y_lag = Y_hist[1:end-1]
    y_now = Y_hist[2:end]

    # A row of X is [1, y_(t-1)]; coefficients are [intercept, persistence].
    X = hcat(ones(length(y_lag)), y_lag)
    coef = X \ y_now
    β_ar1, α_ar1 = coef

    ar1_forecast = zeros(T_fc + 1)
    ar1_forecast[1] = last(Y_hist)
    for t in 2:(T_fc+1)
        ar1_forecast[t] = β_ar1 + α_ar1 * ar1_forecast[t-1]
    end
    (persistence=round(α_ar1, digits=4), intercept=round(β_ar1, digits=4))
end

# ╔═╡ 83758030-7ed7-40a5-9910-45c92caf1408
begin
    ar1_norm = 100 .* ar1_forecast ./ first(ar1_forecast)
    nothing
end

# ╔═╡ b2afa3a4-aeb8-11f1-890c-c75acb76f4a5
begin
    gdp_norm = nb2_gdp_mean
    p10_norm = nb2_gdp_p10
    p90_norm = nb2_gdp_p90

    p_benchmark = plot(0:T_fc, p10_norm, fillrange=p90_norm, fillalpha=0.15,
                       color=:steelblue, lw=0, label="ABM 10–90% path band",
                       title="Forecast disagreement: ABM and levels AR(1)",
                       xlabel="Quarters ahead", ylabel="Index (2010:Q1 = 100)")
    plot!(p_benchmark, 0:T_fc, gdp_norm, color=:steelblue, lw=2, label="ABM ensemble mean")
    plot!(p_benchmark, 0:T_fc, ar1_norm, color=:tomato, lw=2, ls=:dash, label="AR(1) point forecast")
end

# ╔═╡ b2afa3b0-aeb8-11f1-b0c2-4b6ae274fab9
md"""
---
## 8 — Forecast divergence at selected horizons

Compare the indexed AR(1) point forecast with the indexed ABM distribution. The table reports:
- **Absolute mean gap:** forecast disagreement in index points.
- **ABM path standard deviation:** across-path dispersion in the same units.
- **Gap / ABM standard deviation:** disagreement relative to model dispersion; undefined when dispersion is zero.
- **Within the 10–90% band:** whether the benchmark lies between those path quantiles.

A gap of one standard deviation is a descriptive scale, not a significance test. Being inside
the fan does not make the AR(1) accurate, and being outside does not make the ABM accurate.
Neither forecast is compared with a realised outcome here. Only horizons within the applied
simulation length are included.
"""

# ╔═╡ b2afa3c2-aeb8-11f1-9ab0-bd059ee19dd4
begin
    horizons = filter(h -> h <= T_fc, [1, 2, 4, 8])
    nb2_mean_gaps = Float64[]
    nb2_path_spreads = Float64[]
    nb2_scaled_gaps = Union{Missing, Float64}[]
    nb2_inside_band = Bool[]

    for h in horizons
        ar1_val = ar1_norm[h+1]
        abm_val = nb2_gdp_mean[h+1]
        gap = abs(ar1_val - abm_val)
        spread = std(nb2_gdp_index_mat[h+1, :])
        push!(nb2_mean_gaps, gap)
        push!(nb2_path_spreads, spread)
        push!(nb2_scaled_gaps, spread > 0 ? gap / spread : missing)
        push!(nb2_inside_band, nb2_gdp_p10[h+1] <= ar1_val <= nb2_gdp_p90[h+1])
    end

    nb2_divergence_table = DataFrame(
        "Horizon (quarters)" => horizons,
        "Absolute mean gap (index points)" => round.(nb2_mean_gaps, digits=3),
        "ABM path std (index points)" => round.(nb2_path_spreads, digits=3),
        "Gap / ABM std" => map(x -> ismissing(x) ? missing : round(x, digits=2), nb2_scaled_gaps),
        "Within 10–90% path band" => nb2_inside_band,
    )
    nb2_divergence_table
end

# ╔═╡ b2afa3d6-aeb8-11f1-8991-db6bbeb7d2cf
md"""
### What would a proper forecast evaluation add?

For each reference quarter, use only the information available then, simulate the required
horizons, and compare point forecasts with **held-out observed values**. For a fixed horizon,
RMSE is `sqrt(mean((forecast .- realised).^2))` across forecast origins. Report its units
and compare benchmarks using the same origins, horizons, information and transformations.
Across-path standard deviation is not RMSE, and the ABM mean is not observed truth.

The lecture repository's `../lecture_2_sfc_abm/tabs/error_table_*.jl` scripts show the
larger evaluation workflow and require their own data. This notebook does not run that pipeline.

**Conditional forecasting** fixes selected exogenous paths, for example external demand or
government consumption, instead of drawing them. Realised future paths provide hindsight;
scenario paths supply assumed information. Such forecasts can reveal how external developments
contribute to errors, but should be compared with benchmarks given the same information.
"""

# ╔═╡ b2afa3de-aeb8-11f1-a74f-c52b1df4ff4a
md"""
---
## ✔ What you learned

- Data-derived initial stocks, estimated coefficients and calibration choices have different roles.
- Aggregate household deposits include workers, inactive households and owners. Financial stocks
  and quarterly rates need separate unit labels.
- `C=0` removes three correlated innovations; it leaves deterministic dynamics, two other
  exogenous innovations and random matching. A full no-growth diagnostic also needs a
  well-defined expectations rule; an accounting reference is not a simulated steady state.
- GDP indices and deflator levels describe different objects; inflation is a change in the deflator.
- Monte Carlo quantiles describe fixed-calibration path dispersion, not uncertainty in the mean.
- A levels AR(1) is a teaching benchmark. Indexed forecast disagreement is not out-of-sample accuracy.

---
## Exercises — predict, implement, explain

Work through 02.1–02.3 first. For simulations, construct a **fresh model** for every treatment:
`run!` mutates its argument, so running it again extends that path. Keep budgets small while
debugging. Save an economic prediction before looking at the new plot.

**02.1 — Compare like with like.**
Which rate or share differs most between Austria and Italy? Compare agent counts separately.
Explain one mechanism linking your chosen parameter to demand or income, then state why the
country comparison alone cannot identify its effect.

*Hint:* form `comparison.Italy .- comparison.Austria`, but do not rank counts and fractions
together. A consumption-share vector contains more structural information than its mean.

**02.2 — Covariance versus shock amplitude.**
In a fresh Austria model, apply `model.prop.C .*= 0.5` and compare its indexed GDP path with
the baseline and `C=0` cases. Predict the change first. Which two exogenous innovations remain?

*Hint:* multiplying a covariance matrix by `f` multiplies standard deviations by `sqrt(f)`.
To halve the correlated innovations' standard deviations, use `f=0.25`, not `0.5`.

**02.3 — A small sensitivity experiment.**
Start with `f` in `(0.0, 0.25, 1.0)`, a fresh model and the same seed for each run.
Compute maximum absolute GDP deviation from each path's own initial value and plot it against
`f`. Extend to `(0.0, 0.1, 0.25, 0.5, 0.75, 1.0)` if useful. Is the relationship linear?

*Hint:* maximum deviation along one path is not a volatility estimator. Drift and nonlinear
feedback can dominate it. Repeat a small set of seeds before claiming a monotonic relationship.

**02.4 — More paths, the same economic uncertainty.**
Change the applied budget from 10 to 20 paths, keeping horizon and seed fixed. Compare the mean
and 10–90% band. Try 200 paths only as an optional, more expensive precision check.

*Hint:* more paths reduce Monte Carlo error in estimated means and quantiles; they do not remove
model-generated risk. A small change in band width can have either sign.

**02.5 — Relative forecast dispersion.**
Compute the GDP coefficient of variation at horizons 1, 4 and 8 that fit within `T_fc`.
Does it increase monotonically?

*Hint:* for horizon `h`, use the row `nb2_gdp_index_mat[h+1, :]`. Compute `std(row) / mean(row)`,
or multiply by 100 to report percent. Take the standard deviation across paths, not across time.

**02.6 — An endpoint rather than a whole trajectory.**
Apply 20 paths and `T_fc=20`, then compare the mean and standard deviation of GDP at horizon 20.
Reuse the existing ensemble rather than running every model for another 20 quarters.

*Hint:* raw levels are in `nb2_gdp_mat[21, :]`; indexed values are in `nb2_gdp_index_mat[21, :]`.
State which units you report. Compare spread relative to the mean.

**02.7 — Longer-horizon diagnostic (stretch).**
Compare fresh Austria and Italy models with `C=0` over 20 quarters, then extend a small set of
seeds to 80 quarters. Which country departs more from its starting GDP, and does that ordering
persist? Outline what else would need to change to construct the lecture's no-growth diagnostic.

*Hint:* index each path to its own initial value, report the metric and horizon, and do not treat
a single path as a stability proof. Removing all exogenous drifts and innovations is a stronger
change than `C=0`; flat histories also require an explicit expectations rule rather than an
unidentified AR(1) fit. Future realised exogenous paths would instead change the information
set of a conditional forecast.
"""

# ╔═╡ Cell order:
# ╠═b25815ec-aeb8-11f1-9f19-c1af47b3dc37
# ╟─b293063e-aeb8-11f1-9e88-8b4fe9232048
# ╠═b293067c-aeb8-11f1-ad5a-6b89548f4a6b
# ╟─b2930690-aeb8-11f1-b26d-7d15154cf812
# ╠═b29306b8-aeb8-11f1-b039-b9a728d6c227
# ╟─b29306cc-aeb8-11f1-b9dd-1760a9f7c6e4
# ╟─b29306e0-aeb8-11f1-b7a4-3dd934fc3956
# ╠═b29306f4-aeb8-11f1-b90e-27a20a09c353
# ╟─b2930714-aeb8-11f1-abe4-5d52a2a3d662
# ╠═b293071c-aeb8-11f1-acbf-7f82e962da0c
# ╠═b293074e-aeb8-11f1-b819-abbb938d2334
# ╠═0a77cff2-b9b5-4b86-b669-9bdb8a262131
# ╠═b2930762-aeb8-11f1-a537-7fa2dec3ab68
# ╟─b2930778-aeb8-11f1-87c2-fdbcbfda5da2
# ╟─b293078a-aeb8-11f1-84ec-4bfed0885b59
# ╠═b29307a6-aeb8-11f1-b3c2-a98e06704a0e
# ╠═b29307bc-aeb8-11f1-96ec-19bde3d822a6
# ╠═b293080c-aeb8-11f1-9991-eb2293054cd3
# ╟─b2930820-aeb8-11f1-8e85-51d538e6971f
# ╟─b293083e-aeb8-11f1-8891-598f6f05cbd2
# ╟─b2afa2fa-aeb8-11f1-b9b3-f75d094ff641
# ╟─b2afa318-aeb8-11f1-9a41-b1574df0a926
# ╠═b2afa322-aeb8-11f1-86b7-7996bf33c307
# ╠═b2afa322-aeb8-11f1-9614-65079b45f80c
# ╠═b2afa32c-aeb8-11f1-8898-c1cd175b3425
# ╠═b2afa336-aeb8-11f1-a55b-e75364320332
# ╠═80f08e04-b55e-47b7-8c86-fd45195df8bd
# ╠═b2afa340-aeb8-11f1-8dd6-d3320810d4d9
# ╟─b2afa340-aeb8-11f1-bb47-d38b51bec0f3
# ╟─b2afa34c-aeb8-11f1-af46-291c0386f1cf
# ╠═b2afa354-aeb8-11f1-a065-3f7be16f752a
# ╟─b2afa372-aeb8-11f1-8640-1fe8cf76ca5c
# ╟─b2afa390-aeb8-11f1-9b7c-6dcb8a3b7349
# ╠═b2afa39a-aeb8-11f1-b8bc-e9c07f6758d2
# ╠═83758030-7ed7-40a5-9910-45c92caf1408
# ╠═b2afa3a4-aeb8-11f1-890c-c75acb76f4a5
# ╟─b2afa3b0-aeb8-11f1-b0c2-4b6ae274fab9
# ╠═b2afa3c2-aeb8-11f1-9ab0-bd059ee19dd4
# ╟─b2afa3d6-aeb8-11f1-8991-db6bbeb7d2cf
# ╟─b2afa3de-aeb8-11f1-a74f-c52b1df4ff4a
