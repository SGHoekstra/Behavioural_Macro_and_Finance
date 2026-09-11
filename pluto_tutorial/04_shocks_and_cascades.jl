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

# ╔═╡ 04000000-0000-0000-0000-000000000001
begin
    import Pkg
    Pkg.activate(dirname(@__FILE__))
    import BeforeIT as Bit
    import Random
    using Plots, StatsPlots, PlutoUI, Statistics
end

# ╔═╡ 04000000-0000-0000-0000-000000000002
md"""
# Notebook 04 — Shocks and Bankruptcy Cascades

> **Question this notebook answers:** can a small shock to one sector trigger a recession that lasts for years without any further disturbance?

### Lecture 2 slides covered
- *What drives fluctuations? Five exogenous AR(1) processes*
- *Endogenous crises: the bankruptcy cascade*

### Learning goals
1. Understand the five AR(1) shock processes that drive the model.
2. Apply a custom shock interactively and trace the GDP response.
3. Visualise a bankruptcy cascade through its three propagation channels.
4. Discover the non-linearity of the cascade response.
"""

# ╔═╡ 04000000-0000-0000-0000-000000000003
begin
    nb04_p  = Bit.AUSTRIA2010Q1.parameters
    nb04_ic = Bit.AUSTRIA2010Q1.initial_conditions
    "Calibration loaded ✓"
end

# ╔═╡ 04000000-0000-0000-0000-000000000004
md"""
---
## 1 — The five AR(1) shock processes

Unlike the Assenza et al. (2015) model (Lecture 1) where fluctuations are entirely endogenous, the Poledna ABM is driven by five exogenous AR(1) processes estimated from Austrian national accounts:

| # | Process | Code | Direction |
|---|---------|------|-----------|
| 1 | Export demand $C^E_t$ | `model.agg.epsilon_E` | Push GDP up via foreign demand |
| 2 | Import supply $Y^I_t$ | `model.agg.epsilon_I` | Raise import costs → compress domestic demand |
| 3 | Government consumption $C^G_t$ | via `gov` step | Direct fiscal stimulus/drag |
| 4 | Euro-area GDP growth $\gamma^{EA}_t$ | `model.agg.epsilon_Y_EA` | Feeds Taylor rule |
| 5 | Euro-area inflation $\pi^{EA}_t$ | — | Feeds Taylor rule |

Each process is drawn each quarter from $\mathcal{N}(0, \mathbf{C})$ where $\mathbf{C}$ is the covariance matrix estimated from data. Let's look at the shock realisations over a simulated run.
"""

# ╔═╡ 04000000-0000-0000-0000-000000000005
@bind run_baseline PlutoUI.Button("▶ Run baseline (20 quarters)")

# ╔═╡ 04000000-0000-0000-0000-000000000006
begin
    run_baseline
    _m_base = Bit.Model(nb04_p, nb04_ic)
    Bit.run!(_m_base, 20)
    "Baseline run complete ✓"
end

# ╔═╡ 04000000-0000-0000-0000-000000000007
begin
    run_baseline
    plot(
        Bit.plot_data(_m_base, quantities = [
            :real_gdp, :real_exports, :real_imports,
            :real_government_consumption, :euribor, :wages
        ])...,
        layout = (2, 3), size = (850, 500),
        title  = ["Real GDP" "Exports" "Imports" "Gov. consumption" "Euribor" "Wages"],
    )
end

# ╔═╡ 04000000-0000-0000-0000-000000000008
md"""
---
## 2 — Interactive shock experiment

BeforeIT accepts a **callable struct** as a `shock!` argument to `Bit.ensemblerun!`. The shock is applied at each step before the goods market clears.

Use the controls below to design a shock and observe the GDP impulse response.
"""

# ╔═╡ 04000000-0000-0000-0000-000000000009
md"""
**Shock type:** $(@bind shock_type PlutoUI.Select(["Productivity", "Consumption (MPC)"], default="Productivity"))

**Shock size (multiplier, 1.0 = no shock):** $(@bind shock_size PlutoUI.Slider(0.80:0.01:1.20, default=0.95, show_value=true))

**Number of MC paths:** $(@bind n_shock_mc PlutoUI.Slider([8, 16, 32], default=16, show_value=true))
"""

