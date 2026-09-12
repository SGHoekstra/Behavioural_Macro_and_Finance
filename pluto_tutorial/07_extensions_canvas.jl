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

# ╔═╡ 07000000-0000-0000-0000-000000000001
begin
    import Pkg
    Pkg.activate(dirname(@__FILE__))
    import BeforeIT as Bit
    import Random
    using Plots, PlutoUI, Statistics, StatsPlots
end

# ╔═╡ 07000000-0000-0000-0000-000000000002
md"""
# Notebook 07 — Extending the Model: CANVAS Wage–Price Spiral *(Advanced)*

> **Question this notebook answers:** how does a 10% permanent wage shock propagate into persistent inflation — and does it matter whether firms have full or partial price pass-through?

### Lecture 2 slides covered
- *Pricing mechanism* (CANVAS)
- *Demand pull mechanisms*
- *CANVAS pricing mechanism implicit assumptions*
- *Sectoral inflation decomposition: wage shock, non-estimated ABM*
- *Sectoral inflation decomposition: wage shock, estimated ABM*

### Learning goals
1. Understand BeforeIT's extension architecture (Julia multiple dispatch on model types).
2. Implement the CANVAS demand-pull pricing rule as a model extension.
3. Use sliders to vary pass-through coefficients and observe effects on inflation.
4. Reproduce the qualitative pattern from the Lecture 2 inflation decomposition figures.
"""

# ╔═╡ 07000000-0000-0000-0000-000000000003
md"""
---
## 1 — BeforeIT's extension architecture

BeforeIT uses Julia's **multiple dispatch** system to allow clean model extensions. The pattern is:

1. Create a new model type inheriting from `Bit.AbstractModel`.
2. Define new method(s) for the function you want to override, specialised on your new type.
3. Julia automatically calls your method when the model is of your type.

This is the "open/closed principle" in action: you extend behaviour without modifying the original source code.

```julia
# Step 1: new model type
Bit.@object mutable struct MyModel(Bit.Model) <: Bit.AbstractModel end

# Step 2: override a single function
function Bit.firms_expectations_and_decisions(model::MyModel)
    # your implementation here ...
end

# Step 3: instantiate with your type
model = MyModel(w_act, w_inact, firms, bank, cb, gov, rotw, agg, prop, data)
Bit.step!(model)   # automatically calls your overridden function
```
"""

# ╔═╡ 07000000-0000-0000-0000-000000000004
md"""
---
## 2 — The CANVAS pricing equation

Recall from Lecture 2 slide *"CANVAS pricing mechanism implicit assumptions"*:

$$P_i(t) = P_i(t-1) \cdot \underbrace{(1+\phi^{DP}\pi^d_i(t))}_{\text{demand-pull}} \cdot \underbrace{(1+\phi^{CP}\pi^c_i(t))}_{\text{cost-push}} \cdot \underbrace{(1+\phi^{AE}\pi^e(t))}_{\text{aggregate expectations}}$$

where $\pi^d_i$ comes from firm-level inventory/price positioning across four scenarios:

| Supply vs Demand | Price vs sector avg | Action |
|---|---|---|
| Excess demand | Below average | Raise price ($\pi^d_i > 0$) |
| Excess demand | Above average | Expand production ($\gamma^d_i > 0$) |
| Excess supply | Above average | Cut price ($\pi^d_i < 0$) |
| Excess supply | Below average | Cut production ($\gamma^d_i < 0$) |

Setting **$\phi^{DP} = \phi^{CP} = \phi^{AE} = 1$** gives full, immediate pass-through. With $\phi < 1$ firms absorb part of the shock — inflation is dampened but more persistent.
"""

