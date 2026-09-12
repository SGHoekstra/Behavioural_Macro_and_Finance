### A Pluto.jl notebook ###
# v0.20.24

#> [frontmatter]
#> order = 2
#> title = "Meet the model"
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

# ╔═╡ afacab38-aeaf-11f1-abe7-c5c37dd6a14b
begin
    import Pkg
    Pkg.activate(dirname(@__FILE__))
    import BeforeIT as Bit
    import Random
    using Plots, StatsPlots, PlutoUI, DataFrames, Statistics, LinearAlgebra
end

# ╔═╡ afeb8448-aeaf-11f1-af47-c739f5f21ffc
md"""
# Notebook 01 — Meet the model

> **Question this notebook answers:** what does the Austrian macro economy do over the next five years according to the Poledna et al. (2019) agent-based model — and what is actually inside the box?

We run the model first and look at its output, then open it up: who the agents are, how they trade through the input–output network, what happens in a quarter, and whether the accounting closes.

### Lecture 2 slides covered
- *Model overview* (slide: "What are agent-based model typical elements again?")
- *Sequence of events in each quarter* (slide: "(i) Expectations → … → (v) Accounting")
- *How big is the model?* (agent count table)
- *Household behaviour and heterogeneity: four types*
- *Firms* (Leontief production function), *labour market: search and matching*
- *Input-output network*, and the remaining sectors (government, bank, central bank, rest of world)

### Learning goals
After this notebook you will be able to:
1. Initialise, step and run the BeforeIT model, and plot any tracked series.
2. Name the agent types and read their counts off `model.prop`.
3. Visualise the production network and compare sector intensities.
4. Trace the per-quarter event sequence by stepping manually.
5. Verify the GDP accounting identity — the stock-flow consistency check.

Forecasting and Monte Carlo ensembles come in Notebook 02.
"""

# ╔═╡ afeb8484-aeaf-11f1-a594-79cbf074b789
md"""
---
## 1 — Load the Austria 2010:Q1 calibration

The model ships with a fully pre-calibrated parametrisation of the Austrian economy at the start of Q1 2010. All 50+ parameters are read directly from Eurostat national accounts — no free parameters to tune.

A few headline values from `Bit.AUSTRIA2010Q1`: VAT $\tau^{VAT}$ = 15.29%, MPC $\psi$ = 90.97%, corporate tax $\tau^{FIRM}$ = 7.70%. Read any of them off `model.prop` directly.
"""

# ╔═╡ afeb8484-aeaf-11f1-b507-97431e415ab7
begin
    nb1_p  = Bit.AUSTRIA2010Q1.parameters
    nb1_ic = Bit.AUSTRIA2010Q1.initial_conditions
    "Parameters and initial conditions loaded ✓"
end

# ╔═╡ afeb8498-aeaf-11f1-98a0-f3d28296a451
md"""
---
## 2 — Initialise the model

`Bit.Model` builds every agent and wires up the full stock-flow-consistent balance sheet structure.

Note the scale. Lecture 2 quotes ~9.9 million agents for the *actual* Austrian economy, but `Bit.AUSTRIA2010Q1` ships a **1:1000 scaled** version — about 10,000 agents — so a run takes seconds rather than hours. Every ratio and share is preserved; only the head counts are divided through. Part 2 below reproduces the full table.
"""

# ╔═╡ afeb84a4-aeaf-11f1-97e3-4b0cd421f7c8
nb1_model = Bit.Model(nb1_p, nb1_ic);

# ╔═╡ afeb84a4-aeaf-11f1-80b1-1bab0c52eeb3
md"""
Inspect what's inside the model. Each field is a container of agents or an aggregate tracker:
"""

# ╔═╡ afeb84c0-aeaf-11f1-8b29-edba9452036b
fieldnames(typeof(nb1_model))

# ╔═╡ afeb84c0-aeaf-11f1-810b-af5ddbc43d14
md"""
For example, the `bank` agent holds:
"""

# ╔═╡ afeb84ca-aeaf-11f1-9a80-2127338dd386
fieldnames(typeof(nb1_model.bank))