# ╔═╡ 04000000-0000-0000-0000-000000000018
# Shock type definitions — in a standalone cell so they are never redefined on button press.
# (Redefining a struct in Julia raises an error; keeping these outside the button-triggered
# cell ensures they run exactly once when the notebook loads.)
begin
    struct Nb04ProductivityShock; mult::Float64 end
    struct Nb04ConsumptionShock;  mult::Float64 end

    function (s::Nb04ProductivityShock)(model)
        if model.agg.t == 1
            model.firms.alpha_bar_i .*= s.mult
        end
    end
    function (s::Nb04ConsumptionShock)(model)
        if model.agg.t == 1
            model.prop.psi *= s.mult
        end
    end
end

# ╔═╡ 04000000-0000-0000-0000-00000000000a
@bind run_shock PlutoUI.Button("▶ Run shocked vs baseline")

# ╔═╡ 04000000-0000-0000-0000-00000000000b
begin
    run_shock

    chosen_shock = shock_type == "Productivity" ?
        Nb04ProductivityShock(shock_size) : Nb04ConsumptionShock(shock_size)

    # Fix the seeds so that re-running with unchanged sliders reproduces the
    # same figure. Without this, the difference between two shock sizes is
    # confounded with Monte Carlo noise across runs.
    #
    # The two ensembles get DIFFERENT seeds, so they stay independent — which
    # is the assumption behind the delta-method error band below. Pairing them
    # on a common seed (common random numbers) narrows the band 131x at the
    # impact quarter, but the median across all 20 quarters is 1.0x: once a
    # firm goes bankrupt in one arm and not the other the paths decouple, and
    # the pairing is worth nothing thereafter.
    #
    # Caveat on "reproducible": ensemblerun! is threaded by default, so the
    # order of floating-point reductions varies between runs. A single seeded
    # ensemble reproduces to ~1e-15 relative — but the model contains discrete
    # thresholds (a firm goes bankrupt or it does not), and a rounding
    # difference that lands near one of them flips the branch and diverges
    # macroscopically. In practice that is rare but visible: occasional
    # ~0.1% differences in the aggregate. Pass parallel = false for exact
    # reproduction, at roughly nthreads() times the runtime.
    NB04_SEED_BASE    = 4040
    NB04_SEED_SHOCKED = 4041

    Random.seed!(NB04_SEED_BASE)
    _models_base    = Bit.ensemblerun!(
        (Bit.Model(nb04_p, nb04_ic) for _ in 1:n_shock_mc), 20)
    Random.seed!(NB04_SEED_SHOCKED)
    _models_shocked = Bit.ensemblerun!(
        (Bit.Model(nb04_p, nb04_ic) for _ in 1:n_shock_mc), 20;
        shock! = chosen_shock)

    "Shock experiment complete ✓"
end

# ╔═╡ 04000000-0000-0000-0000-00000000000c
begin
    run_shock

    # Stack ensemble trajectories into (T+1) × n_mc matrices
    gdp_base_mat    = hcat([m.data.real_gdp for m in _models_base]...)
    gdp_shocked_mat = hcat([m.data.real_gdp for m in _models_shocked]...)

    gdp_base_mean    = mean(gdp_base_mat,    dims = 2)[:]
    gdp_shocked_mean = mean(gdp_shocked_mat, dims = 2)[:]
    gdp_ratio        = gdp_shocked_mean ./ gdp_base_mean

    # Error propagation for a ratio of two noisy means
    sem_base    = std(gdp_base_mat,    dims = 2)[:] ./ sqrt(n_shock_mc)
    sem_shocked = std(gdp_shocked_mat, dims = 2)[:] ./ sqrt(n_shock_mc)
    sem_ratio   = gdp_ratio .* sqrt.((sem_base    ./ gdp_base_mean).^2 .+
                                     (sem_shocked ./ gdp_shocked_mean).^2)

    plot(
        0:20, gdp_ratio,
        ribbon = sem_ratio, fillalpha = 0.2,
        label = "Shocked / Baseline GDP ratio",
        xlabel = "Quarter", ylabel = "GDP ratio (1.0 = no effect)",
        title  = "Impulse response: $(shock_type) shock × $(shock_size)",
        lw = 2, color = :steelblue,
    )
    hline!([1.0], label = "No effect", color = :black, ls = :dash, lw = 1)
