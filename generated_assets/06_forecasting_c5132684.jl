### A Pluto.jl notebook ###
# v0.20.24

#> [frontmatter]
#> title = "Forecasting and validation"
#> order = 7
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

# ╔═╡ 06000000-0000-0000-0000-000000000001
begin
    import Pkg
    Pkg.activate(joinpath(@__DIR__, "..", "..", "pluto_tutorial"); io=devnull)
    import BeforeIT as Bit
    import Random
    using Plots, PlutoUI, Statistics, StatsBase, DataFrames
end

# ╔═╡ 06000000-0000-0000-0000-000000000002
md"""
# Notebook 06 — Forecasting and Validation

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

# ╔═╡ 06000000-0000-0000-0000-000000000003
begin
    nb06_p  = Bit.AUSTRIA2010Q1.parameters
    nb06_ic = Bit.AUSTRIA2010Q1.initial_conditions
    "Calibration loaded ✓"
end

# ╔═╡ 06000000-0000-0000-0000-000000000004
md"""
---
## 1 — Monte Carlo fan chart

A **fan chart** shows the distribution of model forecasts across Monte Carlo paths. The Poledna et al. (2019) paper runs 500 paths per reference quarter — we use a smaller number here for speed.

The Austria model is initialised at **2010:Q1** — we are asking: starting from the actual Austrian economy in Q1 2010, what does the ABM predict for the next T quarters?
"""

# ╔═╡ 06000000-0000-0000-0000-000000000005
@bind n_mc_fc PlutoUI.Slider([20, 50, 100, 200], default=50, show_value=true)

# ╔═╡ 06000000-0000-0000-0000-000000000006
@bind T_fc PlutoUI.Slider(4:4:40, default=20, show_value=true)

# ╔═╡ 06000000-0000-0000-0000-000000000007
@bind run_fc PlutoUI.Button("▶ Run MC forecast (may take 1–5 min)")

# ╔═╡ 06000000-0000-0000-0000-000000000008
begin
    run_fc
    Random.seed!(2019)

    _mc_models = Bit.ensemblerun!(
        (Bit.Model(nb06_p, nb06_ic) for _ in 1:n_mc_fc),
        T_fc,
    )
    "MC forecast complete: $(n_mc_fc) paths × $(T_fc) quarters ✓"
end

# ╔═╡ 06000000-0000-0000-0000-000000000009
begin
    run_fc

    # Stack GDP series: (T+1) × n_mc
    nb06_gdp_mat = hcat([m.data.real_gdp for m in _mc_models]...)

    nb06_gdp_mean = mean(nb06_gdp_mat, dims=2)[:]
    nb06_gdp_p10  = [quantile(nb06_gdp_mat[t,:], 0.10) for t in 1:T_fc+1]
    nb06_gdp_p25  = [quantile(nb06_gdp_mat[t,:], 0.25) for t in 1:T_fc+1]
    nb06_gdp_p75  = [quantile(nb06_gdp_mat[t,:], 0.75) for t in 1:T_fc+1]
    nb06_gdp_p90  = [quantile(nb06_gdp_mat[t,:], 0.90) for t in 1:T_fc+1]

    p = plot(
        0:T_fc, nb06_gdp_mean,
        ribbon = (nb06_gdp_mean .- nb06_gdp_p10, nb06_gdp_p90 .- nb06_gdp_mean),
        fillalpha = 0.15, color = :steelblue,
        label = "Mean + 10–90%", lw = 2,
        title  = "ABM forecast: Real GDP\n($(n_mc_fc) paths, Austria 2010:Q1)",
        xlabel = "Quarters ahead", ylabel = "Real GDP (index)",
    )
    plot!(p, 0:T_fc, nb06_gdp_p25, fillrange = nb06_gdp_p75, fillalpha = 0.2,
          color = :steelblue, lw = 0, label = "25–75%")
    plot!(p, 0:T_fc, nb06_gdp_mean, lw = 2, color = :steelblue, label = "")
end

# ╔═╡ 06000000-0000-0000-0000-00000000000a
md"""
The fan widens as the forecast horizon extends — this is correct statistical behaviour. The inner 25–75% band (darker) and outer 10–90% band (lighter) together show the forecast distribution.
"""

# ╔═╡ 06000000-0000-0000-0000-000000000014
md"""
---
## 1b — Historical trajectory + forecast overlay

The model is initialised from the *actual* Austrian economy at 2010:Q1. Let's plot the **historical GDP series** from the calibration data alongside the MC forecast, to show where the forecast starts relative to the recent past.

The historical data ($Y$ from the initial conditions) was used to estimate the AR(1) expectation rules during calibration. The vertical dashed line marks the initialisation date.
"""

# ╔═╡ 06000000-0000-0000-0000-000000000015
begin
    run_fc

    Y_hist_raw = vec(nb06_ic["Y"])   # GDP series up to 2010:Q1
    T_hist     = length(Y_hist_raw)

    # Normalise to 100 at the last historical point (t=0 for the forecast)
    y0 = Y_hist_raw[end]
    Y_hist_norm  = Y_hist_raw        ./ y0 .* 100
    fc_norm_mean = nb06_gdp_mean     ./ nb06_gdp_mean[1] .* 100
    fc_norm_p10  = nb06_gdp_p10      ./ nb06_gdp_mean[1] .* 100
    fc_norm_p90  = nb06_gdp_p90      ./ nb06_gdp_mean[1] .* 100

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

# ╔═╡ 06000000-0000-0000-0000-000000000016
md"""
**Reading the plot:**
- The black line shows the Austrian GDP trajectory *used to calibrate* the model — it ends exactly at the initialisation point (index = 100).
- The blue ribbon shows where the ABM *predicts* GDP will go from 2010:Q1 onward, given the stochastic shocks.
- The fan width reflects **forecast uncertainty** from the AR(1) shock processes, not parameter uncertainty.

