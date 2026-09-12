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

# ╔═╡ 2c278f24-aeb1-11f1-af9b-c5924659f871
begin
    nb3_p  = Bit.AUSTRIA2010Q1.parameters
    nb3_ic = Bit.AUSTRIA2010Q1.initial_conditions
    "Calibration loaded ✓"
end

# ╔═╡ 2c278f44-aeb1-11f1-a7d6-0786c7458453
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

Processes 1, 2 and 4 — the ones with an `epsilon_*` field — are drawn jointly each quarter from $\mathcal{N}(0, \mathbf{C})$, where $\mathbf{C}$ is the $3\times3$ covariance matrix estimated from data, so they are *correlated*. Processes 3 and 5 draw independently from their own scalar standard deviations (`gov.sigma_G` and `rotw.sigma_pi_EA`) and are not part of $\mathbf{C}$. Let's look at the shock realisations over a simulated run.
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
        title  = ["Real GDP" "Exports" "Imports" "Gov. consumption" "Euribor" "Wages"],
    )
end

# ╔═╡ 2c278f9c-aeb1-11f1-860a-63e91f994997
md"""
---
## 2 — Interactive shock experiment

BeforeIT accepts a **callable struct** as a `shock!` argument to `Bit.ensemblerun!`. The shock is applied at each step before the goods market clears.

Use the controls below to design a shock and observe the GDP impulse response.
"""

# ╔═╡ 2c278fb0-aeb1-11f1-a8fa-0331ace63bdd
md"""
**Shock type:** $(@bind shock_type PlutoUI.Select(["Productivity", "Consumption (MPC)"], default="Productivity"))

**Shock size (multiplier, 1.0 = no shock):** $(@bind shock_size PlutoUI.Slider(0.80:0.01:1.20, default=0.95, show_value=true))

**Number of MC paths:** $(@bind n_shock_mc PlutoUI.Slider([8, 16, 32], default=16, show_value=true))
"""

# ╔═╡ 2c278fc4-aeb1-11f1-b35e-b9290280c086
# Shock type definitions — in a standalone cell so they are never redefined on button press.
# (Redefining a struct in Julia raises an error; keeping these outside the button-triggered
# cell ensures they run exactly once when the notebook loads.)
begin
    struct Nb3ProductivityShock; mult::Float64 end
    struct Nb3ConsumptionShock;  mult::Float64 end

    function (s::Nb3ProductivityShock)(model)
        if model.agg.t == 1
            model.firms.alpha_bar_i .*= s.mult
        end
    end
    function (s::Nb3ConsumptionShock)(model)
        if model.agg.t == 1
            model.prop.psi *= s.mult
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
    NB3_SEED_BASE    = 4040
    NB3_SEED_SHOCKED = 4041

    Random.seed!(NB3_SEED_BASE)
    _models_base    = Bit.ensemblerun!(
        (Bit.Model(nb3_p, nb3_ic) for _ in 1:n_shock_mc), 20)
    Random.seed!(NB3_SEED_SHOCKED)
    _models_shocked = Bit.ensemblerun!(
        (Bit.Model(nb3_p, nb3_ic) for _ in 1:n_shock_mc), 20;
        shock! = chosen_shock)

    "Shock experiment complete ✓"
end

# ╔═╡ 2c27901e-aeb1-11f1-97bb-0d095ecd46fd
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

# ╔═╡ 2c279032-aeb1-11f1-93a6-310284d02e04
md"""
Move the **shock size** slider below 1.0 (negative shock) and click **Run** again. Notice:
- A productivity shock $< 1$ raises unit costs → firms set higher prices → demand falls → GDP contracts.
- The effect persists because bankrupt firms don't immediately recover — the cascade propagates through the three channels.
"""

# ╔═╡ 2c279050-aeb1-11f1-9ab8-f37ad5c40d3b
md"""
**Reading the plots:**
- Top-left (GDP): the gap between baseline and shocked paths widens over time — **amplification without further shocks**.
- Top-right (wages): the labour channel fires immediately — wages fall as employment contracts.
- Bottom-left (policy rate): the Taylor rule responds to the contraction, cutting rates — monetary policy tries to offset the shock.
- Bottom-right (consumption): household income falls through the labour channel, depressing consumption further.

This is what Lecture 2 calls the "medium-term recession without any further exogenous disturbance" — the defining feature that distinguishes the ABM from linearised DSGE where balance-sheet constraints don't bind.
"""