# ╔═╡ 07000000-0000-0000-0000-00000000000e
md"""
### CANVAS implicit assumptions

The four-scenario table encodes two pieces of **local information** available to every firm each quarter:

1. **Inventory signal** — does realised demand $Q^d_i$ exceed or fall short of planned supply $Q^s_i$?
2. **Price signal** — is the firm's price $P_i$ above or below the sector-average price $\bar{P}_g$?

These combine into four quadrants:

| Demand signal | Price signal | Action | Motive |
|---|---|---|---|
| Excess demand $(Q^d > Q^s)$ | Cheap $(P_i < \bar P_g)$ | **Raise price** | Room to pass costs through without losing customers |
| Excess demand | Expensive $(P_i \geq \bar P_g)$ | **Expand output** | Customers buy despite high price → increase volume |
| Excess supply $(Q^d \leq Q^s)$ | Expensive | **Cut price** | Too expensive → attract buyers by discounting |
| Excess supply | Cheap | **Cut output** | Even at low prices, demand is absent → reduce waste |

This is a **bounded-rational approximation** to optimal price-setting. The key *implicit assumption*: firms need only *local* information — their own inventory and their own price relative to a sector average. No utility maximisation, no rational expectations.

Setting $\phi^{DP} = 1$ gives full, immediate demand-pull pass-through. The Lecture 2 "estimated" CANVAS model finds $\phi^{DP} < 1$ because real firms exhibit **price stickiness** — they don't fully exploit their demand-pull margin each period.
"""

# ╔═╡ 07000000-0000-0000-0000-000000000005
md"""
---
## 3 — Implementing the CANVAS extension
"""

# ╔═╡ 07000000-0000-0000-0000-000000000006
begin
    Bit.@object mutable struct CANVASModel(Bit.Model) <: Bit.AbstractModel end

    # Pass-through coefficients — updated by the sliders below before each run
    const CANVAS_phi = Ref((dp=1.0, cp=1.0, ae=1.0))

    function Bit.firms_expectations_and_decisions(model::CANVASModel)
        firms   = model.firms
        P_bar_g = model.agg.P_bar_g
        gamma_e = model.agg.gamma_e
        pi_e    = model.agg.pi_e
        ϕ       = CANVAS_phi[]

        I = length(firms.G_i)
        gamma_d_i = zeros(I)
        pi_d_i    = zeros(I)

        for i in 1:I
            if firms.Q_s_i[i] <= firms.Q_d_i[i] && firms.P_i[i] >= P_bar_g[firms.G_i[i]]
                gamma_d_i[i] = firms.Q_d_i[i] / firms.Q_s_i[i] - 1   # expand production
            elseif firms.Q_s_i[i] <= firms.Q_d_i[i] && firms.P_i[i] < P_bar_g[firms.G_i[i]]
                pi_d_i[i]    = firms.Q_d_i[i] / firms.Q_s_i[i] - 1   # raise price
            elseif firms.Q_s_i[i] > firms.Q_d_i[i] && firms.P_i[i] >= P_bar_g[firms.G_i[i]]
                pi_d_i[i]    = firms.Q_d_i[i] / firms.Q_s_i[i] - 1   # cut price
            else
                gamma_d_i[i] = firms.Q_d_i[i] / firms.Q_s_i[i] - 1   # cut production
            end
        end

        Q_s_i  = firms.Q_s_i .* (1 .+ gamma_e) .* (1 .+ gamma_d_i)
        pi_c_i = Bit.cost_push_inflation(firms, model)

        new_P_i = firms.P_i .*
                  (1 .+ ϕ.cp .* pi_c_i) .*
                  (1 .+ ϕ.ae * pi_e)    .*
                  (1 .+ ϕ.dp .* pi_d_i)

        I_d_i, DM_d_i, N_d_i = Bit.desired_capital_material_employment(firms, Q_s_i)
        Pi_e_i                = firms.Pi_i .* (1 + pi_e) * (1 + gamma_e)
        DD_e_i, K_e_i, L_e_i = Bit.expected_deposits_capital_loans(firms, model, Pi_e_i)
        DL_d_i                = max.(0, -DD_e_i .- firms.D_i)

        return Q_s_i, I_d_i, DM_d_i, N_d_i, Pi_e_i, DL_d_i, K_e_i, L_e_i, new_P_i
    end

    "CANVASModel and pricing function defined ✓"
