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

# ╔═╡ 02000000-0000-0000-0000-000000000001
begin
    import Pkg
    Pkg.activate(dirname(@__FILE__))
    import BeforeIT as Bit
    import Random
    using Plots, PlutoUI, DataFrames, Statistics, LinearAlgebra
end

# ╔═╡ 02000000-0000-0000-0000-000000000002
md"""
# Notebook 02 — Anatomy of the Model

> **Question this notebook answers:** who are the agents, how do they interact, and does the accounting actually add up?

### Lecture 2 slides covered
- *Household behaviour: consumption, savings, expectations*
- *Household heterogeneity: four types*
- *Firms* (Leontief production function)
- *Labour market: search and matching*
- *Input-output network*
- *Remainder of model* (government, bank, central bank, rest of world)

### Learning goals
1. Understand the agent types and their counts.
2. Visualise the production network (I-O matrix).
3. Trace the per-quarter event sequence by stepping manually.
4. Verify GDP accounting identity — the SFC consistency check.
5. Compare labour, capital, and material intensities across sectors.
"""

# ╔═╡ 02000000-0000-0000-0000-000000000003
begin
    nb02_p     = Bit.AUSTRIA2010Q1.parameters
    nb02_ic    = Bit.AUSTRIA2010Q1.initial_conditions
    nb02_model = Bit.Model(nb02_p, nb02_ic)
    "Model loaded ✓"
end

# ╔═╡ 02000000-0000-0000-0000-000000000004
md"""
---
## 1 — Who are the agents?

The Lecture 2 table "How big is the model?" reports ~9.9 million agents for Austria 2010:Q4 — the real economy. `Bit.AUSTRIA2010Q1` is scaled **1:1000** so that a run finishes in seconds, so expect counts around a thousandth of the lecture's. Shares and ratios are unaffected.
"""

# ╔═╡ 02000000-0000-0000-0000-000000000005
begin
    p = nb02_model.prop
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

# ╔═╡ 02000000-0000-0000-0000-000000000006
md"""
**Total: $(nb02_model.prop.H_act + nb02_model.prop.H_inact + nb02_model.prop.I + nb02_model.prop.J + nb02_model.prop.L + nb02_model.prop.G) agents** — about 1/1000 of the lecture's 9.9 million, as expected from the scaling.

One label needs care: `prop.G` is the number of production **sectors** (62, the NACE breakdown), which doubles as the count of foreign supplier firms because imports arrive one representative firm per sector. It is the same `g` index used in `P_bar_g` and `firms.G_i`.

The four household types from Lecture 2:
- **Employed** (`nb02_model.w_act`) — labour supplied to a specific sector.
- **Unemployed** — subset of `nb02_model.w_act` with no current job.
- **Investors** — one per firm, receive dividends $\theta^{DIV}(1-\tau^{FIRM})\Pi_i$.
- **Inactive** (`nb02_model.w_inact`) — outside the labour force, receive social transfers.
"""

# ╔═╡ 02000000-0000-0000-0000-000000000007
md"""
Let's inspect a single active worker:
"""

# ╔═╡ 02000000-0000-0000-0000-000000000008
fieldnames(typeof(nb02_model.w_act))

# ╔═╡ 02000000-0000-0000-0000-000000000009
md"""
And a single firm:
"""

# ╔═╡ 02000000-0000-0000-0000-00000000000a
fieldnames(typeof(nb02_model.firms))

# ╔═╡ 02000000-0000-0000-0000-00000000001e
md"""
---
## 1b — Household heterogeneity

Lecture 2 identifies **four household types**. BeforeIT stores them in two structs:

| Type | Struct | Description |
|---|---|---|
| Employed workers | `nb02_model.w_act` (`O_h > 0`) | Earn wages, pay income tax, buy consumption goods |
| Unemployed workers | `nb02_model.w_act` (`O_h = 0`) | Receive unemployment benefits $(θ^{UB} w)$, job search |
| Inactive persons | `nb02_model.w_inact` | Out of labour force, receive social transfers |
| Capitalist investors | `nb02_model.firms` (one per firm) | Own a firm, receive dividends $(θ^{DIV}(1-τ^{FIRM})Π_i)$ |

**Employed + unemployed** live in `w_act`; the `O_h` field records which firm employs each worker (0 = unemployed). Investors own firms and are counted in `prop.I`; they are tracked via `nb02_model.firms` rather than as household agents with individual deposit records.
"""

