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

> **Question this notebook answers:** where do the 50+ parameters come from, and why doesn't the model need a burn-in period?

### Lecture 2 slides covered
- *Data-based initialisation & no burn-in*
- *Data Sources*
- *How big is the model?*
- *Calibration Process*
- *The full parameter set: (almost) no free parameters*

### Learning goals
1. Map every parameter to its data source (census, I-O, tax statutes, Basel III, estimated).
2. Read initial balance sheets directly from the model.
3. Empirically verify the **no-burn-in** claim by running with shocks zeroed out.
4. Swap the calibration country and compare macroeconomic structure.
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
## 1 — The full parameter table

Lecture 2 shows a table of ~50 parameters categorised by data source. Let's reproduce it from the model's `parameters` dict and `model.prop`.

The five categories match the Lecture 2 slide exactly:
- **Census / business demography** — agent counts, firm size distribution
- **Input-output tables** — technology coefficients, labour productivities, consumption shares
- **Government statistics / sector accounts** — tax rates, MPC, dividend payout
- **Basel III / statutory** — capital ratio, LTV, unemployment benefit, inflation target
- **Estimated (AR(1) + Taylor rule)** — the only "free" block
"""

# ╔═╡ b29306b8-aeb8-11f1-b039-b9a728d6c227
begin
    _nb03_m_p = Bit.Model(nb2_p_AT, nb2_ic_AT)
    p = _nb03_m_p.prop

    param_table = DataFrame(
        "Source"    => [
            "Census", "Census", "Census", "Census",
            "I-O tables", "I-O tables", "I-O tables",
            "Gov. statistics", "Gov. statistics", "Gov. statistics",
            "Gov. statistics", "Gov. statistics", "Gov. statistics",
            "Basel III / statute", "Basel III / statute",
            "Basel III / statute", "Basel III / statute",
            "Estimated (AR(1))", "Estimated (Taylor)", "Estimated (Taylor)",
        ],
        "Symbol"    => [
            "H_act", "H_inact", "I (firms)", "J (gov. entities)",
            "a_sg (matrix)", "ᾱ_i (mean)", "b_HH_g (mean)",
            "τ^INC", "τ^VAT", "τ^FIRM", "τ^SIF", "ψ (MPC)", "θ^DIV",
            "ζ (cap. ratio)", "ζ_LTV",
            "θ_UB (unempl. benefit)", "π* (target)",
            "ρ (smoothing)", "ξ^π (infl. weight)", "ξ^γ (growth weight)",
        ],
        "Value" => [
            p.H_act, p.H_inact, p.I, p.J,
            "$(size(p.a_sg))", round(mean(_nb03_m_p.firms.alpha_bar_i), digits=4),
            round(mean(p.b_HH_g), digits=4),
            round(p.tau_INC, digits=4), round(p.tau_VAT, digits=4),
            round(p.tau_FIRM, digits=4), round(p.tau_SIF, digits=4),
            round(p.psi, digits=4), round(p.theta_DIV, digits=4),
            round(p.zeta, digits=4), round(p.zeta_LTV, digits=4),
            round(p.theta_UB, digits=4), "0.0050",
            "see Taylor rule", "see Taylor rule", "see Taylor rule",
        ],
    )
    param_table
end

# ╔═╡ b29306cc-aeb8-11f1-b9dd-1760a9f7c6e4
md"""
**Key insight:** almost everything is read directly from data. Only the last 3 rows (AR(1) expectations + Taylor rule coefficients) are estimated from time-series data. Compare this to a DSGE model where most parameters are estimated — the BeforeIT calibration strategy is fundamentally different.
"""

# ╔═╡ b29306e0-aeb8-11f1-b7a4-3dd934fc3956
md"""
---
## 2 — Initial balance sheets