# ╔═╡ 2c27906e-aeb1-11f1-b728-01a680a89df4
md"""
---
## 3 — Non-linearity: is the response proportional to the shock?

Lecture 2 claims the cascade is **non-linear and path-dependent**. Let's test this by varying shock size and measuring where real GDP ends up after 20 quarters, relative to an unshocked baseline.

Every point on the curve is measured against the *same* baseline ensemble, and each shocked ensemble reuses the baseline's seed. That **anchors** the curve: at a multiplier of 1.0 the shock does nothing, so the ratio comes out at exactly 1.

It does *not* smooth the curve. Path dependence decouples a shocked run from the baseline within a few quarters, so each multiplier still carries its own Monte Carlo noise and the line stays jagged. Raise the MC-paths slider if you want a cleaner read — that is the only thing that helps here.
"""

# ╔═╡ 2c279078-aeb1-11f1-90c0-ddb27eeda0a6
@bind run_nonlinear PlutoUI.Button("▶ Scan shock sizes (slow, ~2–3 min)")

# ╔═╡ 2c2790a0-aeb1-11f1-80f1-9736724f909d
begin
    run_nonlinear

    NB3_SCAN_SEED = 4042
    shock_mults = 0.70:0.05:1.2

    # The baseline is drawn ONCE and reused for every multiplier. Re-drawing it
    # inside the loop meant each point on the curve was measured against a
    # different baseline, mixing Monte Carlo noise into exactly the curvature
    # this plot is meant to reveal: the old cell reported a 2.1% GDP effect at
    # multiplier 1.0, where the shock is a no-op. Hoisting it also cuts the
    # cell from 22 ensemble runs to 12.
    Random.seed!(NB3_SCAN_SEED)
    _scan_base = Bit.ensemblerun!(
        (Bit.Model(nb3_p, nb3_ic) for _ in 1:n_shock_mc), 20)
    scan_base_mean = mean(hcat([mm.data.real_gdp for mm in _scan_base]...), dims = 2)[:]

    terminal_ratios = Float64[]
    for mult in shock_mults
        # Same seed as the baseline, so the two ensembles differ only by the
        # shock. At mult = 1.0 the shock is a no-op, so the ratio is 1 up to
        # floating-point tolerance and the curve is anchored there.
        Random.seed!(NB3_SCAN_SEED)
        _scan_shocked = Bit.ensemblerun!(
            (Bit.Model(nb3_p, nb3_ic) for _ in 1:n_shock_mc), 20;
            shock! = Nb3ProductivityShock(mult))
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

# ╔═╡ 2c2790be-aeb1-11f1-9dfc-195170ee5996
md"""
If the response were **linear**, the points would lie on a straight line. Non-linearity shows up as a convex or concave curve — the cascade mechanism amplifies shocks disproportionately beyond a threshold.
"""

# ╔═╡ 2c2790c8-aeb1-11f1-b03c-d1ce6d30fdbb
md"""
---
# Part 2 — Expectations and policy

The dashboard above already showed the policy rate moving in response to the shock. That
response comes from two mechanisms this half makes explicit: how agents form expectations,
and how the central bank sets rates.
"""

# ╔═╡ 2c400cd6-aeb1-11f1-8bd9-e3408cd87a3a
md"""


> **Question this notebook answers:** how do agents form beliefs about the future, and how do monetary and fiscal policy constrain the economy's path?

### Lecture 2 slides covered
- *Household behaviour: consumption, savings, expectations* (AR(1) rules)
- *Fiscal and monetary closure*
- *What drives fluctuations?* (Taylor rule reacting to EA, not domestic, conditions)

### Learning goals
1. Understand the AR(1) expectation formation mechanism.
2. Compare AR(1) (forward-looking) vs constant (backward-looking) expectations.
3. Explore how Taylor rule parameters shape the policy-rate and GDP path.
4. Inspect fiscal closure: tax decomposition and debt dynamics.
"""

# ╔═╡ 2c400cf2-aeb1-11f1-ae5a-436dbaaa2fe5
md"""
---
## 4 — AR(1) expectation formation

Lecture 2, slide *"Household behaviour"*, gives the expectation rules:

$$\mathbb{E}^*_t[\pi_{t+1}] = \alpha^\pi_t \, \pi_t + \beta^\pi_t$$
$$\mathbb{E}^*_t[y_{t+1}] = \alpha^y_t \, y_t + \beta^y_t$$

where $\alpha^\pi_t, \beta^\pi_t, \alpha^y_t, \beta^y_t$ are updated **each quarter via OLS** on the history of realised inflation and output. This is **adaptive learning** — agents use all past data optimally but don't know the future.

The mechanism is implemented in `Bit.estimate_next_value(data)`, which accepts a vector of past realisations and returns the OLS-optimal AR(1) one-step-ahead forecast.

We can override this function via multiple dispatch to experiment with alternative expectation schemes.
"""