end

# ╔═╡ 04000000-0000-0000-0000-00000000000d
md"""
Move the **shock size** slider below 1.0 (negative shock) and click **Run** again. Notice:
- A productivity shock $< 1$ raises unit costs → firms set higher prices → demand falls → GDP contracts.
- The effect persists because bankrupt firms don't immediately recover — the cascade propagates through the three channels.
"""

# ╔═╡ 04000000-0000-0000-0000-000000000013
md"""
**Reading the plots:**
- Top-left (GDP): the gap between baseline and shocked paths widens over time — **amplification without further shocks**.
- Top-right (wages): the labour channel fires immediately — wages fall as employment contracts.
- Bottom-left (policy rate): the Taylor rule responds to the contraction, cutting rates — monetary policy tries to offset the shock.
- Bottom-right (consumption): household income falls through the labour channel, depressing consumption further.

This is what Lecture 2 calls the "medium-term recession without any further exogenous disturbance" — the defining feature that distinguishes the ABM from linearised DSGE where balance-sheet constraints don't bind.
"""

# ╔═╡ 04000000-0000-0000-0000-000000000014
md"""
---
## 3 — Non-linearity: is the response proportional to the shock?

Lecture 2 claims the cascade is **non-linear and path-dependent**. Let's test this by varying shock size and measuring where real GDP ends up after 20 quarters, relative to an unshocked baseline.

Every point on the curve is measured against the *same* baseline ensemble, and each shocked ensemble reuses the baseline's seed. That **anchors** the curve: at a multiplier of 1.0 the shock does nothing, so the ratio comes out at exactly 1.

It does *not* smooth the curve. Path dependence decouples a shocked run from the baseline within a few quarters, so each multiplier still carries its own Monte Carlo noise and the line stays jagged. Raise the MC-paths slider if you want a cleaner read — that is the only thing that helps here.
"""

# ╔═╡ 04000000-0000-0000-0000-000000000015
@bind run_nonlinear PlutoUI.Button("▶ Scan shock sizes (slow, ~2–3 min)")

# ╔═╡ 04000000-0000-0000-0000-000000000016
begin
    run_nonlinear

    NB04_SCAN_SEED = 4042
    shock_mults = 0.70:0.05:1.2

    # The baseline is drawn ONCE and reused for every multiplier. Re-drawing it
    # inside the loop meant each point on the curve was measured against a
    # different baseline, mixing Monte Carlo noise into exactly the curvature
    # this plot is meant to reveal: the old cell reported a 2.1% GDP effect at
    # multiplier 1.0, where the shock is a no-op. Hoisting it also cuts the
    # cell from 22 ensemble runs to 12.
    Random.seed!(NB04_SCAN_SEED)
    _scan_base = Bit.ensemblerun!(
        (Bit.Model(nb04_p, nb04_ic) for _ in 1:n_shock_mc), 20)
    scan_base_mean = mean(hcat([mm.data.real_gdp for mm in _scan_base]...), dims = 2)[:]

    terminal_ratios = Float64[]
    for mult in shock_mults
        # Same seed as the baseline, so the two ensembles differ only by the
        # shock. At mult = 1.0 the shock is a no-op, so the ratio is 1 up to
        # floating-point tolerance and the curve is anchored there.
        Random.seed!(NB04_SCAN_SEED)
        _scan_shocked = Bit.ensemblerun!(
            (Bit.Model(nb04_p, nb04_ic) for _ in 1:n_shock_mc), 20;
            shock! = Nb04ProductivityShock(mult))
        scan_shocked_mean =
            mean(hcat([mm.data.real_gdp for mm in _scan_shocked]...), dims = 2)[:]

        # Terminal GDP relative to baseline, after 20 quarters. Note this is a
        # ratio, not a percentage, and it is the level at the end of the
        # horizon rather than the trough — the axis label used to say both.
        push!(terminal_ratios, (scan_shocked_mean ./ scan_base_mean)[end])
    end

    plot(
        collect(shock_mults), terminal_ratios,
        xlabel = "Productivity multiplier",
        ylabel = "Terminal GDP ratio (shocked / baseline)",
        title  = "Non-linearity: shock size vs terminal GDP",
        marker = :circle, lw = 2, color = :steelblue, label = "",
    )
    hline!([1.0], label = "Baseline", color = :grey, ls = :dash)
    vline!([1.0], label = "No shock", color = :grey, ls = :dot)