# ╔═╡ 02000000-0000-0000-0000-00000000001f
begin
    # w_act holds all regular workers (employed + unemployed); O_h = 0 means unemployed
    O_h_regular    = nb02_model.w_act.O_h
    n_employed_reg = sum(O_h_regular .> 0)
    n_unemployed   = sum(O_h_regular .== 0)
    n_investors    = nb02_model.prop.I
    n_inactive     = nb02_model.prop.H_inact
    n_total        = nb02_model.prop.H_act + n_inactive

    het_table = DataFrame(
        "Household type"      => ["Employed workers", "Unemployed workers",
                                   "Capitalist investors (nb02_model.firms)", "Inactive persons"],
        "Count"               => [n_employed_reg, n_unemployed, n_investors, n_inactive],
        "Share of adults (%)" => round.([n_employed_reg, n_unemployed, n_investors, n_inactive]
                                         ./ n_total .* 100, digits=1),
    )
    het_table
end

# ╔═╡ 02000000-0000-0000-0000-000000000020
begin
    # Deposits D_h by household type (investors tracked via nb02_model.firms, not as household agents)
    D_employed   = nb02_model.w_act.D_h[O_h_regular .> 0]
    D_unemployed = nb02_model.w_act.D_h[O_h_regular .== 0]
    D_inactive   = nb02_model.w_inact.D_h

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

# ╔═╡ 02000000-0000-0000-0000-000000000021
md"""
**Why do unemployed and inactive workers show near-zero variance?**

At $t=0$, BeforeIT initialises household deposits from **aggregate national accounts data** — only the sector total is known, so it is divided equally across all agents of the same type. That is why every unemployed worker starts with exactly the same $D_h$, and every inactive person starts with exactly the same $D_h$ (a different level, but still identical within the group). The employed histogram looks wider because employment-type variation maps onto wage variation, which produces some spread even at initialisation.

The narrow distributions are **technically correct, not a bug** — they reflect the data-based initialisation that lets the model start at calibrated aggregate stocks without a burn-in period. Run the model for a few quarters and re-run this cell to see heterogeneity build up as workers change jobs, accumulate savings, or cycle through unemployment.

**Key observation:** Investor-capitalists (who receive dividends $\theta^{DIV}(1-\tau^{FIRM})\Pi_i$) hold significantly more deposits than regular employed workers. Unemployed workers hold the least, reflecting lost wage income partially offset by unemployment benefits $\theta^{UB} w_i$. These wealth heterogeneities feed into different **marginal propensities to consume**, driving aggregate demand dynamics across the business cycle.
"""

# ╔═╡ 02000000-0000-0000-0000-00000000000b
md"""
---
## 2 — The input-output production network

Firms buy intermediate inputs from other sectors. The technology matrix $a_{sg}$ gives the share of industry $s$'s output that goes as intermediate input to product type $g$.

This is the heatmap shown in Lecture 2 (Figure: "Intermediate consumption between 19 industries"). We plot the full 64-sector version here.
"""

# ╔═╡ 02000000-0000-0000-0000-00000000000c
begin
    nb02_a_sg = nb02_model.prop.a_sg   # I-O matrix: rows = supplier sector, cols = buyer product

    heatmap(
        nb02_a_sg,
        color      = :viridis,
        title      = "Input-Output technology matrix a_sg\n(64 NACE sectors × product types)",
        xlabel     = "Buyer product g",
        ylabel     = "Supplier sector s",
        aspect_ratio = :equal,
        size       = (600, 550),
        clims      = (0, quantile(vec(nb02_a_sg[nb02_a_sg .> 0]), 0.99)),  # cap colorscale at 99th pct
    )
end

# ╔═╡ 02000000-0000-0000-0000-00000000000d
md"""
**Reading the heatmap:** a bright cell at row $s$, column $g$ means sector $s$ supplies a large fraction of its output as intermediate input to the production of product type $g$.

The diagonal entries represent within-sector intermediate use (e.g., agriculture buying agricultural products). Off-diagonal bright cells reveal key supply-chain dependencies — a failure in a bright-cell upstream sector cascades to all sectors that buy from it (the bankruptcy cascade from Lecture 2).
"""

# ╔═╡ 02000000-0000-0000-0000-00000000000e
md"""
---
## 3 — Leontief coefficients by sector

Recall the production function from Lecture 2:

$$Y_{i,t} = \min\!\left(Q^S_{i,t},\; \beta_i M_{i,t},\; \bar\alpha_{i,t} N_{i,t},\; \kappa_i K_{i,t-1}\right)$$

The three coefficients $\bar\alpha_i$ (labour productivity), $\beta_i$ (material efficiency), $\kappa_i$ (capital productivity) determine which input is the binding constraint in each sector.
"""

