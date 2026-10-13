### A Pluto.jl notebook ###
# v0.20.24

#> [frontmatter]
#> order = 5
#> title = "Extending the model: CANVAS"
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

# ╔═╡ 9222600a-aeb2-11f1-8097-b3e7ed45a1f8
md"""
# Notebook 04 — Extending the model: CANVAS *(advanced)*

> **Question:** how does a persistent increase in firms' wage norms propagate, and how do firms' price and quantity rules affect its transmission?

### Before running anything
Predict the first direct effect: household income, firms' wage costs, or both?
Then distinguish an inflation **rate** from a permanently higher **price level**.
The online page shows saved outputs; run Pluto locally to change the controls.

### Lecture 2 slides covered
- *Pricing mechanism* (CANVAS)
- *Demand-pull mechanisms*
- *CANVAS pricing mechanism implicit assumptions*
- *Sectoral inflation decomposition*

### Learning goals
1. Add model-specific price and quantity decisions without replacing the base model's method.
2. Read the local demand/price signals used in CANVAS.
3. Compare shock effects against each model's own matched baseline.
4. Distinguish channel-isolation experiments from an additive causal decomposition.
"""

# ╔═╡ 92249eb2-aeb2-11f1-93c6-5f7eb9558b2f
begin
    import Pkg
    Pkg.activate(joinpath(@__DIR__, "..", "..", "pluto_tutorial"); io=devnull)
    import BeforeIT as Bit
    import Random
    using Plots, PlutoUI, Statistics, StatsPlots
    nb4_p = Bit.AUSTRIA2010Q1.parameters
    nb4_ic = Bit.AUSTRIA2010Q1.initial_conditions
end

# ╔═╡ 92249fa0-aeb2-11f1-ace8-bd629c2e194b
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