# ╔═╡ 2c400d08-aeb1-11f1-a996-8bbad67ea5d0
md"""
---
## 5 — AR(1) vs backward-looking expectations

Let's compare two expectation schemes:
- **AR(1) (default):** `Bit.estimate_next_value(data)` — OLS optimal forecast.
- **Constant (backward-looking):** always expect last period's value.

The `change_expectations.jl` upstream example shows exactly how to do this.
"""

# ╔═╡ 2c400d10-aeb1-11f1-a78b-15b23274db5d
@bind run_expectations PlutoUI.Button("▶ Compare expectations (40 quarters each, ~2 min)")

# ╔═╡ 2c400d1a-aeb1-11f1-a677-2582c519bb0e
begin
    run_expectations
    Random.seed!(1234)

    # --- Default: AR(1) forward-looking ---
    nb3_model_ar1 = Bit.Model(nb3_p, nb3_ic)
    Bit.run!(nb3_model_ar1, 40)

    # --- Override: constant/backward-looking expectations ---
    # Julia multiple dispatch: adding a 1-arg method that always returns the last value.
    function Bit.estimate_next_value(data)
        return data[end]    # always expect last period's value
    end

    Random.seed!(1234)
    nb3_model_const = Bit.Model(nb3_p, nb3_ic)
    Bit.run!(nb3_model_const, 40)

    # Restore the default OLS-AR(1) behaviour for the rest of this notebook session
    # by delegating back to BeforeIT's original 2-arg method.
    # Note: each Pluto notebook runs in its own Julia session, so this override
    # does not affect any other notebook.
    function Bit.estimate_next_value(data)
        return Bit.estimate_next_value(data, nothing)
    end

    "Expectations comparison complete ✓"
end

# ╔═╡ 2c400d24-aeb1-11f1-a52a-91454431a7e5
begin
    run_expectations
    p_exp_gdp = plot(
        nb3_model_ar1.data.real_gdp, label = "AR(1) expectations",
        lw = 2, color = :steelblue, title = "Real GDP",
        xlabel = "Quarter",
    )
    plot!(p_exp_gdp, nb3_model_const.data.real_gdp, label = "Constant expectations",
          lw = 2, color = :tomato, ls = :dash)

    p_exp_defl = plot(
        nb3_model_ar1.data.nominal_gdp ./ nb3_model_ar1.data.real_gdp, label = "AR(1)",
        lw = 2, color = :steelblue, title = "GDP deflator",
        xlabel = "Quarter",
    )
    plot!(p_exp_defl, nb3_model_const.data.nominal_gdp ./ nb3_model_const.data.real_gdp, label = "Constant",
          lw = 2, color = :tomato, ls = :dash)

    plot(p_exp_gdp, p_exp_defl, layout = (1, 2), size = (800, 350))
end

# ╔═╡ 2c400d36-aeb1-11f1-9d4d-bd47b9b16653
md"""
Differences reflect how well agents anticipate turning points:
- **AR(1)** agents can identify trends and adjust production/consumption earlier.
- **Constant** agents always anchor to last period's value — they are systematically surprised whenever the economy moves.

Higher volatility under constant expectations is a direct consequence of larger forecast errors feeding back into pricing and production decisions.
"""

# ╔═╡ 2c400d42-aeb1-11f1-9d9d-4ba30acda0d6
md"""
---
## 6 — The Taylor rule

Lecture 2 slide *"Fiscal and monetary closure"* gives the generalised Taylor rule:

$$\bar{r}_t = \rho\,\bar{r}_{t-1} + (1-\rho)\!\left[\pi^* + \xi^\pi(\pi^{EA}_t - \pi^*) + \xi^\gamma \gamma^{EA}_t\right]$$

**Key design choice:** the central bank reacts to **euro-area** inflation $\pi^{EA}$ and growth $\gamma^{EA}$, not domestic conditions. This is the small-open-economy assumption: Austria is in the eurozone and cannot set its own policy rate independently.

The estimated parameters (from the Lecture 2 parameter table):
- $\rho = 0.9263$ (high smoothing — the ECB moves rates slowly)
- $\xi^\pi = 0.3214$ (mild inflation response)
- $\xi^\gamma = 1.2994$ (stronger output growth response)

Let's explore how changing these parameters shifts the policy path.
"""