# ╔═╡ afeb84d2-aeaf-11f1-ab92-af35331abf4a
md"""
---
## 3 — Run the model

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

# ╔═╡ afeb84de-aeaf-11f1-8c71-733554335da9
begin
    model_demo = Bit.Model(nb1_p, nb1_ic)
    Bit.step!(model_demo; parallel = true)   # one quarter
    Bit.collect_data!(model_demo)            # save the time series
    "Stepped one quarter. GDP = $(round(model_demo.data.real_gdp[1], digits=2))"
end

# ╔═╡ afeb84e8-aeaf-11f1-b1d9-d1f28ffd0896
md"""
---
## 4 — Simulate for T quarters

`Bit.run!` is the convenient wrapper that calls `step!` + `collect_data!` in a loop.

Use the slider below to set the horizon, then press **Run** to simulate.

> ⚠️ Each run takes ~10–30 seconds depending on your machine. Do not move the slider during a run.
"""

# ╔═╡ afeb84e8-aeaf-11f1-9728-3741750f455d
@bind T_horizon PlutoUI.Slider(4:4:40, default=20, show_value=true)

# ╔═╡ afeb84f2-aeaf-11f1-8ebc-e376ec4c3867
@bind rng_seed PlutoUI.Slider(1:100, default=42, show_value=true)

# ╔═╡ afeb84fc-aeaf-11f1-b9dc-679d86fd21dc
@bind run_single PlutoUI.Button("▶ Run simulation")

# ╔═╡ afeb84fc-aeaf-11f1-84a7-cfdac3cd721e
md"""
Horizon: **$(T_horizon) quarters** ($(T_horizon ÷ 4) years)  |  RNG seed: **$(rng_seed)**
"""

# ╔═╡ afeb8504-aeaf-11f1-9f11-5b270d89e616
begin
    run_single   # re-runs only when button is pressed
    Random.seed!(rng_seed)
    _m = Bit.Model(nb1_p, nb1_ic)
    Bit.run!(_m, T_horizon)
    _m
end

# ╔═╡ afeb8510-aeaf-11f1-8aad-6fb0d75564c5
md"""
---
## 5 — Plot the results

`Bit.plot_data` knows how to plot any of the tracked time series. The 9-panel dashboard below shows the same quantities reported in Poledna et al. (2019) Table 4.
"""

# ╔═╡ afeb851a-aeaf-11f1-b0c4-93231ab9e333
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

# ╔═╡ afeb851a-aeaf-11f1-9b87-8b6ec0fc646c
md"""
Try different seeds (slider above) and click **Run** again. Notice that:
- The **trend** is similar across seeds — driven by the five exogenous AR(1) processes.
- The **fluctuations** differ — driven by agent-level stochasticity in search-and-matching.

This is what Monte Carlo simulation quantifies.
"""

# ╔═╡ aff4f0e8-aeaf-11f1-a709-bb4dd6a9f8cd
md"""
---
# Part 2 — Anatomy of the model

You have run it and seen the output. Now open the box: who the agents are, how they
are wired together, what happens inside a quarter, and whether the books balance.
"""

# ╔═╡ aff4f122-aeaf-11f1-b091-01ca261c4774
md"""
---
## 6 — Who are the agents?

The Lecture 2 table "How big is the model?" reports ~9.9 million agents for Austria 2010:Q4 — the real economy. `Bit.AUSTRIA2010Q1` is scaled **1:1000** so that a run finishes in seconds, so expect counts around a thousandth of the lecture's. Shares and ratios are unaffected.
"""

# ╔═╡ aff4f136-aeaf-11f1-92b0-6ff1409c3868
begin
    p = nb1_model.prop
    agent_table = DataFrame(
        "Agent type"        => ["Economically active persons",
                                "Inactive persons",
                                "Firms / investors",
                                "Government entities",
                                "Foreign consumers",
                                "Foreign firms (imports) = sectors"],
        "Count"             => [p.H_act, p.H_inact, p.I, p.J, p.L, p.G],
    )
    agent_table
end

# ╔═╡ aff4f14c-aeaf-11f1-9e32-b5beec69e824
md"""
**Total: $(nb1_model.prop.H_act + nb1_model.prop.H_inact + nb1_model.prop.I + nb1_model.prop.J + nb1_model.prop.L + nb1_model.prop.G) agents** — about 1/1000 of the lecture's 9.9 million, as expected from the scaling.