At $t=0$, every balance sheet is loaded directly from Eurostat national accounts. Let's inspect the initial deposit accounts and debt levels.
"""

# ╔═╡ b29306f4-aeb8-11f1-b90e-27a20a09c353
begin
    model_AT = Bit.Model(nb2_p_AT, nb2_ic_AT)

    # Aggregate initial conditions
    bs_table = DataFrame(
        "Sector"         => ["Households (deposits)", "Firms (deposits, sum)",
                             "Firms (debt, sum)", "Bank equity",
                             "Government debt", "Policy rate (initial)"],
        "Value (€ real)" => [
            round(sum(model_AT.w_act.D_h), sigdigits=5),
            round(sum(model_AT.firms.D_i), sigdigits=5),
            round(sum(model_AT.firms.L_i), sigdigits=5),
            round(model_AT.bank.E_k, sigdigits=5),
            round(model_AT.gov.L_G, sigdigits=5),
            round(model_AT.cb.r_bar, digits=4),
        ],
    )
    bs_table
end

# ╔═╡ b2930714-aeb8-11f1-abe4-5d52a2a3d662
md"""
---
## 3 — The no-burn-in demonstration

Lecture 2 claims: *"If we suppress the growth processes, the model fluctuates around its initial conditions."* This is what makes the model so unusual — most ABMs need hundreds of periods to converge before they can be used for forecasting.

**Let's test this claim with three scenarios over 20 quarters (5 years):**
1. **Shocks ON** — normal Austria 2010:Q1 run.
2. **Shocks OFF (`C=0`)** — zero the shock covariance matrix `model.prop.C`. This suppresses **three of the five** stochastic innovations (euro-area GDP, export demand, import supply); deterministic drift terms β remain, and so do the government-consumption and euro-area-inflation shocks, which have their own scalar σ rather than coming from `C`.
3. **Full steady state** — use `Bit.STEADY_STATE2010Q1`, a built-in calibration where all AR(1) drift and noise are zero, the policy rate is fixed, and agent histories are pre-loaded with flat time series so the OLS expectations do not re-introduce drift.

If the claim holds, scenarios 2 and 3 should stay much closer to the t=0 value than the full-shock run, with scenario 3 showing the least drift of all.
"""

# ╔═╡ b293071c-aeb8-11f1-acbf-7f82e962da0c
@bind run_noburn PlutoUI.Button("▶ Run no-burn-in demo (3 scenarios × 20 quarters, ~60 sec)")

# ╔═╡ b293074e-aeb8-11f1-b819-abbb938d2334
begin
    run_noburn
    Random.seed!(42)

    # --- Baseline: shocks ON ---
    model_shocks_on = Bit.Model(nb2_p_AT, nb2_ic_AT)
    Bit.run!(model_shocks_on, 20)

    # --- No-burn-in: shocks OFF (zero covariance matrix only) ---
    # model.prop.C is the 3×3 covariance matrix of the three CORRELATED innovations
    # (eps_Y_EA, eps_E, eps_I). The other two exogenous processes — government
    # consumption and euro-area inflation — draw from their own scalar sigmas
    # (gov.sigma_G, rotw.sigma_pi_EA) and are NOT silenced by zeroing C.
    # That is precisely why scenario 3 below is quieter than scenario 2.
    # Setting it to zero suppresses all stochastic noise; deterministic AR(1) drift remains.
    Random.seed!(42)
    model_no_shocks = Bit.Model(nb2_p_AT, nb2_ic_AT)
    model_no_shocks.prop.C .= 0.0
    Bit.run!(model_no_shocks, 20)

    # --- Full steady state ---
    # Bit.STEADY_STATE2010Q1 is a special calibration where all AR(1) drift and noise
    # are zero, the policy rate is fixed at zero, and agent histories are pre-loaded
    # with flat time series so OLS expectations stay inert every quarter.
    Random.seed!(42)
    nb2_ss_p, nb2_ss_ic = Bit.STEADY_STATE2010Q1.parameters, Bit.STEADY_STATE2010Q1.initial_conditions
    model_steady = Bit.Model(nb2_ss_p, nb2_ss_ic)
    Bit.run!(model_steady, 20)

    "Simulations complete ✓"
end

# ╔═╡ b2930762-aeb8-11f1-a537-7fa2dec3ab68
begin
    run_noburn

    gdp_on     = model_shocks_on.data.real_gdp
    gdp_off    = model_no_shocks.data.real_gdp
    gdp_steady = model_steady.data.real_gdp
    gdp_0      = gdp_on[1]

    p3 = plot(
        1:21, gdp_on,
        label = "Shocks ON", lw = 2, color = :steelblue,
        title = "Real GDP: three scenarios (20 quarters)",
        xlabel = "Quarter", ylabel = "Real GDP",
    )
    plot!(p3, 1:21, gdp_off,
          label = "Shocks OFF (C=0)", lw = 2, color = :crimson, ls = :dash)
    plot!(p3, 1:21, gdp_steady,
          label = "Full steady state", lw = 2, color = :forestgreen, ls = :solid)
    hline!(p3, [gdp_0], label = "t=0 value", color = :grey, ls = :dot, lw = 1.5)

    p4 = plot(
        1:21, (gdp_off .- gdp_0) ./ gdp_0 .* 100,
        label = "C=0", color = :crimson, lw = 2, ls = :dash,
        title = "GDP deviation from t=0 value (%)",
        xlabel = "Quarter", ylabel = "% deviation",
    )
    plot!(p4, 1:21, (gdp_steady .- gdp_0) ./ gdp_0 .* 100,
          label = "Full steady state", color = :forestgreen, lw = 2)
    hline!(p4, [0], color = :black, lw = 1, label = "")

    plot(p3, p4, layout = (2, 1), size = (750, 580))
end

# ╔═╡ b2930778-aeb8-11f1-87c2-fdbcbfda5da2
begin
    run_noburn
    dev_on     = maximum(abs.((model_shocks_on.data.real_gdp .- gdp_0) ./ gdp_0)) * 100
    dev_off    = maximum(abs.((model_no_shocks.data.real_gdp .- gdp_0) ./ gdp_0)) * 100
    dev_steady = maximum(abs.((model_steady.data.real_gdp    .- gdp_0) ./ gdp_0)) * 100
    md"""
    | Scenario | Max GDP deviation from t=0 (20 quarters) |
    |---|---|
    | Shocks ON | **$(round(dev_on, digits=2))%** |
    | Shocks OFF (`C=0`) | **$(round(dev_off, digits=2))%** |
    | Full steady state | **$(round(dev_steady, digits=2))%** |

    With exogenous shocks suppressed (`C=0`), GDP stays within roughly **$(round(dev_off, digits=1))%**
    of its initial value — the AR(1) drift terms still push the economy slightly but there is no
    stochastic amplification. With the full steady-state calibration, the model sits even closer
    to the fixed point (**$(round(dev_steady, digits=2))%** max deviation).

    Compare this to a typical macro ABM starting from an arbitrary initial state, where
    it can take 200+ quarters of discarded burn-in to reach statistical equilibrium.
    BeforeIT starts *at* the data: the initial conditions are the fixed point.
    """
end

# ╔═╡ b293078a-aeb8-11f1-84ec-4bfed0885b59
md"""
---
## 4 — Austria vs Italy