In Poledna et al. (2019), this plot is constructed for *39 reference quarters* (2010:Q2–2019:Q4) to compute out-of-sample RMSE. Here we show only the 2010:Q1 reference quarter.
"""

# ╔═╡ 06000000-0000-0000-0000-00000000000b
md"""
---
## 2 — A simple AR(1) benchmark

Lecture 2 Table 4 benchmarks the ABM against an AR(1) model. Let's implement a simple AR(1) in Julia to replicate the comparison setup.

An AR(1) for GDP: $y_t = \alpha y_{t-1} + \beta + \varepsilon_t$, estimated by OLS on the initialisation window. We use the initial GDP series from the calibration data.
"""

# ╔═╡ 06000000-0000-0000-0000-00000000000c
begin
    # Use the historical GDP series from the calibration initial conditions
    # (the pre-sample data used to estimate AR(1) coefficients)
    Y_hist = vec(nb06_ic["Y"])  # quarterly GDP series up to 2010:Q1

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

# ╔═╡ 06000000-0000-0000-0000-00000000000f
begin
    run_fc

    # Compute RMSE of ABM mean vs AR(1) at different horizons
    horizons = [1, 2, 4, 8]

    rmse_ar1 = Float64[]
    rmse_abm = Float64[]

    for h in horizons
        # AR(1) forecast error vs ABM mean (using ABM as pseudo-truth here)
        ar1_val = ar1_forecast[h+1]
        abm_val = nb06_gdp_mean[h+1]

        # RMSE of individual MC paths vs their mean (spread metric)
        paths_at_h = nb06_gdp_mat[h+1, :]
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

# ╔═╡ 06000000-0000-0000-0000-00000000000d
begin
    run_fc

    # Normalise both to 100 at t=0
    ar1_norm = ar1_forecast      ./ ar1_forecast[1] .* 100
    gdp_norm = nb06_gdp_mean     ./ nb06_gdp_mean[1] .* 100
    p10_norm = nb06_gdp_p10      ./ nb06_gdp_mean[1] .* 100
    p90_norm = nb06_gdp_p90      ./ nb06_gdp_mean[1] .* 100

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

# ╔═╡ 06000000-0000-0000-0000-00000000000e
md"""
---
## 3 — Forecast divergence at selected horizons

Let's compare the AR(1) point forecast against the ABM distribution at several horizons.

The table below shows, at each horizon $h$:
- **`|AR(1) − ABM mean|`**: how far the AR(1) point forecast sits from the ABM ensemble mean.
- **`ABM std across paths`**: the spread (1 std) of the ABM MC distribution at that horizon.
- **`AR(1) within ABM spread (%)`**: $(σ_{ABM} - |AR(1) - \bar{x}_{ABM}|)/σ_{ABM} \times 100$; positive means the AR(1) falls inside the ABM spread; negative means it diverges further.

Note: this is **not** a proper forecast evaluation — neither series is compared against realised data. See the note below for how Poledna et al. compute the actual out-of-sample RMSE.
"""

# ╔═╡ 06000000-0000-0000-0000-000000000010
md"""
> **Note:** A proper validation (as in Poledna et al. Table 4) requires out-of-sample held-out data: run the model 39 different reference quarters (2010:Q2–2019:Q4) and compare forecasted vs realised values. The calculation above is illustrative; it uses the ABM's own mean as the "truth". For replication of the paper's exact Table 4 numbers, see the scripts in `../tabs/error_table_*.jl` in the lecture repository.
"""

# ╔═╡ 06000000-0000-0000-0000-000000000013
md"""
---
## ✔ What you learned

- `Bit.ensemblerun!` generates a full MC ensemble; stack `m.data.real_gdp` into a matrix for quantile analysis.
- An AR(1) benchmark is simple to implement in Julia: `X = hcat(ones(n), y_lag); coef = X \\ y_now`.
- The ABM fan chart widens at longer horizons — uncertainty accumulates correctly through the stochastic shocks.

---
## Exercises

**Exercise 06.1** — Increase `n_mc_fc` to 200. Does the mean forecast change? Does the 10–90% band narrow significantly?

**Exercise 06.2** — Compute the **coefficient of variation** (std / mean) of GDP at horizons 1, 4, 8 quarters. How fast does forecast uncertainty grow with the horizon?

"""

# ╔═╡ Cell order:
# ╟─06000000-0000-0000-0000-000000000002
# ╠═06000000-0000-0000-0000-000000000001
# ╠═06000000-0000-0000-0000-000000000003
# ╟─06000000-0000-0000-0000-000000000004
# ╠═06000000-0000-0000-0000-000000000005
# ╠═06000000-0000-0000-0000-000000000006
# ╠═06000000-0000-0000-0000-000000000007
# ╠═06000000-0000-0000-0000-000000000008
# ╠═06000000-0000-0000-0000-000000000009
# ╟─06000000-0000-0000-0000-00000000000a
# ╟─06000000-0000-0000-0000-000000000014
# ╠═06000000-0000-0000-0000-000000000015
# ╟─06000000-0000-0000-0000-000000000016
# ╟─06000000-0000-0000-0000-00000000000b
# ╠═06000000-0000-0000-0000-00000000000c
# ╠═06000000-0000-0000-0000-00000000000d
# ╟─06000000-0000-0000-0000-00000000000e
# ╠═06000000-0000-0000-0000-00000000000f
# ╟─06000000-0000-0000-0000-000000000010
# ╠═06000000-0000-0000-0000-000000000013