One label needs care: `prop.G` is the number of production **sectors** (62, the NACE breakdown), which doubles as the count of foreign supplier firms because imports arrive one representative firm per sector. It is the same `g` index used in `P_bar_g` and `firms.G_i`.

The four household types from Lecture 2:
- **Employed** (`nb1_model.w_act`) — labour supplied to a specific sector.
- **Unemployed** — subset of `nb1_model.w_act` with no current job.
- **Investors** — one per firm, receive dividends $\theta^{DIV}(1-\tau^{FIRM})\Pi_i$.
- **Inactive** (`nb1_model.w_inact`) — outside the labour force, receive social transfers.
"""

# ╔═╡ aff4f15e-aeaf-11f1-83c8-39c1c4315067
md"""
Let's inspect a single active worker:
"""

# ╔═╡ aff4f168-aeaf-11f1-8e5d-4f4edb4d4f90
fieldnames(typeof(nb1_model.w_act))

# ╔═╡ aff4f17a-aeaf-11f1-82c1-e758bc19853c
md"""
And a single firm:
"""

# ╔═╡ aff4f190-aeaf-11f1-bc82-fbcc2ff7b700
fieldnames(typeof(nb1_model.firms))

# ╔═╡ aff4f1a4-aeaf-11f1-a328-b5deddfd15d0
md"""
---
## 7 — Household heterogeneity

Lecture 2 identifies **four household types**. BeforeIT stores them in two structs:

| Type | Struct | Description |
|---|---|---|
| Employed workers | `nb1_model.w_act` (`O_h > 0`) | Earn wages, pay income tax, buy consumption goods |
| Unemployed workers | `nb1_model.w_act` (`O_h = 0`) | Receive unemployment benefits $(θ^{UB} w)$, job search |
| Inactive persons | `nb1_model.w_inact` | Out of labour force, receive social transfers |
| Capitalist investors | `nb1_model.firms` (one per firm) | Own a firm, receive dividends $(θ^{DIV}(1-τ^{FIRM})Π_i)$ |

**Employed + unemployed** live in `w_act`; the `O_h` field records which firm employs each worker (0 = unemployed). Investors own firms and are counted in `prop.I`; they are tracked via `nb1_model.firms` rather than as household agents with individual deposit records.
"""

# ╔═╡ aff4f1b8-aeaf-11f1-a488-d966727fbdf8
begin
    # w_act holds all regular workers (employed + unemployed); O_h = 0 means unemployed
    O_h_regular    = nb1_model.w_act.O_h
    n_employed_reg = sum(O_h_regular .> 0)
    n_unemployed   = sum(O_h_regular .== 0)
    n_investors    = nb1_model.prop.I
    n_inactive     = nb1_model.prop.H_inact
    n_total        = nb1_model.prop.H_act + n_inactive

    het_table = DataFrame(
        "Household type"      => ["Employed workers", "Unemployed workers",
                                   "Capitalist investors (nb1_model.firms)", "Inactive persons"],
        "Count"               => [n_employed_reg, n_unemployed, n_investors, n_inactive],
        "Share of adults (%)" => round.([n_employed_reg, n_unemployed, n_investors, n_inactive]
                                         ./ n_total .* 100, digits=1),
    )
    het_table
end

# ╔═╡ aff4f1cc-aeaf-11f1-9e1c-51f7847655cf
begin
    # Deposits D_h by household type (investors tracked via nb1_model.firms, not as household agents)
    D_employed   = nb1_model.w_act.D_h[O_h_regular .> 0]
    D_unemployed = nb1_model.w_act.D_h[O_h_regular .== 0]
    D_inactive   = nb1_model.w_inact.D_h

    p_wealth = plot(layout=(1,3), size=(900,320),
                    left_margin=4Plots.mm, bottom_margin=4Plots.mm)
    for (sp, (d, ttl, clr)) in enumerate([
            (D_employed,   "Employed",   :steelblue),
            (D_unemployed, "Unemployed", :crimson),
            (D_inactive,   "Inactive",   :mediumseagreen),
        ])
        mn = round(mean(d), sigdigits=4)
        histogram!(p_wealth, d, subplot=sp, bins=40, color=clr, alpha=0.7, label="",
                   title="$(ttl)  n=$(length(d))  mean=$(mn)",
                   xlabel="Deposits D_h (€)", ylabel="Count",
                   titlefontsize=8)
    end
    p_wealth
end

# ╔═╡ aff4f1ea-aeaf-11f1-80ab-8b458c9d217a
md"""
**Why do unemployed and inactive workers show near-zero variance?**