BeforeIT ships a second calibration for Italy. Let's compare the two economies side-by-side on key structural parameters.
"""

# ╔═╡ b29307a6-aeb8-11f1-b3c2-a98e06704a0e
begin
    pAT = Bit.Model(nb2_p_AT, nb2_ic_AT).prop
    pIT = Bit.Model(nb2_p_IT, nb2_ic_IT).prop

    comparison = DataFrame(
        "Parameter"   => ["MPC ψ", "τ^INC", "τ^VAT", "τ^FIRM",
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
@bind run_countries PlutoUI.Button("▶ Run Austria vs Italy (20 quarters each)")

# ╔═╡ b293080c-aeb8-11f1-9991-eb2293054cd3
begin
    run_countries
    Random.seed!(42)

    _m_AT = Bit.Model(nb2_p_AT, nb2_ic_AT)
    _m_IT = Bit.Model(nb2_p_IT, nb2_ic_IT)

    Bit.run!(_m_AT, 20)
    Bit.run!(_m_IT, 20)

    # Normalise GDP to 100 at t=0 for comparison
    gdp_AT_norm = _m_AT.data.real_gdp ./ _m_AT.data.real_gdp[1] .* 100
    gdp_IT_norm = _m_IT.data.real_gdp ./ _m_IT.data.real_gdp[1] .* 100
    inf_AT = _m_AT.data.nominal_gdp ./ _m_AT.data.real_gdp
    inf_IT = _m_IT.data.nominal_gdp ./ _m_IT.data.real_gdp

    p1 = plot(
        gdp_AT_norm, label = "Austria", lw = 2, color = :steelblue,
        title = "Real GDP (indexed to 100)",
        xlabel = "Quarter", ylabel = "Index (t=0 = 100)"
    )
    plot!(p1, gdp_IT_norm, label = "Italy", lw = 2, color = :tomato)

    p2 = plot(
        inf_AT, label = "Austria", lw = 2, color = :steelblue,
        title = "GDP deflator",
        xlabel = "Quarter", ylabel = "Deflator"
    )
    plot!(p2, inf_IT, label = "Italy", lw = 2, color = :tomato)

    plot(p1, p2, layout = (1, 2), size = (800, 350), legend = :topright)
end

# ╔═╡ b2930820-aeb8-11f1-8e85-51d538e6971f
md"""
Structural differences in MPC, tax rates, and unemployment benefit replacement rates show up in the GDP path and inflation dynamics within just a few quarters.
"""

# ╔═╡ b293083e-aeb8-11f1-8891-598f6f05cbd2
md"""
---
# Part 2 — Forecasting

