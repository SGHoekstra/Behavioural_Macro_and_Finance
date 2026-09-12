### A Pluto.jl notebook ###
# v0.20.24

#> [frontmatter]
#> title = "Expectations, policy and fiscal closure"
#> order = 6
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

# ╔═╡ 05000000-0000-0000-0000-000000000001
begin
    import Pkg
    Pkg.activate(joinpath(@__DIR__, "..", "..", "pluto_tutorial"); io=devnull)
    import BeforeIT as Bit
    import Random
    using Plots, PlutoUI, Statistics
end

# ╔═╡ 05000000-0000-0000-0000-000000000002
md"""
# Notebook 05 — Expectations, Monetary Policy, and Fiscal Closure

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

# ╔═╡ 05000000-0000-0000-0000-000000000003
begin
    nb05_p  = Bit.AUSTRIA2010Q1.parameters
    nb05_ic = Bit.AUSTRIA2010Q1.initial_conditions
    "Calibration loaded ✓"
end

# ╔═╡ 05000000-0000-0000-0000-000000000004
md"""
---
## 1 — AR(1) expectation formation

Lecture 2, slide *"Household behaviour"*, gives the expectation rules:

$$\mathbb{E}^*_t[\pi_{t+1}] = \alpha^\pi_t \, \pi_t + \beta^\pi_t$$
$$\mathbb{E}^*_t[y_{t+1}] = \alpha^y_t \, y_t + \beta^y_t$$

where $\alpha^\pi_t, \beta^\pi_t, \alpha^y_t, \beta^y_t$ are updated **each quarter via OLS** on the history of realised inflation and output. This is **adaptive learning** — agents use all past data optimally but don't know the future.

The mechanism is implemented in `Bit.estimate_next_value(data)`, which accepts a vector of past realisations and returns the OLS-optimal AR(1) one-step-ahead forecast.

We can override this function via multiple dispatch to experiment with alternative expectation schemes.
"""

# ╔═╡ 05000000-0000-0000-0000-000000000005
md"""
---
## 2 — AR(1) vs backward-looking expectations

Let's compare two expectation schemes:
- **AR(1) (default):** `Bit.estimate_next_value(data)` — OLS optimal forecast.
- **Constant (backward-looking):** always expect last period's value.

The `change_expectations.jl` upstream example shows exactly how to do this.
"""

# ╔═╡ 05000000-0000-0000-0000-000000000006
@bind run_expectations PlutoUI.Button("▶ Compare expectations (40 quarters each, ~2 min)")

# ╔═╡ 05000000-0000-0000-0000-000000000007
begin
    run_expectations
    Random.seed!(1234)

    # --- Default: AR(1) forward-looking ---
    nb05_model_ar1 = Bit.Model(nb05_p, nb05_ic)
    Bit.run!(nb05_model_ar1, 40)

    # --- Override: constant/backward-looking expectations ---
    # Julia multiple dispatch: adding a 1-arg method that always returns the last value.
    function Bit.estimate_next_value(data)
        return data[end]    # always expect last period's value
    end

    Random.seed!(1234)
    nb05_model_const = Bit.Model(nb05_p, nb05_ic)
    Bit.run!(nb05_model_const, 40)

    # Restore the default OLS-AR(1) behaviour for the rest of this notebook session
    # by delegating back to BeforeIT's original 2-arg method.
    # Note: each Pluto notebook runs in its own Julia session, so this override
    # does not affect any other notebook.
    function Bit.estimate_next_value(data)
        return Bit.estimate_next_value(data, nothing)
    end

    "Expectations comparison complete ✓"
end

# ╔═╡ 05000000-0000-0000-0000-000000000008
begin
    run_expectations
    p_exp_gdp = plot(
        nb05_model_ar1.data.real_gdp, label = "AR(1) expectations",
        lw = 2, color = :steelblue, title = "Real GDP",
        xlabel = "Quarter",
    )
    plot!(p_exp_gdp, nb05_model_const.data.real_gdp, label = "Constant expectations",
          lw = 2, color = :tomato, ls = :dash)

    p_exp_defl = plot(
        nb05_model_ar1.data.nominal_gdp ./ nb05_model_ar1.data.real_gdp, label = "AR(1)",
        lw = 2, color = :steelblue, title = "GDP deflator",
        xlabel = "Quarter",
    )
    plot!(p_exp_defl, nb05_model_const.data.nominal_gdp ./ nb05_model_const.data.real_gdp, label = "Constant",
          lw = 2, color = :tomato, ls = :dash)

    plot(p_exp_gdp, p_exp_defl, layout = (1, 2), size = (800, 350))
end

# ╔═╡ 05000000-0000-0000-0000-000000000009
md"""
Differences reflect how well agents anticipate turning points:
- **AR(1)** agents can identify trends and adjust production/consumption earlier.
- **Constant** agents always anchor to last period's value — they are systematically surprised whenever the economy moves.