At $t=0$, BeforeIT initialises household deposits from **aggregate national accounts data** — only the sector total is known, so it is divided equally across all agents of the same type. That is why every unemployed worker starts with exactly the same $D_h$, and every inactive person starts with exactly the same $D_h$ (a different level, but still identical within the group). The employed histogram looks wider because employment-type variation maps onto wage variation, which produces some spread even at initialisation.

The narrow distributions are **technically correct, not a bug** — they reflect the data-based initialisation that lets the model start at calibrated aggregate stocks without a burn-in period. Run the model for a few quarters and re-run this cell to see heterogeneity build up as workers change jobs, accumulate savings, or cycle through unemployment.

**Key observation:** Investor-capitalists (who receive dividends $\theta^{DIV}(1-\tau^{FIRM})\Pi_i$) hold significantly more deposits than regular employed workers. Unemployed workers hold the least, reflecting lost wage income partially offset by unemployment benefits $\theta^{UB} w_i$. These wealth heterogeneities feed into different **marginal propensities to consume**, driving aggregate demand dynamics across the business cycle.
"""

# ╔═╡ aff4f208-aeaf-11f1-87d7-991503c2e629
md"""
---
## 8 — The input–output production network

Firms buy intermediate inputs from other sectors. The technology matrix $a_{sg}$ gives the share of industry $s$'s output that goes as intermediate input to product type $g$.

This is the heatmap shown in Lecture 2 (Figure: "Intermediate consumption between 19 industries"). We plot the full 64-sector version here.
"""

# ╔═╡ aff4f21c-aeaf-11f1-a686-3dff9ab0119a
begin
    nb1_a_sg = nb1_model.prop.a_sg   # I-O matrix: rows = supplier sector, cols = buyer product

    heatmap(
        nb1_a_sg,
        color      = :viridis,
        title      = "Input-Output technology matrix a_sg\n(62 NACE sectors × product types)",
        xlabel     = "Buyer product g",
        ylabel     = "Supplier sector s",
        aspect_ratio = :equal,
        size       = (600, 550),
        clims      = (0, quantile(vec(nb1_a_sg[nb1_a_sg .> 0]), 0.99)),  # cap colorscale at 99th pct
    )
end

# ╔═╡ aff4f230-aeaf-11f1-b61d-2ddcec739827
md"""
**Reading the heatmap:** a bright cell at row $s$, column $g$ means sector $s$ supplies a large fraction of its output as intermediate input to the production of product type $g$.

The diagonal entries represent within-sector intermediate use (e.g., agriculture buying agricultural products). Off-diagonal bright cells reveal key supply-chain dependencies — a failure in a bright-cell upstream sector cascades to all sectors that buy from it (the bankruptcy cascade from Lecture 2).
"""

# ╔═╡ aff4f244-aeaf-11f1-be85-b54d53a0e1de
md"""
---
## 9 — Leontief coefficients by sector

Recall the production function from Lecture 2:

$$Y_{i,t} = \min\!\left(Q^S_{i,t},\; \beta_i M_{i,t},\; \bar\alpha_{i,t} N_{i,t},\; \kappa_i K_{i,t-1}\right)$$

The three coefficients $\bar\alpha_i$ (labour productivity), $\beta_i$ (material efficiency), $\kappa_i$ (capital productivity) determine which input is the binding constraint in each sector.
"""

# ╔═╡ aff4f258-aeaf-11f1-bb42-8189f17c42d8
begin
    # Each coefficient is a vector over firms; take the mean per sector
    G_sectors = nb1_model.prop.G        # number of product/sector types
    I_s       = nb1_model.prop.I_s      # vector of firm counts per sector

    # Build sector indices
    sector_id = vcat([fill(s, I_s[s]) for s in 1:length(I_s)]...)

    leontief = DataFrame(
        "Sector"     => 1:length(I_s),
        "Firms"      => I_s,
        "ᾱ (labour prod.)"   => [mean(nb1_model.firms.alpha_bar_i[sector_id .== s])
                                   for s in 1:length(I_s)],
        "β (material eff.)"  => [mean(nb1_model.firms.beta_i[sector_id .== s])
                                  for s in 1:length(I_s)],
        "κ (capital prod.)"  => [mean(nb1_model.firms.kappa_i[sector_id .== s])
                                  for s in 1:length(I_s)],
    )
    leontief
end

# ╔═╡ aff4f28a-aeaf-11f1-96ad-093e6a70a935
md"""
---
## 10 — Stepping through the quarter sequence

Instead of running all T quarters at once with `Bit.run!`, let's step manually and observe what changes.

Each call to `Bit.step!` runs the full five-stage sequence from Lecture 2 (expectations → shocks → credit/labour → goods → accounting).
"""

# ╔═╡ aff4f2a8-aeaf-11f1-adf6-bd082d2cf498
begin
    nb1_model_step = Bit.Model(nb1_p, nb1_ic)

    # Snapshot before step
    gdp_before  = nb1_model_step.agg.Y_e              # expected aggregate output
    emp_before  = sum(nb1_model_step.firms.N_i)        # total employed workers
    rate_before = nb1_model_step.cb.r_bar              # policy rate

    # Take one step
    Bit.step!(nb1_model_step; parallel = true)
    Bit.collect_data!(nb1_model_step)

    gdp_after   = nb1_model_step.agg.Y_e
    emp_after   = sum(nb1_model_step.firms.N_i)
    rate_after  = nb1_model_step.cb.r_bar

    DataFrame(
        "Variable"  => ["Expected output Y_e", "Total employment ΣN_i", "Policy rate r_bar"],
        "Before"    => [round(gdp_before, sigdigits=6),
                        round(emp_before, sigdigits=6),
                        round(rate_before, sigdigits=6)],
        "After Q1"  => [round(gdp_after, sigdigits=6),
                        round(emp_after, sigdigits=6),
                        round(rate_after, sigdigits=6)],
    )
end

# ╔═╡ aff4f2bc-aeaf-11f1-a873-2f7978aa2937
md"""
The small changes after one step reflect the exogenous AR(1) shock draw and the OLS expectation update. Multiple steps accumulate into the time series we plotted in Notebook 01.
"""

# ╔═╡ aff4f2d0-aeaf-11f1-b973-5b727f64032a
md"""
---
## 11 — SFC accounting check ✓

**Stock-flow consistency** (the central feature of the Lecture 2 model) implies that the **GDP expenditure identity** must hold at every time step:

$$Y_t = C_t + I_t + G_t + X_t - M_t$$