The model starts at its calibrated state and stays there without a spin-up. That is what
makes it usable for prediction from quarter zero, so the natural next question is how good
those predictions actually are.
"""

# ╔═╡ b2afa2fa-aeb8-11f1-b9b3-f75d094ff641
md"""


> **Question this notebook answers:** how well does the BeforeIT ABM forecast compared to standard statistical models?

### Lecture 2 slides covered
- *Out-of-sample forecast performance in comparison to DSGE model*
- *Out-of-sample forecast performance* (fan chart figure)
- *Quarterly out-of-sample GDP forecast decomposition*
- *Poledna et al. (2019) summary*

### Learning goals
1. Build a multi-path Monte Carlo forecast with confidence bands.
2. Implement a simple AR(1) benchmark in Julia for comparison.
3. Compare AR(1) point forecasts against the ABM ensemble distribution at selected horizons.
4. Understand the improvement from **conditional forecasting** (fixing realised exogenous paths).
"""

# ╔═╡ b2afa318-aeb8-11f1-9a41-b1574df0a926
md"""
---
## 5 — Monte Carlo fan chart

A **fan chart** shows the distribution of model forecasts across Monte Carlo paths. The Poledna et al. (2019) paper runs 500 paths per reference quarter — we use a smaller number here for speed.

The Austria model is initialised at **2010:Q1** — we are asking: starting from the actual Austrian economy in Q1 2010, what does the ABM predict for the next T quarters?
"""

# ╔═╡ b2afa322-aeb8-11f1-86b7-7996bf33c307
@bind n_mc_fc PlutoUI.Slider([20, 50, 100, 200], default=50, show_value=true)

# ╔═╡ b2afa322-aeb8-11f1-9614-65079b45f80c
@bind T_fc PlutoUI.Slider(4:4:40, default=20, show_value=true)

# ╔═╡ b2afa32c-aeb8-11f1-8898-c1cd175b3425
@bind run_fc PlutoUI.Button("▶ Run MC forecast (may take 1–5 min)")

# ╔═╡ b2afa336-aeb8-11f1-a55b-e75364320332
begin
    run_fc
    Random.seed!(2019)

    _mc_models = Bit.ensemblerun!(
        (Bit.Model(nb2_p_AT, nb2_ic_AT) for _ in 1:n_mc_fc),
        T_fc,
    )
    "MC forecast complete: $(n_mc_fc) paths × $(T_fc) quarters ✓"
end

# ╔═╡ b2afa340-aeb8-11f1-8dd6-d3320810d4d9
begin
    run_fc

    # Stack GDP series: (T+1) × n_mc
    nb2_gdp_mat = hcat([m.data.real_gdp for m in _mc_models]...)

    nb2_gdp_mean = mean(nb2_gdp_mat, dims=2)[:]
    nb2_gdp_p10  = [quantile(nb2_gdp_mat[t,:], 0.10) for t in 1:T_fc+1]
    nb2_gdp_p25  = [quantile(nb2_gdp_mat[t,:], 0.25) for t in 1:T_fc+1]
    nb2_gdp_p75  = [quantile(nb2_gdp_mat[t,:], 0.75) for t in 1:T_fc+1]
    nb2_gdp_p90  = [quantile(nb2_gdp_mat[t,:], 0.90) for t in 1:T_fc+1]

    p_fan = plot(
        0:T_fc, nb2_gdp_mean,
        ribbon = (nb2_gdp_mean .- nb2_gdp_p10, nb2_gdp_p90 .- nb2_gdp_mean),
        fillalpha = 0.15, color = :steelblue,
        label = "Mean + 10–90%", lw = 2,
        title  = "ABM forecast: Real GDP\n($(n_mc_fc) paths, Austria 2010:Q1)",
        xlabel = "Quarters ahead", ylabel = "Real GDP (index)",
    )
    plot!(p_fan, 0:T_fc, nb2_gdp_p25, fillrange = nb2_gdp_p75, fillalpha = 0.2,
          color = :steelblue, lw = 0, label = "25–75%")
    plot!(p_fan, 0:T_fc, nb2_gdp_mean, lw = 2, color = :steelblue, label = "")
end

# ╔═╡ b2afa340-aeb8-11f1-bb47-d38b51bec0f3
md"""
The fan widens as the forecast horizon extends — this is correct statistical behaviour. The inner 25–75% band (darker) and outer 10–90% band (lighter) together show the forecast distribution.
"""

# ╔═╡ b2afa34c-aeb8-11f1-af46-291c0386f1cf
md"""
---
## 6 — Historical trajectory and forecast overlay