# ╔═╡ 2c400d4c-aeb1-11f1-bacf-29a092bcd5b0
md"""
**Taylor rule parameters:**

Smoothing $\rho$: $(@bind rho_val PlutoUI.Slider(0.0:0.05:0.99, default=0.9263, show_value=true))

Inflation weight $\xi^\pi$: $(@bind xi_pi_val PlutoUI.Slider(0.0:0.1:3.0, default=0.3214, show_value=true))

Growth weight $\xi^\gamma$: $(@bind xi_gamma_val PlutoUI.Slider(0.0:0.1:3.0, default=1.2994, show_value=true))
"""

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
        nb3_m_default.data.euribor .* 100, label = "Default (ρ=0.93, ξᵖ=0.32, ξᵞ=1.30)",
        lw = 2, color = :steelblue,
        title = "Policy rate (%)", xlabel = "Quarter", ylabel = "%",
    )
    plot!(nb3_p1, nb3_m_custom.data.euribor .* 100,
          label = "Custom (ρ=$(rho_val), ξᵖ=$(xi_pi_val), ξᵞ=$(xi_gamma_val))",
          lw = 2, color = :tomato, ls = :dash)

    nb3_p2 = plot(
        nb3_m_default.data.real_gdp, label = "Default", lw = 2, color = :steelblue,
        title = "Real GDP", xlabel = "Quarter",
    )
    plot!(nb3_p2, nb3_m_custom.data.real_gdp, label = "Custom", lw = 2, color = :tomato, ls = :dash)

    nb3_p3 = plot(
        nb3_m_default.data.nominal_gdp ./ nb3_m_default.data.real_gdp, label = "Default", lw = 2, color = :steelblue,
        title = "GDP deflator", xlabel = "Quarter",
    )
    plot!(nb3_p3, nb3_m_custom.data.nominal_gdp ./ nb3_m_custom.data.real_gdp, label = "Custom", lw = 2, color = :tomato, ls = :dash)

    plot(nb3_p1, nb3_p2, nb3_p3, layout = (1, 3), size = (900, 320), legend = :bottomright)
end

# ╔═╡ 2c400d7e-aeb1-11f1-9eae-8ba00ee10b4c
md"""
Try:
- **Low smoothing** ($\rho \approx 0$): rates jump aggressively each quarter. Does this stabilise or destabilise GDP?
- **High inflation weight** ($\xi^\pi > 2$): strong anti-inflation stance. How does this affect real output?
- **Zero growth weight** ($\xi^\gamma = 0$): pure inflation-targeting. Compare to the "balanced" calibration.
"""

# ╔═╡ 2c400d92-aeb1-11f1-8cb4-5f0af2b94c90
md"""
The government sector is fully embedded in the SFC structure — every transfer, tax, and interest payment is accounted for on both sides of the balance sheet. There is no "black box" government in this model.
"""

# ╔═╡ 2c400d9a-aeb1-11f1-93cd-73e608b43691
md"""
---
## ✔ What you learned

Shocks:

- Five exogenous AR(1) processes drive the model. Three are drawn jointly from the calibrated 3×3 covariance matrix `model.prop.C`; government consumption and euro-area inflation draw from their own scalar sigmas.
- A custom shock is a callable struct that mutates model state, passed as `shock!` to `ensemblerun!` — note the bang.
- Seed both ensembles explicitly, or Monte Carlo noise is confounded with whatever you changed. Measure the response against one shared baseline rather than redrawing it per setting.
- The response is not proportional to the shock: bankruptcy cascades propagate through the input–output network and make it path-dependent.

Expectations and policy:

- Agents update AR(1) expectation coefficients via OLS each quarter — adaptive learning, not rational expectations.
- Overriding `Bit.estimate_next_value` changes the expectation scheme for all agents; multiple dispatch is the extension mechanism.
- The Taylor rule responds to **euro-area** (not domestic) conditions — the small-open-economy constraint.
- High smoothing ($\rho \approx 0.93$) creates persistent monetary policy inertia.

---
## Exercises

**Exercise 03.4** — Set $\xi^\pi = 0$ (Taylor rule ignores inflation entirely) and compare GDP deflator paths against the baseline. Does the economy become more or less inflationary?

**Exercise 03.5** — Run the constant-expectations model 10 times with different seeds. Compute the standard deviation of real GDP at quarter 20. Compare to the AR(1) model. Which generates more volatility?

**Exercise 03.6** *(stretch)* — Modify the Taylor rule to respond to **domestic** inflation instead of euro-area inflation. You'll need to override a different function in `Bit`. Hint: look at `Bit.set_central_bank_rate!` and create a method for a custom model type. Is the policy-rate path smoother or noisier?
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