# Step 3: initialise fresh components with your type
model = MyModel((w_act, w_inact, firms, bank, cb, gov, rotw, agg, prop, data))
Bit.run!(model, 1)   # calls your method, then records the quarter's outcomes
```

The tuple constructor performs the shared initialisation, including worker–firm
assignment, balance sheets and the initial data point. For fresh components, calling
the field constructor directly would skip those steps. `build_canvas_model` below uses
the tuple constructor and then initialises CANVAS's planned-supply field.
"""

# ╔═╡ 92249fd2-aeb2-11f1-9494-cba8284edbc5
md"""
---
## 2 — Read the CANVAS pricing equation

$$P_i(t)=P_i(t-1)
\underbrace{(1+\phi^{DP}\pi_i^d(t))}_{\text{demand-pull}}
\underbrace{(1+\phi^{CP}\pi_i^c(t))}_{\text{cost-push}}
\underbrace{(1+\phi^{AE}\pi^e(t))}_{\text{aggregate expectations}}.$$

Each factor is a gross price multiplier. The channel signals are rates expressed as
fractions: a signal of 0.02 with a coefficient of 0.5 contributes a multiplier of 1.01.
The product of the factors, not their sum, determines the price change.

| Last demand versus planned supply | Firm price versus sector average | Adjustment |
|---|---|---|
| Demand at least as high as supply | Below average | Price signal |
| Demand at least as high as supply | At or above average | Output signal |
| Demand below supply | At or above average | Price signal |
| Demand below supply | Below average | Output signal |

A coefficient of 1 applies the full **computed channel signal**; it does not mean a
10% wage intervention becomes 10% inflation. A smaller coefficient attenuates that
channel's direct effect. Its effect on persistence is a question for the model experiment,
not a guaranteed consequence of the equation.
"""

# ╔═╡ 9224a004-aeb2-11f1-8efc-33d761348d38
md"""
### Information, timing and assumptions

The firm compares its lagged realised demand with its planned supply and its own price
with the sector average. Excess demand at a relatively low price signals scope to raise
prices; excess supply at a relatively high price signals a price cut. The other two
quadrants adjust planned output. At equal demand and supply the adjustment signal is zero.

**Zero-demand and zero-supply states:** the relative-demand signal cannot be used when supply
is zero, and full pass-through of a zero-demand price signal would set the quote to zero.
For either boundary, this teaching extension instead targets observed demand (adjusted for
expected growth) and leaves the demand-price multiplier at one. Zero demand therefore gives
a zero quantity target; positive demand restarts a firm that previously supplied nothing.
Cost and expectation effects still apply. This is an explicit behavioural assumption; it
does not imply firm exit or override BeforeIT's minimum employment rule. Invalid quantities
or nonpositive price quotes raise an error rather than propagating NaNs.

The comparison with BeforeIT changes **both** pricing and quantity planning: in positive
price-adjustment quadrants CANVAS retains previous planned supply, while BeforeIT targets
previous demand. Differences between these models therefore reflect both mechanisms.

This is a behavioural rule based on local information, not a derivation of optimal
price-setting. The experiment varies its coefficients by hand: it does not estimate
price stickiness or reproduce an empirical inflation decomposition.

**Check before coding:** changing a pricing method also affects production, profits,
employment, expectations and later demand. Those feedbacks prevent a simple interpretation
of each plotted line as an isolated direct price elasticity.
"""

# ╔═╡ 9224a036-aeb2-11f1-8043-d9080676020a
md"""
---
## 3 — Implementing the CANVAS extension
"""

# ╔═╡ 9224a05e-aeb2-11f1-a81a-57549d5890ea
begin
    # The CANVAS model lives in canvas_model.jl so that this notebook and
    # Notebook 05 share one definition instead of two copies that can drift.
    include(joinpath(@__DIR__, "..", "..", "pluto_tutorial", "canvas_model.jl"))
    "CANVASModel, its pricing override and build_canvas_model loaded ✓"
end

# ╔═╡ 9224a086-aeb2-11f1-bbc0-a112bceab37a
md"""
---
## 4 — Matched pass-through experiments

The intervention increases `firms.w_bar_i`, the firm-specific **wage norm**, by 10% at
quarter 1 and leaves it elevated. The model subsequently computes actual wages from this
norm and production conditions; actual wages and the aggregate wage bill need not rise
by exactly 10%.

Changing only `w_i` at this hook would fail: `set_firms_wages!` recomputes that field later
in the same quarter. This is why understanding the step order matters when writing shocks.

Compare each model's shocked path with **its own** unshocked baseline. Both model families
use the same calibration and seeded replicate list; changes to the pricing architecture
can still alter later random-number use. We run eight paths serially for a practical,
reproducible default. Confirm the three coefficients together before rerunning.
"""

# ╔═╡ 9224a0b8-aeb2-11f1-9eac-0f290383286a
begin
    nb4_controls = @bind canvas_settings PlutoUI.confirm(PlutoUI.combine() do Child
        md"""
        **Demand-pull ϕDP:** $(Child("dp", PlutoUI.Slider(0.0:0.1:1.0, default=1.0, show_value=true)))

        **Cost-push ϕCP:** $(Child("cp", PlutoUI.Slider(0.0:0.1:1.0, default=1.0, show_value=true)))

        **Aggregate-expectations ϕAE:** $(Child("ae", PlutoUI.Slider(0.0:0.1:1.0, default=1.0, show_value=true)))
        """
    end)
    phi_dp = canvas_settings.dp
    phi_cp = canvas_settings.cp
    phi_ae = canvas_settings.ae
    nb4_controls
end

# ╔═╡ 9224a0d6-aeb2-11f1-9134-bfa1c318d506
@bind run_canvas PlutoUI.Button("▶ Run CANVAS comparison (16 quarters)")

# ╔═╡ 9224a11e-aeb2-11f1-9502-c332731b0d24
begin
    struct Nb4WageShock; mult::Float64 end
    function (s::Nb4WageShock)(model)
        model.agg.t == 1 && (model.firms.w_bar_i .*= s.mult)
    end

    function nb4_ensemble(builder; shock=Bit.NoShock(), seed=7, n=8, T=16)
        map(1:n) do i
            Random.seed!(seed + i)
            Bit.run!(builder(), T; shock! = shock, parallel=false)
        end
    end

    ens_field(ens, field) = hcat([getfield(m.data, field) for m in ens]...)
    nb4_defl(ens) = ens_field(ens, :nominal_gdp) ./ ens_field(ens, :real_gdp)
    nb4_infl(d) = diff(d, dims=1) ./ selectdim(d, 1, 1:(size(d, 1)-1))

    # Exact price-level gap. Its log is the cumulative difference in log inflation.
    nb4_price_gap(ens_s, ens_b) = 100 .* (nb4_defl(ens_s) ./ nb4_defl(ens_b) .- 1)
    nb4_log_gap(ens_s, ens_b) = 100 .* log.(nb4_defl(ens_s) ./ nb4_defl(ens_b))

    # The shared Ref is restored even if a simulation fails.
    function run_isolated_pair(phi_val; shock=Nb4WageShock(1.10), seed=7, n=8, T=16)
        previous_phi = CANVAS_PHI[]
        try
            CANVAS_PHI[] = phi_val
            builder = () -> build_canvas_model(nb4_p, nb4_ic)
            ens_b = nb4_ensemble(builder; seed, n, T)
            ens_s = nb4_ensemble(builder; shock, seed, n, T)
            return ens_b, ens_s
        finally
            CANVAS_PHI[] = previous_phi
        end
    end
end

# ╔═╡ 9224a144-aeb2-11f1-82e8-f92c34855890
begin
    run_canvas
    wage_shock = Nb4WageShock(1.10)
    poledna_builder = () -> Bit.Model(nb4_p, nb4_ic)
    ens_poledna_base = nb4_ensemble(poledna_builder)
    ens_poledna_shock = nb4_ensemble(poledna_builder; shock=wage_shock)
    nb4_selected_phi = (dp=phi_dp, cp=phi_cp, ae=phi_ae)
    ens_canvas_base, ens_canvas_shock = run_isolated_pair(nb4_selected_phi; shock=wage_shock)
    "Matched CANVAS comparison complete ✓"
end

# ╔═╡ 9224a162-aeb2-11f1-8958-119a77de5232
begin
    run_canvas

    p1 = errorline(0:16, nb4_price_gap(ens_poledna_shock, ens_poledna_base);
        errorstyle=:ribbon, errortype=:sem, label="Poledna baseline pricing",
        lw=2, color=:steelblue, title="GDP deflator after a 10% wage-norm increase",
        xlabel="Quarter", ylabel="Price level above own baseline (%)")
    errorline!(p1, 0:16, nb4_price_gap(ens_canvas_shock, ens_canvas_base);
        errorstyle=:ribbon, errortype=:sem,
        label="CANVAS (ϕDP=$(phi_dp), ϕCP=$(phi_cp), ϕAE=$(phi_ae))",
        lw=2, color=:tomato, ls=:dash)
    hline!(p1, [0.0]; color=:black, lw=1, label="No effect")

    p2 = errorline(0:16,
        100 .* (ens_field(ens_poledna_shock, :real_gdp) ./ ens_field(ens_poledna_base, :real_gdp) .- 1);
        errorstyle=:ribbon, errortype=:sem, label="Poledna", lw=2, color=:steelblue,
        title="Real GDP: shock versus own baseline", xlabel="Quarter", ylabel="GDP change (%)")
    errorline!(p2, 0:16,
        100 .* (ens_field(ens_canvas_shock, :real_gdp) ./ ens_field(ens_canvas_base, :real_gdp) .- 1);
        errorstyle=:ribbon, errortype=:sem, label="CANVAS", lw=2, color=:tomato, ls=:dash)
    hline!(p2, [0.0]; color=:black, lw=1, label="No effect")
    plot(p1, p2; layout=(1, 2), size=(900, 410), legend=:topright)
end

# ╔═╡ 9224a17e-aeb2-11f1-b3ec-274348f58db8
md"""
**Read these units:** a price-level gap of 2 means the GDP deflator is 2% above that model's
baseline. It does not mean inflation remains 2 percentage points higher every quarter.
A flat positive gap means the price level stays higher while the additional inflation
has ended. Ribbons show one Monte Carlo standard error of the mean paired effect, not
uncertainty about estimated parameters.

---
## 5 — Channel-isolation experiments

For a fixed reference with all three coefficients equal to 1, activate one channel at a
time and compare its wage intervention with its own baseline. This reference is independent
of the sliders above; it always means **all three coefficients equal to 1**.

The decomposition uses **100 × log(price-level ratio)**, exactly the cumulative difference
in log inflation. Isolated experiments generally do not add up to the full response.
The plotted remainder collects the non-additivity of all feedbacks; it is not a uniquely
identified structural contribution or only a second-order cross-product in the price equation.
This experiment alone does not establish bias in an empirical regression.
"""

# ╔═╡ 9224a1a8-aeb2-11f1-91ff-97184fcd8a4b
@bind run_decomp PlutoUI.Button("▶ Compare isolated channels and fixed full reference")

# ╔═╡ 9224a1d0-aeb2-11f1-8167-91cd39977eb3
begin
    run_decomp
    _ens_b_dp, _ens_s_dp = run_isolated_pair((dp=1.0, cp=0.0, ae=0.0))
    _ens_b_cp, _ens_s_cp = run_isolated_pair((dp=0.0, cp=1.0, ae=0.0))
    _ens_b_ae, _ens_s_ae = run_isolated_pair((dp=0.0, cp=0.0, ae=1.0))
    _ens_b_full, _ens_s_full = run_isolated_pair((dp=1.0, cp=1.0, ae=1.0))

    ei_dp_iso = nb4_log_gap(_ens_s_dp, _ens_b_dp)
    ei_cp_iso = nb4_log_gap(_ens_s_cp, _ens_b_cp)
    ei_ae_iso = nb4_log_gap(_ens_s_ae, _ens_b_ae)
    ei_full = nb4_log_gap(_ens_s_full, _ens_b_full)
    ei_interact = ei_full .- ei_dp_iso .- ei_cp_iso .- ei_ae_iso
    @assert isapprox(ei_full, ei_dp_iso .+ ei_cp_iso .+ ei_ae_iso .+ ei_interact)

    qs = 0:16
    p_decomp = errorline(qs, ei_dp_iso; errortype=:sem, lw=2, color=:tomato, ls=:dash, label="Demand-pull only")
    errorline!(p_decomp, qs, ei_cp_iso; errortype=:sem, lw=2, color=:steelblue, ls=:dash, label="Cost-push only")
    errorline!(p_decomp, qs, ei_ae_iso; errortype=:sem, lw=2, color=:goldenrod, ls=:dash, label="Expectations only")
    errorline!(p_decomp, qs, ei_interact; errortype=:sem, lw=1, color=:grey, ls=:dot, label="Non-additivity remainder")
    errorline!(p_decomp, qs, ei_full; errortype=:sem, lw=3, color=:black, label="All three coefficients = 1")
    hline!(p_decomp, [0.0]; lw=1, color=:grey, label="No effect")
    plot!(p_decomp; title="Wage-norm intervention: channel isolation",
        xlabel="Quarter", ylabel="Cumulative log-inflation difference (100 × log ratio)",
        legend=:topleft, size=(850, 420))
end

# ╔═╡ 9224a1ee-aeb2-11f1-a96c-a5246dec63cb
md"""
**Interpretation checklist:**
1. All curves start at zero: the intervention is applied after the initial observation.
2. Explain why raising wage norms changes both household income and firms' wage costs.
3. Compare a lower cost-push coefficient with the full setting. Do not presume it lowers
   the total inflation response or increases persistence: other channels can compensate.
4. The remainder is defined so the curves add up numerically. This identity checks the
   calculation, not the empirical validity of the channels.

All coefficients here are chosen by hand. Notebook 05 introduces inference; these runs
are mechanism illustrations, not evidence about estimated Austrian or Dutch pass-through.
"""

# ╔═╡ 9224a216-aeb2-11f1-ba17-6bcbccd1a13c
md"""
---
## ✔ What you learned

- Model-type dispatch changes price and quantity rules while retaining the base model's method.
- CANVAS combines demand/relative-price signals with cost-push and aggregate expectations.
- A wage-norm intervention must survive the model's wage-update step.
- Each treatment needs its own baseline; price-level gaps and inflation-rate differences use different units.
- Channel-isolation experiments include economy-wide feedbacks, so they are not additive direct-effect estimates.
- This notebook changes price and quantity decisions; the upstream CANVAS example also changes monetary-policy learning.

---
## Exercises — predict, run, explain, check

**04.1 — A no-intervention check.** Replace `Nb4WageShock(1.10)` with
`Nb4WageShock(1.0)` in the main comparison. What should both panels show?
*Check:* use the same seed list. Restore 1.10 afterward. This changes the main experiment;
the fixed channel-isolation experiment separately constructs its 1.10 intervention.

**04.2 — Price level versus inflation.** Run the default comparison. Find a quarter where
the price-level gap is approximately flat. Is the inflation-rate difference also large?
*Hint:* compute simple inflation with `nb4_infl(nb4_defl(ensemble))`, then compare each
shocked path with its own baseline. Multiply rate differences by 100 for percentage points.

**04.3 — Turn off direct cost-push.** Set ϕCP = 0, keep the other coefficients at 1,
and confirm. Predict whether higher household income can still alter demand and prices.
*Check:* compare the full reference with the cost-push-only curve. Zeroing one pricing
channel does not switch off wage payments or the other channels.

**04.4 — Persistence without assuming it.** Compare ϕAE = 1 and ϕAE = 0 with the same
other settings. Record the quarter-16 price-level gap and the quarterly inflation differences.
*Hint:* a higher terminal price level and persistent extra inflation are different claims.
Repeat the seed list before drawing a general conclusion about expectation feedback.

**04.5 — Interpret the remainder.** Verify that the isolated curves plus the remainder
recover the full-reference curve. Explain why this arithmetic identity does not identify
an empirical interaction coefficient or prove that a single-equation estimate is biased.
"""

# ╔═╡ Cell order:
# ╟─9222600a-aeb2-11f1-8097-b3e7ed45a1f8
# ╠═92249eb2-aeb2-11f1-93c6-5f7eb9558b2f
# ╟─92249fa0-aeb2-11f1-ace8-bd629c2e194b
# ╟─92249fd2-aeb2-11f1-9494-cba8284edbc5
# ╟─9224a004-aeb2-11f1-8efc-33d761348d38
# ╟─9224a036-aeb2-11f1-8043-d9080676020a
# ╠═9224a05e-aeb2-11f1-a81a-57549d5890ea
# ╟─9224a086-aeb2-11f1-bbc0-a112bceab37a
# ╠═9224a0b8-aeb2-11f1-9eac-0f290383286a
# ╠═9224a0d6-aeb2-11f1-9134-bfa1c318d506
# ╠═9224a11e-aeb2-11f1-9502-c332731b0d24
# ╠═9224a144-aeb2-11f1-82e8-f92c34855890
# ╠═9224a162-aeb2-11f1-8958-119a77de5232
# ╟─9224a17e-aeb2-11f1-b3ec-274348f58db8
# ╠═9224a1a8-aeb2-11f1-91ff-97184fcd8a4b
# ╠═9224a1d0-aeb2-11f1-8167-91cd39977eb3
# ╟─9224a1ee-aeb2-11f1-a96c-a5246dec63cb
# ╠═9224a216-aeb2-11f1-ba17-6bcbccd1a13c