end

# ╔═╡ 07000000-0000-0000-0000-000000000007
md"""
---
## 4 — Interactive pass-through experiment

Use the sliders to set pass-through coefficients, then apply a **10% permanent wage shock**. Compare cumulative excess inflation and GDP impact under the Poledna baseline vs CANVAS.
"""

# ╔═╡ 07000000-0000-0000-0000-000000000008
md"""
**Demand-pull pass-through $\phi^{DP}$:** $(@bind phi_dp PlutoUI.Slider(0.0:0.1:1.0, default=1.0, show_value=true))

**Cost-push pass-through $\phi^{CP}$:** $(@bind phi_cp PlutoUI.Slider(0.0:0.1:1.0, default=1.0, show_value=true))

**Aggregate expectations pass-through $\phi^{AE}$:** $(@bind phi_ae PlutoUI.Slider(0.0:0.1:1.0, default=1.0, show_value=true))
"""

# ╔═╡ 07000000-0000-0000-0000-000000000009
@bind run_canvas PlutoUI.Button("▶ Run CANVAS comparison (16 quarters)")

# ╔═╡ 07000000-0000-0000-0000-000000000012
# Standalone cell for the Nb07WageShock struct.
# Struct types cannot be redefined in Julia; placing this outside the
# button-triggered cell ensures it compiles exactly once at notebook load.
begin
    struct Nb07WageShock; mult::Float64 end
    function (s::Nb07WageShock)(model)
        model.agg.t == 1 && (model.firms.w_i .*= s.mult)
    end
end

# ╔═╡ 07000000-0000-0000-0000-00000000000a
begin
    run_canvas

    nb07_p  = Bit.AUSTRIA2010Q1.parameters
    nb07_ic = Bit.AUSTRIA2010Q1.initial_conditions

    wage_shock = Nb07WageShock(1.10)

    Random.seed!(7)
    ens_poledna_base  = Bit.ensemblerun(Bit.Model(nb07_p, nb07_ic), 16, 10)
    Random.seed!(7)
    ens_poledna_shock = Bit.ensemblerun(Bit.Model(nb07_p, nb07_ic), 16, 10; shock! = wage_shock)

    CANVAS_phi[] = (dp = phi_dp, cp = phi_cp, ae = phi_ae)

    function build_canvas(p, ic)
        w_act, w_inact = Bit.Workers(p, ic)
        firms  = Bit.Firms(p, ic);  bank = Bit.Bank(p, ic)
        cb     = Bit.CentralBank(p, ic); gov = Bit.Government(p, ic)
        rotw   = Bit.RestOfTheWorld(p, ic); agg = Bit.Aggregates(p, ic)
        prop   = Bit.Properties(p, ic);    data = Bit.Data()
        m = CANVASModel(w_act, w_inact, firms, bank, cb, gov, rotw, agg, prop, data)
        # Initialise Q_s_i from Y_i so the demand-pull ratios are well-defined at t=1
        m.firms.Q_s_i .= m.firms.Y_i
        return m
    end

    Random.seed!(7)
    ens_canvas_base  = Bit.ensemblerun(build_canvas(nb07_p, nb07_ic), 16, 10)
    Random.seed!(7)
    ens_canvas_shock = Bit.ensemblerun(build_canvas(nb07_p, nb07_ic), 16, 10; shock! = wage_shock)

    "CANVAS run complete ✓"
end