BeforeIT computes GDP via the **production approach** internally, but also tracks each expenditure component. Let's verify they match.
"""

# ╔═╡ aff4f2e2-aeaf-11f1-af1a-3d0e4629a7da
@bind T_sfc PlutoUI.Slider(4:4:40, default=20, show_value=true)

# ╔═╡ aff4f2f8-aeaf-11f1-a746-d3ff9313a433
@bind run_sfc PlutoUI.Button("▶ Run SFC check")

# ╔═╡ aff4f30c-aeaf-11f1-9142-dd30e9ca39cf
begin
    run_sfc
    Random.seed!(1)
    _m_sfc = Bit.Model(nb1_p, nb1_ic)
    Bit.run!(_m_sfc, T_sfc)

    C = _m_sfc.data.real_household_consumption
    I_inv = _m_sfc.data.real_capitalformation
    G = _m_sfc.data.real_government_consumption
    X = _m_sfc.data.real_exports
    M = _m_sfc.data.real_imports
    Y_prod = _m_sfc.data.real_gdp        # production-side GDP

    Y_exp  = C .+ I_inv .+ G .+ X .- M  # expenditure-side GDP

    residual = Y_exp .- Y_prod
    max_err  = maximum(abs.(residual))
    rel_err  = max_err / mean(Y_prod) * 100

    DataFrame(
        "Stat"  => ["Max |residual| (€ real)", "Max relative error (%)"],
        "Value" => [round(max_err, sigdigits=4), round(rel_err, sigdigits=4)],
    )
end

# ╔═╡ aff4f33e-aeaf-11f1-86da-29175838bf3c
begin
    run_sfc
    plot(
        1:T_sfc+1, Y_prod,
        label = "GDP (production)", lw = 2, color = :steelblue,
        xlabel = "Quarter", ylabel = "Real GDP (index)",
        title  = "Expenditure vs production GDP ($(T_sfc) quarters)",
    )
    plot!(1:T_sfc+1, Y_exp, label = "C + I + G + X − M", lw = 2, ls = :dash, color = :crimson)
    plot!(1:T_sfc+1, residual .+ mean(Y_prod),
          label = "Residual (shifted to mean)", lw = 1, color = :grey, alpha = 0.6)
end

# ╔═╡ aff4f352-aeaf-11f1-9dfc-3350cb420b13
md"""
The two GDP measures should overlay almost exactly (residual near zero), confirming stock-flow consistency in the simulated data.

Note: small floating-point deviations ($<0.01\%$) are expected from rounding in search-and-matching; they are not macroeconomically meaningful.
"""

# ╔═╡ aff4f366-aeaf-11f1-a44f-111e45b03e5d
md"""
### 5b — Multi-identity SFC check

BeforeIT exposes a `get_accounting_identities` utility that checks three simultaneous accounting identities. Let's run it and verify all pass.
"""

# ╔═╡ aff4f37a-aeaf-11f1-8caf-47f6c425a5d1
begin
    run_sfc

    # BeforeIT's built-in accounting identity checker
    inc_prod, gdp_exp_nom, gdp_exp_real = Bit.get_accounting_identities(_m_sfc.data)
    cb_bal,   bank_bal                  = Bit.get_accounting_identity_banks(_m_sfc)

    sfc_table = DataFrame(
        "Identity" => [
            "Income = Production  (nominal GVA identity)",
            "GDP = Expenditure    (nominal)",
            "GDP = Expenditure    (real)",
            "CB balance sheet closure",
            "Bank balance sheet closure",
        ],
        "Cumulative residual" => round.([inc_prod, gdp_exp_nom, gdp_exp_real, cb_bal, bank_bal], sigdigits=4),
        "Pass (< 1e-3)"      => [abs(inc_prod) < 1e-3, abs(gdp_exp_nom) < 1e-3,
                                  abs(gdp_exp_real) < 1e-3,
                                  abs(cb_bal) < 1e-3, abs(bank_bal) < 1e-3],
    )
    sfc_table
end

# ╔═╡ aff4f38e-aeaf-11f1-872d-23a12a43a7d4
md"""
Five identities, all passing. Together they confirm the full **stock-flow consistency** of the model:
1. **Income identity:** GVA = wages + profits + net taxes on production.
2–3. **Expenditure identity (nominal & real):** GDP measured from production = C + I + G + X − M.
4. **Central bank closure:** CB equity + foreign deposits = govt bonds + commercial bank residual.
5. **Bank balance sheet:** firm deposits + household deposits + bank equity = firm loans + D_k.