The model is initialised from the *actual* Austrian economy at 2010:Q1. Let's plot the **historical GDP series** from the calibration data alongside the MC forecast, to show where the forecast starts relative to the recent past.

The historical data ($Y$ from the initial conditions) was used to estimate the AR(1) expectation rules during calibration. The vertical dashed line marks the initialisation date.
"""

# ╔═╡ b2afa354-aeb8-11f1-a065-3f7be16f752a
begin
    run_fc

    Y_hist_raw = vec(nb2_ic_AT["Y"])   # GDP series up to 2010:Q1
    T_hist     = length(Y_hist_raw)

    # Normalise to 100 at the last historical point (t=0 for the forecast)
    y0 = Y_hist_raw[end]
    Y_hist_norm  = Y_hist_raw        ./ y0 .* 100
    fc_norm_mean = nb2_gdp_mean     ./ nb2_gdp_mean[1] .* 100
    fc_norm_p10  = nb2_gdp_p10      ./ nb2_gdp_mean[1] .* 100
    fc_norm_p90  = nb2_gdp_p90      ./ nb2_gdp_mean[1] .* 100

    # x-axis: negative quarters for history, 0…T_fc for forecast
    x_hist = (-(T_hist-1)):0
    x_fc   = 0:T_fc

    p_hist = plot(
        x_hist, Y_hist_norm,
        lw=2, color=:black, label="Historical GDP (calibration data)",
        title  = "Historical trajectory + ABM forecast\n(normalised, 2010:Q1 = 100)",
        xlabel = "Quarters relative to 2010:Q1", ylabel = "Index (2010:Q1 = 100)",
    )
    plot!(p_hist, x_fc, fc_norm_mean,
          ribbon = (fc_norm_mean .- fc_norm_p10, fc_norm_p90 .- fc_norm_mean),
          fillalpha=0.15, color=:steelblue, lw=2,
          label="ABM forecast (mean ± 10–90%)")
    vline!(p_hist, [0], lw=1.5, ls=:dash, color=:grey, label="Init. date (2010:Q1)")
end

# ╔═╡ b2afa372-aeb8-11f1-8640-1fe8cf76ca5c
md"""
**Reading the plot:**
- The black line shows the Austrian GDP trajectory *used to calibrate* the model — it ends exactly at the initialisation point (index = 100).
- The blue ribbon shows where the ABM *predicts* GDP will go from 2010:Q1 onward, given the stochastic shocks.
- The fan width reflects **forecast uncertainty** from the AR(1) shock processes, not parameter uncertainty.

In Poledna et al. (2019), this plot is constructed for *39 reference quarters* (2010:Q2–2019:Q4) to compute out-of-sample RMSE. Here we show only the 2010:Q1 reference quarter.
"""

# ╔═╡ b2afa390-aeb8-11f1-9b7c-6dcb8a3b7349
md"""
---
## 7 — A simple AR(1) benchmark

Lecture 2 Table 4 benchmarks the ABM against an AR(1) model. Let's implement a simple AR(1) in Julia to replicate the comparison setup.