# ╔═╡ 07000000-0000-0000-0000-00000000000b
begin
    run_canvas

    # Stack one field from all ensemble runs into a T × N_runs matrix
    ens_field(ens, field) = hcat([getfield(m.data, field) for m in ens]...)
    nb07_defl(ens) = ens_field(ens, :nominal_gdp) ./ ens_field(ens, :real_gdp)
    nb07_infl(d)   = diff(d, dims=1) ./ selectdim(d, 1, 1:(size(d, 1)-1))

    infl_poledna_base  = nb07_infl(nb07_defl(ens_poledna_base))
    infl_poledna_shock = nb07_infl(nb07_defl(ens_poledna_shock))
    infl_canvas_base   = nb07_infl(nb07_defl(ens_canvas_base))
    infl_canvas_shock  = nb07_infl(nb07_defl(ens_canvas_shock))

    excess_poledna = infl_poledna_shock .- infl_poledna_base
    excess_canvas  = infl_canvas_shock  .- infl_canvas_base

    p1 = errorline(
        cumsum(excess_poledna, dims=1) .* 100, label = "Poledna (no demand-pull)",
        lw = 2, color = :steelblue,
        title = "Cumulative excess inflation\nafter 10% wage shock",
        xlabel = "Quarter", ylabel = "% above baseline",
    )
    errorline!(p1, cumsum(excess_canvas, dims=1) .* 100,
          label = "CANVAS (ϕDP=$(phi_dp), ϕCP=$(phi_cp), ϕAE=$(phi_ae))",
          lw = 2, color = :tomato, ls = :dash)
    hline!(p1, [0], color = :black, lw = 1, label = "")

    p2 = errorline(
        ens_field(ens_poledna_shock, :real_gdp) ./ ens_field(ens_poledna_base, :real_gdp) .- 1,
        label = "Poledna", lw = 2, color = :steelblue,
        title = "Real GDP: shock vs baseline",
        xlabel = "Quarter", ylabel = "Δ fraction",
    )
    errorline!(p2, ens_field(ens_canvas_shock, :real_gdp) ./ ens_field(ens_canvas_base, :real_gdp) .- 1,
          label = "CANVAS", lw = 2, color = :tomato, ls = :dash)
    hline!(p2, [0], color = :black, lw = 1, label = "")

    plot(p1, p2, layout = (1, 2), size = (800, 380), legend = :topright)
end

# ╔═╡ 07000000-0000-0000-0000-00000000000f
md"""
---
## 5 — Channel decomposition

The CANVAS pricing equation has three **multiplicative** channels. We can isolate each by running CANVAS with only one $\phi = 1$ (the other two set to zero), then compare excess inflation.

> **Note on multiplicativity:** Because channels multiply rather than add, the three isolated contributions do not sum exactly to the full-pass-through result. The gap is the channel **interaction term** — a second-order effect. This illustrates why pass-through estimates from single-equation regressions may be biased.
"""

# ╔═╡ 07000000-0000-0000-0000-000000000010
@bind run_decomp PlutoUI.Button("▶ Run decomposition (3 × 2 isolated runs, ~30 s)")

# ╔═╡ 07000000-0000-0000-0000-000000000011
begin
    run_decomp

    function run_isolated_pair(phi_val)
        CANVAS_phi[] = phi_val
        Random.seed!(7)
        ens_b = Bit.ensemblerun(build_canvas(nb07_p, nb07_ic), 16, 10)
        Random.seed!(7)
        ens_s = Bit.ensemblerun(build_canvas(nb07_p, nb07_ic), 16, 10; shock! = wage_shock)
        CANVAS_phi[] = (dp=phi_dp, cp=phi_cp, ae=phi_ae)
        return ens_b, ens_s
    end

    _ens_b_dp, _ens_s_dp = run_isolated_pair((dp=1.0, cp=0.0, ae=0.0))
    _ens_b_cp, _ens_s_cp = run_isolated_pair((dp=0.0, cp=1.0, ae=0.0))
    _ens_b_ae, _ens_s_ae = run_isolated_pair((dp=0.0, cp=0.0, ae=1.0))

    function _excess_infl(ens_s, ens_b)
        cumsum(nb07_infl(nb07_defl(ens_s)) .- nb07_infl(nb07_defl(ens_b)), dims=1) .* 100
    end

    ei_dp_iso = _excess_infl(_ens_s_dp, _ens_b_dp)
    ei_cp_iso = _excess_infl(_ens_s_cp, _ens_b_cp)
    ei_ae_iso = _excess_infl(_ens_s_ae, _ens_b_ae)
    ei_interact = cumsum(excess_canvas, dims=1) .* 100 .- ei_dp_iso .- ei_cp_iso .- ei_ae_iso

    qs = 1:15
    p_decomp = errorline(qs, ei_dp_iso[qs, :],   lw=2, color=:tomato,   ls=:dash, label="Demand-pull only")
    errorline!(p_decomp, qs, ei_cp_iso[qs, :],   lw=2, color=:steelblue, ls=:dash, label="Cost-push only")
    errorline!(p_decomp, qs, ei_ae_iso[qs, :],   lw=2, color=:goldenrod,  ls=:dash, label="Expectations only")
    errorline!(p_decomp, qs, ei_interact[qs, :], lw=1, color=:grey,       ls=:dot,  label="Interaction term")
    errorline!(p_decomp, qs, cumsum(excess_canvas, dims=1)[qs, :] .* 100,
          lw=3, color=:black, label="Full CANVAS (all channels)")
    hline!(p_decomp, [0], lw=1, color=:grey, label="")
    plot!(p_decomp,
          title  = "Inflation channel decomposition\n(10% wage shock, ϕ=1 for active channel, others=0)",
          xlabel = "Quarter", ylabel = "Cumulative excess inflation (%)",
          legend = :topleft, size = (720, 380))