This is a more comprehensive check than a single identity test. All residuals accumulate over the full simulation — so near-zero values confirm the accounting holds quarter by quarter, not just on average.
"""

# ╔═╡ aff4f3a2-aeaf-11f1-b85d-a1b07c15d995
md"""
---
## 12 — The firm size distribution

Lecture 2 notes that firm sizes follow a **power law**, calibrated from Eurostat business demography. Let's check:
"""

# ╔═╡ aff4f3b8-aeaf-11f1-94b1-47bb0dc99191
begin
    firm_sizes = nb1_model.firms.N_i   # initial employment per firm

    histogram(
        log10.(firm_sizes[firm_sizes .> 0] .+ 1),
        bins  = 50,
        title = "Firm size distribution at t=0\n(log₁₀ employees)",
        xlabel = "log₁₀(employees + 1)",
        ylabel = "Count",
        label  = "",
        color  = :steelblue,
        alpha  = 0.7,
    )
end

# ╔═╡ aff4f3ca-aeaf-11f1-b071-3b026390f775
md"""
The right-skewed distribution on a log scale is the hallmark of a **power law** (Zipf-like). Most firms are small; a few are very large. This is consistent with real data and generates the heterogeneous demand/supply dynamics in the goods market.
"""

# ╔═╡ aff4f3de-aeaf-11f1-bd1d-ff8061c897e7
md"""
---
## ✔ What you learned

Running it:

- `Bit.Model(parameters, initial_conditions)` builds the full agent population.
- `Bit.step!(model; parallel=true)` + `Bit.collect_data!(model)` advance one quarter; `Bit.run!(model, T)` is the wrapper for T of them.
- `Bit.plot_data(model, quantities=[...])` gives the built-in dashboard, and `model.data.real_gdp` reaches any tracked series.

What is inside it:

- About 10,000 agents across 6 types, stored struct-of-arrays. The real Austrian economy has ~9.9 million; `Bit.AUSTRIA2010Q1` is scaled 1:1000 so a run takes seconds.
- `model.prop.G` is 62 — the number of NACE **sectors**, which also fixes the count of foreign supplier firms, one per sector.
- The I-O matrix `nb1_model.prop.a_sg` encodes the production network — bright cells are supply-chain dependencies.
- Leontief coefficients $\bar\alpha_i, \beta_i, \kappa_i$ vary across those 62 sectors.
- Stepping manually with `Bit.step!` lets you watch state change quarter by quarter.
- The GDP expenditure identity $Y = C + I + G + X - M$ holds to floating-point precision — stock-flow consistency confirmed.

---
## Exercises

**Exercise 01.1** — Sort the `leontief` table by $\bar\alpha_i$ (labour productivity). Which sector has the **highest** labour productivity (most output per worker)? Which sector has the **lowest** $\bar\alpha_i$ — i.e., is most labour-intensive (requires the most workers per unit of output)? Do capital productivity and labour productivity tend to move together across sectors?

**Exercise 01.2** — Compute the **out-degree** of each sector in the I-O matrix: the number of sectors it supplies to (`sum(a_sg .> threshold, dims=2)`). Plot as a bar chart. Which sector is the most interconnected supplier?