Higher volatility under constant expectations is a direct consequence of larger forecast errors feeding back into pricing and production decisions.
"""

# ╔═╡ 05000000-0000-0000-0000-00000000000a
md"""
---
## 3 — The Taylor rule

Lecture 2 slide *"Fiscal and monetary closure"* gives the generalised Taylor rule:

$$\bar{r}_t = \rho\,\bar{r}_{t-1} + (1-\rho)\!\left[\pi^* + \xi^\pi(\pi^{EA}_t - \pi^*) + \xi^\gamma \gamma^{EA}_t\right]$$

**Key design choice:** the central bank reacts to **euro-area** inflation $\pi^{EA}$ and growth $\gamma^{EA}$, not domestic conditions. This is the small-open-economy assumption: Austria is in the eurozone and cannot set its own policy rate independently.

The estimated parameters (from the Lecture 2 parameter table):
- $\rho = 0.9263$ (high smoothing — the ECB moves rates slowly)
- $\xi^\pi = 0.3214$ (mild inflation response)
- $\xi^\gamma = 1.2994$ (stronger output growth response)

Let's explore how changing these parameters shifts the policy path.
"""

# ╔═╡ 05000000-0000-0000-0000-00000000000b
md"""
**Taylor rule parameters:**

Smoothing $\rho$: $(@bind rho_val PlutoUI.Slider(0.0:0.05:0.99, default=0.9263, show_value=true))

Inflation weight $\xi^\pi$: $(@bind xi_pi_val PlutoUI.Slider(0.0:0.1:3.0, default=0.3214, show_value=true))