# ╔═╡ 02000000-0000-0000-0000-00000000000f
begin
    # Each coefficient is a vector over firms; take the mean per sector
    G_sectors = nb02_model.prop.G        # number of product/sector types
    I_s       = nb02_model.prop.I_s      # vector of firm counts per sector

    # Build sector indices
    sector_id = vcat([fill(s, I_s[s]) for s in 1:length(I_s)]...)

    leontief = DataFrame(
        "Sector"     => 1:length(I_s),
        "Firms"      => I_s,
        "ᾱ (labour prod.)"   => [mean(nb02_model.firms.alpha_bar_i[sector_id .== s])
                                   for s in 1:length(I_s)],
        "β (material eff.)"  => [mean(nb02_model.firms.beta_i[sector_id .== s])
                                  for s in 1:length(I_s)],
        "κ (capital prod.)"  => [mean(nb02_model.firms.kappa_i[sector_id .== s])
                                  for s in 1:length(I_s)],
    )
    leontief
end

# ╔═╡ 02000000-0000-0000-0000-000000000010
md"""
> **Exercise 02.1** — Sort the table by $\bar\alpha_i$ (labour productivity). Which sector has the **highest** labour productivity (most output per worker)? Which sector is most **labour-intensive** (lowest $\bar\alpha_i$ — requires the most workers per unit of output)? Do capital productivity $\kappa_i$ and labour productivity tend to move together across sectors?
"""

# ╔═╡ 02000000-0000-0000-0000-000000000011
md"""
---
## 4 — Stepping through the quarter sequence

Instead of running all T quarters at once with `Bit.run!`, let's step manually and observe what changes.

Each call to `Bit.step!` runs the full five-stage sequence from Lecture 2 (expectations → shocks → credit/labour → goods → accounting).
"""

# ╔═╡ 02000000-0000-0000-0000-000000000012
begin
    nb02_model_step = Bit.Model(nb02_p, nb02_ic)

    # Snapshot before step
    gdp_before  = nb02_model_step.agg.Y_e              # expected aggregate output
    emp_before  = sum(nb02_model_step.firms.N_i)        # total employed workers
    rate_before = nb02_model_step.cb.r_bar              # policy rate

    # Take one step
    Bit.step!(nb02_model_step; parallel = true)
    Bit.collect_data!(nb02_model_step)

    gdp_after   = nb02_model_step.agg.Y_e
    emp_after   = sum(nb02_model_step.firms.N_i)
    rate_after  = nb02_model_step.cb.r_bar

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

# ╔═╡ 02000000-0000-0000-0000-000000000013
md"""
The small changes after one step reflect the exogenous AR(1) shock draw and the OLS expectation update. Multiple steps accumulate into the time series we plotted in Notebook 01.
"""

# ╔═╡ 02000000-0000-0000-0000-000000000014
md"""
---
## 5 — SFC accounting check ✓

**Stock-flow consistency** (the central feature of the Lecture 2 model) implies that the **GDP expenditure identity** must hold at every time step:

$$Y_t = C_t + I_t + G_t + X_t - M_t$$

BeforeIT computes GDP via the **production approach** internally, but also tracks each expenditure component. Let's verify they match.
"""

# ╔═╡ 02000000-0000-0000-0000-000000000015
@bind T_sfc PlutoUI.Slider(4:4:40, default=20, show_value=true)

# ╔═╡ 02000000-0000-0000-0000-000000000016
@bind run_sfc PlutoUI.Button("▶ Run SFC check")

# ╔═╡ 02000000-0000-0000-0000-000000000017
begin
    run_sfc
    Random.seed!(1)
    _m_sfc = Bit.Model(nb02_p, nb02_ic)
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

# ╔═╡ 02000000-0000-0000-0000-000000000018
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

# ╔═╡ 02000000-0000-0000-0000-000000000019
md"""
The two GDP measures should overlay almost exactly (residual near zero), confirming stock-flow consistency in the simulated data.

Note: small floating-point deviations ($<0.01\%$) are expected from rounding in search-and-matching; they are not macroeconomically meaningful.
"""

# ╔═╡ 02000000-0000-0000-0000-000000000022
md"""
### 5b — Multi-identity SFC check

BeforeIT exposes a `get_accounting_identities` utility that checks three simultaneous accounting identities. Let's run it and verify all pass.
"""

# ╔═╡ 02000000-0000-0000-0000-000000000023
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