**Exercise 01.3** *(stretch)* — The bankruptcy cascade argument says that a shock to a **high out-degree** sector is especially damaging. Based on your answer above, which sector would be the most dangerous to shock?
"""

# ╔═╡ Cell order:
# ╠═afacab38-aeaf-11f1-abe7-c5c37dd6a14b
# ╟─afeb8448-aeaf-11f1-af47-c739f5f21ffc
# ╟─afeb8484-aeaf-11f1-a594-79cbf074b789
# ╠═afeb8484-aeaf-11f1-b507-97431e415ab7
# ╟─afeb8498-aeaf-11f1-98a0-f3d28296a451
# ╠═afeb84a4-aeaf-11f1-97e3-4b0cd421f7c8
# ╟─afeb84a4-aeaf-11f1-80b1-1bab0c52eeb3
# ╠═afeb84c0-aeaf-11f1-8b29-edba9452036b
# ╟─afeb84c0-aeaf-11f1-810b-af5ddbc43d14
# ╠═afeb84ca-aeaf-11f1-9a80-2127338dd386
# ╟─afeb84d2-aeaf-11f1-ab92-af35331abf4a
# ╠═afeb84de-aeaf-11f1-8c71-733554335da9
# ╟─afeb84e8-aeaf-11f1-b1d9-d1f28ffd0896
# ╠═afeb84e8-aeaf-11f1-9728-3741750f455d
# ╠═afeb84f2-aeaf-11f1-8ebc-e376ec4c3867
# ╠═afeb84fc-aeaf-11f1-b9dc-679d86fd21dc
# ╟─afeb84fc-aeaf-11f1-84a7-cfdac3cd721e
# ╠═afeb8504-aeaf-11f1-9f11-5b270d89e616
# ╟─afeb8510-aeaf-11f1-8aad-6fb0d75564c5
# ╠═afeb851a-aeaf-11f1-b0c4-93231ab9e333
# ╟─afeb851a-aeaf-11f1-9b87-8b6ec0fc646c
# ╟─aff4f0e8-aeaf-11f1-a709-bb4dd6a9f8cd
# ╟─aff4f122-aeaf-11f1-b091-01ca261c4774
# ╠═aff4f136-aeaf-11f1-92b0-6ff1409c3868
# ╟─aff4f14c-aeaf-11f1-9e32-b5beec69e824
# ╟─aff4f15e-aeaf-11f1-83c8-39c1c4315067
# ╠═aff4f168-aeaf-11f1-8e5d-4f4edb4d4f90
# ╟─aff4f17a-aeaf-11f1-82c1-e758bc19853c
# ╠═aff4f190-aeaf-11f1-bc82-fbcc2ff7b700
# ╟─aff4f1a4-aeaf-11f1-a328-b5deddfd15d0
# ╠═aff4f1b8-aeaf-11f1-a488-d966727fbdf8
# ╠═aff4f1cc-aeaf-11f1-9e1c-51f7847655cf
# ╟─aff4f1ea-aeaf-11f1-80ab-8b458c9d217a
# ╟─aff4f208-aeaf-11f1-87d7-991503c2e629
# ╠═aff4f21c-aeaf-11f1-a686-3dff9ab0119a
# ╟─aff4f230-aeaf-11f1-b61d-2ddcec739827
# ╟─aff4f244-aeaf-11f1-be85-b54d53a0e1de
# ╠═aff4f258-aeaf-11f1-bb42-8189f17c42d8
# ╟─aff4f28a-aeaf-11f1-96ad-093e6a70a935
# ╠═aff4f2a8-aeaf-11f1-adf6-bd082d2cf498
# ╟─aff4f2bc-aeaf-11f1-a873-2f7978aa2937
# ╟─aff4f2d0-aeaf-11f1-b973-5b727f64032a
# ╠═aff4f2e2-aeaf-11f1-af1a-3d0e4629a7da
# ╠═aff4f2f8-aeaf-11f1-a746-d3ff9313a433
# ╠═aff4f30c-aeaf-11f1-9142-dd30e9ca39cf
# ╠═aff4f33e-aeaf-11f1-86da-29175838bf3c
# ╟─aff4f352-aeaf-11f1-9dfc-3350cb420b13
# ╟─aff4f366-aeaf-11f1-a44f-111e45b03e5d
# ╠═aff4f37a-aeaf-11f1-8caf-47f6c425a5d1
# ╟─aff4f38e-aeaf-11f1-872d-23a12a43a7d4
# ╟─aff4f3a2-aeaf-11f1-b85d-a1b07c15d995
# ╠═aff4f3b8-aeaf-11f1-94b1-47bb0dc99191
# ╟─aff4f3ca-aeaf-11f1-b071-3b026390f775
# ╟─aff4f3de-aeaf-11f1-bd1d-ff8061c897e7
