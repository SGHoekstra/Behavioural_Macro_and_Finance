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

# ╔═╡ 03000000-0000-0000-0000-000000000001
begin
    import Pkg
    Pkg.activate(dirname(@__FILE__))
    import BeforeIT as Bit
    import Random
    using Plots, PlutoUI, DataFrames, Statistics
end

# ╔═╡ 03000000-0000-0000-0000-000000000002
md"""
# Notebook 03 — Calibration and Data

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

# ╔═╡ 03000000-0000-0000-0000-000000000003
begin
    nb03_p_AT  = Bit.AUSTRIA2010Q1.parameters
    nb03_ic_AT = Bit.AUSTRIA2010Q1.initial_conditions
    nb03_p_IT  = Bit.ITALY2010Q1.parameters
    nb03_ic_IT = Bit.ITALY2010Q1.initial_conditions
    "Calibrations loaded: Austria and Italy ✓"
end

# ╔═╡ 03000000-0000-0000-0000-000000000004
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

# ╔═╡ 03000000-0000-0000-0000-000000000005
begin
    _nb03_m_p = Bit.Model(nb03_p_AT, nb03_ic_AT)
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

# ╔═╡ 03000000-0000-0000-0000-000000000006
md"""
**Key insight:** almost everything is read directly from data. Only the last 3 rows (AR(1) expectations + Taylor rule coefficients) are estimated from time-series data. Compare this to a DSGE model where most parameters are estimated — the BeforeIT calibration strategy is fundamentally different.
"""

# ╔═╡ 03000000-0000-0000-0000-000000000007
md"""
---
## 2 — Initial balance sheets

At $t=0$, every balance sheet is loaded directly from Eurostat national accounts. Let's inspect the initial deposit accounts and debt levels.
"""

# ╔═╡ 03000000-0000-0000-0000-000000000008
begin
    model_AT = Bit.Model(nb03_p_AT, nb03_ic_AT)

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

# ╔═╡ 03000000-0000-0000-0000-000000000009
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

# ╔═╡ 03000000-0000-0000-0000-00000000000a
@bind run_noburn PlutoUI.Button("▶ Run no-burn-in demo (3 scenarios × 20 quarters, ~60 sec)")

# ╔═╡ 03000000-0000-0000-0000-00000000000b
begin
    run_noburn
    Random.seed!(42)

    # --- Baseline: shocks ON ---
    model_shocks_on = Bit.Model(nb03_p_AT, nb03_ic_AT)
    Bit.run!(model_shocks_on, 20)

    # --- No-burn-in: shocks OFF (zero covariance matrix only) ---
    # model.prop.C is the 3×3 covariance matrix of the three CORRELATED innovations
    # (eps_Y_EA, eps_E, eps_I). The other two exogenous processes — government
    # consumption and euro-area inflation — draw from their own scalar sigmas
    # (gov.sigma_G, rotw.sigma_pi_EA) and are NOT silenced by zeroing C.
    # That is precisely why scenario 3 below is quieter than scenario 2.
    # Setting it to zero suppresses all stochastic noise; deterministic AR(1) drift remains.
    Random.seed!(42)
    model_no_shocks = Bit.Model(nb03_p_AT, nb03_ic_AT)
    model_no_shocks.prop.C .= 0.0
    Bit.run!(model_no_shocks, 20)

    # --- Full steady state ---
    # Bit.STEADY_STATE2010Q1 is a special calibration where all AR(1) drift and noise
    # are zero, the policy rate is fixed at zero, and agent histories are pre-loaded
    # with flat time series so OLS expectations stay inert every quarter.
    Random.seed!(42)
    nb03_ss_p, nb03_ss_ic = Bit.STEADY_STATE2010Q1.parameters, Bit.STEADY_STATE2010Q1.initial_conditions
    model_steady = Bit.Model(nb03_ss_p, nb03_ss_ic)
    Bit.run!(model_steady, 20)

    "Simulations complete ✓"
end

# ╔═╡ 03000000-0000-0000-0000-00000000000c
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

# ╔═╡ 03000000-0000-0000-0000-00000000000d
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

# ╔═╡ 03000000-0000-0000-0000-00000000000e
md"""
---
## 4 — Austria vs Italy