An AR(1) for GDP: $y_t = \alpha y_{t-1} + \beta + \varepsilon_t$, estimated by OLS on the initialisation window. We use the initial GDP series from the calibration data.
"""

# ╔═╡ b2afa39a-aeb8-11f1-b8bc-e9c07f6758d2
begin
    # Use the historical GDP series from the calibration initial conditions
    # (the pre-sample data used to estimate AR(1) coefficients)
    Y_hist = vec(nb2_ic_AT["Y"])  # quarterly GDP series up to 2010:Q1

    # OLS AR(1): regress y_t on y_{t-1}
    y_lag = Y_hist[1:end-1]
    y_now = Y_hist[2:end]

    # OLS in matrix form: [1 y_lag] * [β; α] = y_now
    X = hcat(ones(length(y_lag)), y_lag)
    coef = X \ y_now   # [β, α]
    β_ar1, α_ar1 = coef

    # Forecast T_fc quarters ahead (point forecast, no noise)
    ar1_forecast = zeros(T_fc + 1)
    ar1_forecast[1] = Y_hist[end]   # start from last observed value
    for t in 2:T_fc+1
        ar1_forecast[t] = β_ar1 + α_ar1 * ar1_forecast[t-1]
    end

    (α = round(α_ar1, digits=4), β = round(β_ar1, digits=4))
end

# ╔═╡ b2afa3a4-aeb8-11f1-890c-c75acb76f4a5
begin
    run_fc

    # Normalise both to 100 at t=0
    ar1_norm = ar1_forecast      ./ ar1_forecast[1] .* 100
    gdp_norm = nb2_gdp_mean     ./ nb2_gdp_mean[1] .* 100
    p10_norm = nb2_gdp_p10      ./ nb2_gdp_mean[1] .* 100
    p90_norm = nb2_gdp_p90      ./ nb2_gdp_mean[1] .* 100

    plot(
        0:T_fc, gdp_norm,
        ribbon = (gdp_norm .- p10_norm, p90_norm .- gdp_norm),
        fillalpha = 0.15, color = :steelblue, lw = 2,
        label = "ABM (mean ± 10–90%)",
        title  = "ABM vs AR(1) forecast\n(normalised, 2010:Q1 = 100)",
        xlabel = "Quarters ahead", ylabel = "Index (t=0 = 100)",
    )
    plot!(0:T_fc, ar1_norm, label = "AR(1) point forecast",
          lw = 2, color = :tomato, ls = :dash)
end

# ╔═╡ b2afa3b0-aeb8-11f1-b0c2-4b6ae274fab9
md"""
---
## 8 — Forecast divergence at selected horizons

Let's compare the AR(1) point forecast against the ABM distribution at several horizons.

The table below shows, at each horizon $h$:
- **`|AR(1) − ABM mean|`**: how far the AR(1) point forecast sits from the ABM ensemble mean.
- **`ABM std across paths`**: the spread (1 std) of the ABM MC distribution at that horizon.
- **`AR(1) within ABM spread (%)`**: $(σ_{ABM} - |AR(1) - \bar{x}_{ABM}|)/σ_{ABM} \times 100$; positive means the AR(1) falls inside the ABM spread; negative means it diverges further.