end

# ╔═╡ 04000000-0000-0000-0000-000000000017
md"""
If the response were **linear**, the points would lie on a straight line. Non-linearity shows up as a convex or concave curve — the cascade mechanism amplifies shocks disproportionately beyond a threshold.
"""

# ╔═╡ 3e398baa-3912-11f1-b7e8-2fcca456812d
md"""
---
## ✔ What you learned

- Five exogenous AR(1) processes drive the model; they're drawn from a calibrated covariance matrix `model.prop.C`.
- A custom shock is a callable struct that modifies model state; passed as `shock!` to `ensemblerun!`.
- The bankruptcy cascade propagates through labour, supply-chain, and credit channels simultaneously.
- Setting `model.agg.t == 1` inside the shock callable makes the shock permanent-from-period-1 style.
- The GDP response to a productivity shock is non-linear — small shocks may be absorbed; large ones trigger cascades.

---
## Exercises

**Exercise 04.1** — Using the interactive shock controls, find the approximate multiplier threshold below which the GDP ratio at quarter 20 drops below 0.95. Does this threshold depend on the shock type (productivity vs consumption)?

**Exercise 04.2** — Apply a **positive** productivity shock (`shock_size > 1.0`). Does the economy overshoot and then correct? Is the positive response as persistent as the negative one?

**Exercise 04.3** *(stretch)* — Modify the cascade shock to apply to only **one sector**. Inside your shock callable, first build the sector-assignment vector: `sector_id = vcat([fill(s, model.prop.I_s[s]) for s in eachindex(model.prop.I_s)]...)`, then apply the shock to only that sector: `model.firms.alpha_bar_i[sector_id .== 3] .*= s.mult`. How does the aggregate GDP response compare to shocking all sectors equally?
"""

# ╔═╡ Cell order:
# ╟─04000000-0000-0000-0000-000000000002
# ╠═04000000-0000-0000-0000-000000000001
# ╠═04000000-0000-0000-0000-000000000003
# ╟─04000000-0000-0000-0000-000000000004
# ╠═04000000-0000-0000-0000-000000000005
# ╠═04000000-0000-0000-0000-000000000006
# ╠═04000000-0000-0000-0000-000000000007
# ╟─04000000-0000-0000-0000-000000000008
# ╠═04000000-0000-0000-0000-000000000009
# ╟─04000000-0000-0000-0000-000000000018
# ╠═04000000-0000-0000-0000-00000000000a
# ╠═04000000-0000-0000-0000-00000000000b
# ╠═04000000-0000-0000-0000-00000000000c
# ╟─04000000-0000-0000-0000-00000000000d
# ╟─04000000-0000-0000-0000-000000000013
# ╠═04000000-0000-0000-0000-000000000014
# ╠═04000000-0000-0000-0000-000000000015
# ╠═04000000-0000-0000-0000-000000000016
# ╟─04000000-0000-0000-0000-000000000017
# ╠═3e398baa-3912-11f1-b7e8-2fcca456812d