Growth weight $\xi^\gamma$: $(@bind xi_gamma_val PlutoUI.Slider(0.0:0.1:3.0, default=1.2994, show_value=true))
"""

# ╔═╡ 05000000-0000-0000-0000-00000000000c
@bind run_taylor PlutoUI.Button("▶ Run Taylor rule experiment (20 quarters)")

# ╔═╡ 05000000-0000-0000-0000-00000000000d
begin
    run_taylor
    Random.seed!(42)

    # Default calibration
    nb05_m_default = Bit.Model(nb05_p, nb05_ic)
    Bit.run!(nb05_m_default, 20)

    # Custom Taylor rule via parameter modification
    nb05_params_custom = deepcopy(nb05_p)
    nb05_params_custom["rho"] = rho_val
    nb05_params_custom["xi_pi"] = xi_pi_val
    nb05_params_custom["xi_gamma"] = xi_gamma_val

    Random.seed!(42)
    nb05_m_custom = Bit.Model(nb05_params_custom, nb05_ic)
    Bit.run!(nb05_m_custom, 20)

    "Taylor experiment complete ✓"
end

# ╔═╡ 05000000-0000-0000-0000-00000000000e
begin
    run_taylor
    nb05_p1 = plot(
        nb05_m_default.data.euribor .* 100, label = "Default (ρ=0.93, ξᵖ=0.32, ξᵞ=1.30)",
        lw = 2, color = :steelblue,
        title = "Policy rate (%)", xlabel = "Quarter", ylabel = "%",
    )
    plot!(nb05_p1, nb05_m_custom.data.euribor .* 100,
          label = "Custom (ρ=$(rho_val), ξᵖ=$(xi_pi_val), ξᵞ=$(xi_gamma_val))",
          lw = 2, color = :tomato, ls = :dash)

    nb05_p2 = plot(
        nb05_m_default.data.real_gdp, label = "Default", lw = 2, color = :steelblue,
        title = "Real GDP", xlabel = "Quarter",
    )
    plot!(nb05_p2, nb05_m_custom.data.real_gdp, label = "Custom", lw = 2, color = :tomato, ls = :dash)

    nb05_p3 = plot(
        nb05_m_default.data.nominal_gdp ./ nb05_m_default.data.real_gdp, label = "Default", lw = 2, color = :steelblue,
        title = "GDP deflator", xlabel = "Quarter",
    )
    plot!(nb05_p3, nb05_m_custom.data.nominal_gdp ./ nb05_m_custom.data.real_gdp, label = "Custom", lw = 2, color = :tomato, ls = :dash)

    plot(nb05_p1, nb05_p2, nb05_p3, layout = (1, 3), size = (900, 320), legend = :bottomright)
end

# ╔═╡ 05000000-0000-0000-0000-00000000000f
md"""
Try:
- **Low smoothing** ($\rho \approx 0$): rates jump aggressively each quarter. Does this stabilise or destabilise GDP?
- **High inflation weight** ($\xi^\pi > 2$): strong anti-inflation stance. How does this affect real output?
- **Zero growth weight** ($\xi^\gamma = 0$): pure inflation-targeting. Compare to the "balanced" calibration.
"""

# ╔═╡ 05000000-0000-0000-0000-000000000014
md"""
The government sector is fully embedded in the SFC structure — every transfer, tax, and interest payment is accounted for on both sides of the balance sheet. There is no "black box" government in this model.
"""

# ╔═╡ 05000000-0000-0000-0000-000000000015
md"""
---
## ✔ What you learned

- Agents update AR(1) expectation coefficients via OLS each quarter — adaptive learning, not rational expectations.
- Overriding `Bit.estimate_next_value` changes the expectation scheme for all agents; multiple dispatch is the extension mechanism.
- The Taylor rule responds to **euro-area** (not domestic) conditions — the small-open-economy constraint.
- High smoothing ($\rho \approx 0.93$) creates persistent monetary policy inertia.

---
## Exercises

**Exercise 05.1** — Set $\xi^\pi = 0$ (Taylor rule ignores inflation entirely) and compare GDP deflator paths against the baseline. Does the economy become more or less inflationary?

**Exercise 05.2** — Run the constant-expectations model 10 times with different seeds. Compute the standard deviation of real GDP at quarter 20. Compare to the AR(1) model. Which generates more volatility?

**Exercise 05.3** *(stretch)* — Modify the Taylor rule to respond to **domestic** inflation instead of euro-area inflation. You'll need to override a different function in `Bit`. Hint: look at `Bit.set_central_bank_rate!` and create a method for a custom model type. Is the policy-rate path smoother or noisier?
"""

# ╔═╡ Cell order:
# ╟─05000000-0000-0000-0000-000000000002
# ╠═05000000-0000-0000-0000-000000000001
# ╠═05000000-0000-0000-0000-000000000003
# ╟─05000000-0000-0000-0000-000000000004
# ╟─05000000-0000-0000-0000-000000000005
# ╠═05000000-0000-0000-0000-000000000006
# ╠═05000000-0000-0000-0000-000000000007
# ╠═05000000-0000-0000-0000-000000000008
# ╟─05000000-0000-0000-0000-000000000009
# ╟─05000000-0000-0000-0000-00000000000a
# ╠═05000000-0000-0000-0000-00000000000b
# ╠═05000000-0000-0000-0000-00000000000c
# ╠═05000000-0000-0000-0000-00000000000d
# ╠═05000000-0000-0000-0000-00000000000e
# ╟─05000000-0000-0000-0000-00000000000f
# ╟─05000000-0000-0000-0000-000000000014
# ╠═05000000-0000-0000-0000-000000000015