end

# ╔═╡ 07000000-0000-0000-0000-00000000000c
md"""
**Interpretation:**
- With $\phi = 1$ (full pass-through), the 10% wage shock feeds immediately and fully into prices via all three channels.
- With $\phi < 1$ (partial pass-through), inflation is dampened but more persistent — firms absorb part of the shock each period and pass it through gradually.
- The Lecture 2 figures show the **estimated** CANVAS model (via SBI in Notebook 08) typically has $\phi^{CP} < 1$ — firms absorb costs to some degree.
"""

# ╔═╡ 07000000-0000-0000-0000-00000000000d
md"""
---
## ✔ What you learned

- BeforeIT extensions use `Bit.@object mutable struct` + Julia multiple dispatch — no forking of source code.
- `Bit.firms_expectations_and_decisions` is the pricing hook: override it to change how firms set prices.
- The CANVAS demand-pull mechanism adds firm-level inventory/price positioning (four scenarios) on top of cost-push and expectations.
- Pass-through coefficients $\phi^{DP}, \phi^{CP}, \phi^{AE}$ control how much of each inflation component reaches the price level.
- The upstream `examples/CANVAS_extension.jl` also overrides the Taylor rule to use adaptive learning — this notebook shows the pricing extension only.

---
## Exercises

**Exercise 07.1** — Set $\phi^{CP} = 0$ (no cost-push pass-through). Does the wage shock produce any inflation at all? Explain the mechanism.

**Exercise 07.2** — Run with $\phi^{AE} = 0$ (no aggregate expectations pass-through). Compare cumulative inflation after 16 quarters to the full-pass-through case. How important are expectations in generating inflation persistence?
"""

# ╔═╡ Cell order:
# ╟─07000000-0000-0000-0000-000000000002
# ╠═07000000-0000-0000-0000-000000000001
# ╟─07000000-0000-0000-0000-000000000003
# ╟─07000000-0000-0000-0000-000000000004
# ╟─07000000-0000-0000-0000-00000000000e
# ╟─07000000-0000-0000-0000-000000000005
# ╠═07000000-0000-0000-0000-000000000006
# ╟─07000000-0000-0000-0000-000000000007
# ╠═07000000-0000-0000-0000-000000000008
# ╠═07000000-0000-0000-0000-000000000009
# ╠═07000000-0000-0000-0000-000000000012
# ╠═07000000-0000-0000-0000-00000000000a
# ╠═07000000-0000-0000-0000-00000000000b
# ╟─07000000-0000-0000-0000-00000000000f
# ╠═07000000-0000-0000-0000-000000000010
# ╠═07000000-0000-0000-0000-000000000011
# ╟─07000000-0000-0000-0000-00000000000c
# ╠═07000000-0000-0000-0000-00000000000d