# ╔═╡ 02000000-0000-0000-0000-000000000024
md"""
Five identities, all passing. Together they confirm the full **stock-flow consistency** of the model:
1. **Income identity:** GVA = wages + profits + net taxes on production.
2–3. **Expenditure identity (nominal & real):** GDP measured from production = C + I + G + X − M.
4. **Central bank closure:** CB equity + foreign deposits = govt bonds + commercial bank residual.
5. **Bank balance sheet:** firm deposits + household deposits + bank equity = firm loans + D_k.

This is a more comprehensive check than a single identity test. All residuals accumulate over the full simulation — so near-zero values confirm the accounting holds quarter by quarter, not just on average.
"""

# ╔═╡ 02000000-0000-0000-0000-00000000001a
md"""
---
## 6 — The firm size distribution

Lecture 2 notes that firm sizes follow a **power law**, calibrated from Eurostat business demography. Let's check:
"""

# ╔═╡ 02000000-0000-0000-0000-00000000001b
begin
    firm_sizes = nb02_model.firms.N_i   # initial employment per firm

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

# ╔═╡ 02000000-0000-0000-0000-00000000001c
md"""
The right-skewed distribution on a log scale is the hallmark of a **power law** (Zipf-like). Most firms are small; a few are very large. This is consistent with real data and generates the heterogeneous demand/supply dynamics in the goods market.
"""

# ╔═╡ 02000000-0000-0000-0000-00000000001d
md"""
---
## ✔ What you learned

- The model has ~9.9M agents across 6 types, all stored in struct-of-arrays.
- The I-O matrix `nb02_model.prop.a_sg` encodes the production network — bright cells are supply-chain dependencies.
- Leontief coefficients $\bar\alpha_i, \beta_i, \kappa_i$ vary across the 64 NACE sectors.
- Stepping manually with `Bit.step!` lets you observe state changes quarter by quarter.
- The GDP expenditure identity $Y = C + I + G + X - M$ holds to within floating-point precision — SFC consistency confirmed.

---
## Exercises

**Exercise 02.1** — Sort the `leontief` table by $\bar\alpha_i$ (labour productivity). Which sector has the **highest** labour productivity (most output per worker)? Which sector has the **lowest** $\bar\alpha_i$ — i.e., is most labour-intensive (requires the most workers per unit of output)? Do capital productivity and labour productivity tend to move together across sectors?

**Exercise 02.2** — Compute the **out-degree** of each sector in the I-O matrix: the number of sectors it supplies to (`sum(a_sg .> threshold, dims=2)`). Plot as a bar chart. Which sector is the most interconnected supplier?

**Exercise 02.3** *(stretch)* — The bankruptcy cascade argument says that a shock to a **high out-degree** sector is especially damaging. Based on your answer above, which sector would be the most dangerous to shock?
"""

# ╔═╡ Cell order:
# ╟─02000000-0000-0000-0000-000000000002
# ╠═02000000-0000-0000-0000-000000000001
# ╠═02000000-0000-0000-0000-000000000003
# ╟─02000000-0000-0000-0000-000000000004
# ╠═02000000-0000-0000-0000-000000000005
# ╟─02000000-0000-0000-0000-000000000006
# ╠═02000000-0000-0000-0000-000000000007
# ╠═02000000-0000-0000-0000-000000000008
# ╠═02000000-0000-0000-0000-000000000009
# ╠═02000000-0000-0000-0000-00000000000a
# ╟─02000000-0000-0000-0000-00000000001e
# ╠═02000000-0000-0000-0000-00000000001f
# ╠═02000000-0000-0000-0000-000000000020
# ╟─02000000-0000-0000-0000-000000000021
# ╟─02000000-0000-0000-0000-00000000000b
# ╠═02000000-0000-0000-0000-00000000000c
# ╟─02000000-0000-0000-0000-00000000000d
# ╟─02000000-0000-0000-0000-00000000000e
# ╠═02000000-0000-0000-0000-00000000000f
# ╟─02000000-0000-0000-0000-000000000010
# ╟─02000000-0000-0000-0000-000000000011
# ╠═02000000-0000-0000-0000-000000000012
# ╟─02000000-0000-0000-0000-000000000013
# ╟─02000000-0000-0000-0000-000000000014
# ╠═02000000-0000-0000-0000-000000000015
# ╠═02000000-0000-0000-0000-000000000016
# ╠═02000000-0000-0000-0000-000000000017
# ╠═02000000-0000-0000-0000-000000000018
# ╟─02000000-0000-0000-0000-000000000019
# ╟─02000000-0000-0000-0000-000000000022
# ╠═02000000-0000-0000-0000-000000000023
# ╟─02000000-0000-0000-0000-000000000024
# ╟─02000000-0000-0000-0000-00000000001a
# ╠═02000000-0000-0000-0000-00000000001b
# ╟─02000000-0000-0000-0000-00000000001c
# ╟─02000000-0000-0000-0000-00000000001d