BeforeIT ships a second calibration for Italy. Let's compare the two economies side-by-side on key structural parameters.
"""

# ╔═╡ 03000000-0000-0000-0000-00000000000f
begin
    pAT = Bit.Model(nb03_p_AT, nb03_ic_AT).prop
    pIT = Bit.Model(nb03_p_IT, nb03_ic_IT).prop

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

# ╔═╡ 03000000-0000-0000-0000-000000000010
@bind run_countries PlutoUI.Button("▶ Run Austria vs Italy (20 quarters each)")

# ╔═╡ 03000000-0000-0000-0000-000000000011
begin
    run_countries
    Random.seed!(42)

    _m_AT = Bit.Model(nb03_p_AT, nb03_ic_AT)
    _m_IT = Bit.Model(nb03_p_IT, nb03_ic_IT)

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

# ╔═╡ 03000000-0000-0000-0000-000000000012
md"""
Structural differences in MPC, tax rates, and unemployment benefit replacement rates show up in the GDP path and inflation dynamics within just a few quarters.
"""

# ╔═╡ 03000000-0000-0000-0000-000000000013
md"""
---
## ✔ What you learned

- ~50 parameters are read from data; only the AR(1)/Taylor rule block is estimated.
- The initial balance sheets are loaded from Eurostat national accounts — the SFC structure is exact at $t=0$.
- Setting `model.prop.C .= 0` zeros three of the five AR(1) shock processes — the correlated ones; government consumption and euro-area inflation keep drawing from their own sigmas. `Bit.STEADY_STATE2010Q1` goes further by also zeroing AR(1) drift and flattening agent expectation histories. Together these demonstrate the **quasi-fixed-point** property that eliminates burn-in.
- Italy and Austria have measurably different structures, visible after just 20 quarters.

---
## Exercises

**Exercise 03.1** — Which parameter differs most between Austria and Italy in the comparison table? What economic mechanism would this affect most strongly?

**Exercise 03.2**  — Partially remove shocks by scaling the covariance matrix: `model.prop.C .*= 0.5`. How does GDP volatility compare to the full-shock and no-shock cases?

**Exercise 03.3** — Try scaling the covariance matrix in steps: `model.prop.C .*= f` for `f ∈ {0.0, 0.1, 0.25, 0.5, 0.75, 1.0}`. Plot maximum GDP deviation as a function of `f`. Is the relationship between shock amplitude and GDP volatility approximately linear?

**Exercise 03.4** *(stretch)* — Run the full steady-state scenario for 80 quarters instead of 20. Does the deviation remain small? Now run `Bit.ITALY2010Q1` with the same `C=0` treatment. Is Italy's deviation larger or smaller than Austria's at 20 quarters?
"""

# ╔═╡ Cell order:
# ╟─03000000-0000-0000-0000-000000000002
# ╠═03000000-0000-0000-0000-000000000001
# ╠═03000000-0000-0000-0000-000000000003
# ╟─03000000-0000-0000-0000-000000000004
# ╠═03000000-0000-0000-0000-000000000005
# ╟─03000000-0000-0000-0000-000000000006
# ╟─03000000-0000-0000-0000-000000000007
# ╠═03000000-0000-0000-0000-000000000008
# ╟─03000000-0000-0000-0000-000000000009
# ╠═03000000-0000-0000-0000-00000000000a
# ╠═03000000-0000-0000-0000-00000000000b
# ╠═03000000-0000-0000-0000-00000000000c
# ╟─03000000-0000-0000-0000-00000000000d
# ╟─03000000-0000-0000-0000-00000000000e
# ╠═03000000-0000-0000-0000-00000000000f
# ╠═03000000-0000-0000-0000-000000000010
# ╠═03000000-0000-0000-0000-000000000011
# ╟─03000000-0000-0000-0000-000000000012
# ╟─03000000-0000-0000-0000-000000000013