Note: this is **not** a proper forecast evaluation — neither series is compared against realised data. See the note below for how Poledna et al. compute the actual out-of-sample RMSE.
"""

# ╔═╡ b2afa3c2-aeb8-11f1-9ab0-bd059ee19dd4
begin
    run_fc

    # Compute RMSE of ABM mean vs AR(1) at different horizons
    horizons = [1, 2, 4, 8]

    rmse_ar1 = Float64[]
    rmse_abm = Float64[]

    for h in horizons
        # AR(1) forecast error vs ABM mean (using ABM as pseudo-truth here)
        ar1_val = ar1_forecast[h+1]
        abm_val = nb2_gdp_mean[h+1]

        # RMSE of individual MC paths vs their mean (spread metric)
        paths_at_h = nb2_gdp_mat[h+1, :]
        push!(rmse_ar1, abs(ar1_val - abm_val))
        push!(rmse_abm, std(paths_at_h))
    end

    rmse_table = DataFrame(
        "Horizon (quarters)" => horizons,
        "|AR(1) − ABM mean|" => round.(rmse_ar1, sigdigits=4),
        "ABM std across paths" => round.(rmse_abm, sigdigits=4),
        "AR(1) within ABM spread (%)" => round.((rmse_abm .- rmse_ar1) ./ rmse_abm .* 100, digits=1),
    )
    rmse_table
end

# ╔═╡ b2afa3d6-aeb8-11f1-8991-db6bbeb7d2cf
md"""
> **Note:** A proper validation (as in Poledna et al. Table 4) requires out-of-sample held-out data: run the model 39 different reference quarters (2010:Q2–2019:Q4) and compare forecasted vs realised values. The calculation above is illustrative; it uses the ABM's own mean as the "truth". For replication of the paper's exact Table 4 numbers, see the scripts in `../tabs/error_table_*.jl` in the lecture repository.
"""

# ╔═╡ b2afa3de-aeb8-11f1-a74f-c52b1df4ff4a
md"""
---
## ✔ What you learned

Calibration:

- About 50 parameters are read from data; only the AR(1) and Taylor-rule block is estimated.
- Initial balance sheets come from Eurostat national accounts, so the stock-flow structure is exact at t = 0.
- `model.prop.C .= 0` zeros three of the five AR(1) processes — the correlated ones. Government consumption and euro-area inflation keep drawing from their own sigmas, which is why the full steady state is quieter still. Together they show the **quasi-fixed-point** property that removes burn-in.
- Austria and Italy have measurably different structures, visible after 20 quarters.

Forecasting:

- `Bit.ensemblerun!` generates the ensemble; stack `m.data.real_gdp` into a matrix for quantile analysis.
- An AR(1) benchmark is a two-liner: `X = hcat(ones(n), y_lag); coef = X \\ y_now`.
- The fan widens with the horizon — uncertainty accumulates through the stochastic shocks.

---
## Exercises

**Exercise 02.1** — Which parameter differs most between Austria and Italy in the comparison table? What economic mechanism would that affect most strongly?

**Exercise 02.2** — Partially remove shocks by scaling the covariance matrix: `model.prop.C .*= 0.5`. How does GDP volatility compare to the full-shock and no-shock cases?

**Exercise 02.3** — Scale the covariance matrix in steps, `model.prop.C .*= f` for f in {0.0, 0.1, 0.25, 0.5, 0.75, 1.0}, and plot maximum GDP deviation against f. Is the relationship approximately linear?

**Exercise 02.4** — Increase `n_mc_fc` to 200. Does the mean forecast change? Does the 10–90% band narrow much?

**Exercise 02.5** — Compute the **coefficient of variation** (std / mean) of GDP at horizons 1, 4 and 8 quarters. How fast does forecast uncertainty grow?

**Exercise 02.6** — Compute the standard deviation of real GDP at `T = 20` across 20 Monte Carlo paths. How does it compare to the mean?

**Exercise 02.7** *(stretch)* — Run the full steady-state scenario for 80 quarters rather than 20. Does the deviation stay small? Then run the same `C = 0` treatment on `Bit.ITALY2010Q1`: is Italy's deviation larger or smaller than Austria's at 20 quarters?
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
# ╠═b2afa340-aeb8-11f1-8dd6-d3320810d4d9
# ╟─b2afa340-aeb8-11f1-bb47-d38b51bec0f3
# ╟─b2afa34c-aeb8-11f1-af46-291c0386f1cf
# ╠═b2afa354-aeb8-11f1-a065-3f7be16f752a
# ╟─b2afa372-aeb8-11f1-8640-1fe8cf76ca5c
# ╟─b2afa390-aeb8-11f1-9b7c-6dcb8a3b7349
# ╠═b2afa39a-aeb8-11f1-b8bc-e9c07f6758d2
# ╠═b2afa3a4-aeb8-11f1-890c-c75acb76f4a5
# ╟─b2afa3b0-aeb8-11f1-b0c2-4b6ae274fab9
# ╠═b2afa3c2-aeb8-11f1-9ab0-bd059ee19dd4
# ╟─b2afa3d6-aeb8-11f1-8991-db6bbeb7d2cf
# ╟─b2afa3de-aeb8-11f1-a74f-c52b1df4ff4a
