### A Pluto.jl notebook ###
# v0.20.4

using Markdown
using InteractiveUtils

# This Pluto notebook uses @bind for interactivity. When running this notebook outside of Pluto, the following 'mock version' of @bind gives bound variables a default value (instead of an error).
macro bind(def, element)
    #! format: off
    quote
        local iv = try Base.loaded_modules[Base.PkgId(Base.UUID("6e696c72-6542-2067-7265-42206c756150"), "AbstractPlutoDingetjes")].Bonds.initial_value catch; b -> missing; end
        local el = $(esc(element))
        global $(esc(def)) = Core.applicable(Base.get, el) ? Base.get(el) : iv(el)
        el
    end
    #! format: on
end

# ╔═╡ 0a000000-0000-0000-0000-000000000001
begin
    import Pkg
    Pkg.activate(dirname(@__FILE__))
    using PlutoUI
end

# ╔═╡ 0a000000-0000-0000-0000-000000000002
md"""
# Notebook 00 — Julia + Pluto Primer

**An optional, roughly 20-minute introduction to the Julia and Pluto features used in this course.**

Read the examples, predict their outputs, then change one input and explain the result. Online pages display saved outputs; run the notebook in Pluto to edit code or use the controls.

If you are already comfortable with Julia, skip to **Notebook 01**.

### What this notebook covers
1. Variables, types, and functions
2. Arrays and broadcasting
3. Structs and `fieldnames` — needed to inspect the BeforeIT model
4. Multiple dispatch in one example — needed for model extensions (Notebook 04)
5. Pluto specifics: reactive cells, `begin…end`, `@bind`
6. A mini exercise to check understanding
"""

# ╔═╡ 0a000000-0000-0000-0000-000000000003
md"""
---
## 1. Variables and types

Julia is dynamically typed — you rarely write types explicitly. But types matter for performance and for understanding `fieldnames` later.
"""

# ╔═╡ 0a000000-0000-0000-0000-000000000004
begin
    # Basic values
    x = 3.14          # Float64
    n = 42            # Int64
    s = "hello"       # String
    flag = true       # Bool
    typeof(x), typeof(n), typeof(s)
end


# ╔═╡ 0a000000-0000-0000-0000-000000000005
md"""
Julia also has **named tuples** — lightweight records without a struct:
"""

# ╔═╡ 0a000000-0000-0000-0000-000000000006
begin
    agent = (id = 1, income = 35_000.0, employed = true)
    agent.income   # dot-access by name
end


# ╔═╡ 0a000000-0000-0000-0000-000000000007
md"""
---
## 2. Functions

Two common styles:
"""

# ╔═╡ 0a000000-0000-0000-0000-000000000008
begin
    # Multi-line function
    function compound_growth(value, rate, periods)
        return value * (1 + rate)^periods
    end
    
    # One-liner
    wage_after_tax(w, τ) = w * (1 - τ)
    
    compound_growth(1000.0, 0.02, 4)   # ≈ 1082
end


# ╔═╡ 0a000000-0000-0000-0000-000000000009
md"""
---
## 3. Arrays and broadcasting

Arrays are **1-indexed** (not 0-indexed like Python).

The **dot (`.`) operator** broadcasts any function element-wise — this is used heavily in BeforeIT to update all agents at once without a loop.
"""

# ╔═╡ 0a000000-0000-0000-0000-00000000000a
begin
    wages = [30_000.0, 45_000.0, 28_000.0, 60_000.0]
    
    # Element-wise tax deduction using broadcasting:
    τ_inc = 0.2134    # income tax rate from Lecture 2 parameter table
    net_wages = wages .* (1 - τ_inc)
end


# ╔═╡ 0a000000-0000-0000-0000-00000000000b
begin
    # Ranges and comprehensions
    quarters = 1:20                          # range object (lazy)
    gdp_fake = [100.0 * 1.005^t for t in quarters]   # list comprehension
    gdp_fake[end]   # last element
end


# ╔═╡ 0a000000-0000-0000-0000-00000000000c
md"""
---
## 4. Structs and `fieldnames`

BeforeIT stores all agents in **structs** (plain data containers). You will use `fieldnames` to inspect what fields are available.
"""

# ╔═╡ 0a000000-0000-0000-0000-00000000000d
begin
    struct Household
        id::Int
        income::Float64
        deposits::Float64
        employed::Bool
    end
    
    h = Household(1, 35_000.0, 5_000.0, true)
    fieldnames(typeof(h))    # (:id, :income, :deposits, :employed)
end


# ╔═╡ 0a000000-0000-0000-0000-00000000000e
h.income   # dot-access

# ╔═╡ 0a000000-0000-0000-0000-00000000000f
md"""
In BeforeIT, the model uses a **struct-of-arrays (SoA)** layout for performance: instead of a vector of `Household` structs, there is one struct containing vectors. For example, `model.w_act.Y_h` contains regular workers' incomes, while `model.w_act.D_h` contains their deposits. `Y_h` is the model's actual field name; `income` belongs only to the toy `Household` above.

A further distinction matters: `b = wages` refers to the same array as `wages`, whereas `b = copy(wages)` creates a separate array. Use a copy when you want a comparison that leaves the original data unchanged.
"""

# ╔═╡ 0a000000-0000-0000-0000-000000000010
md"""
---
## 5. Multiple dispatch

Julia functions can have multiple **methods** — different implementations selected by argument type. This is how BeforeIT's model extensions work: you define a new method for your custom model type, and Julia calls it automatically.
"""

# ╔═╡ 0a000000-0000-0000-0000-000000000011
begin
    # Default implementation
    set_price!(firms) = firms .*= 1.02
    
    # Specialised method for a custom type
    struct PriceSticky end
    set_price!(firms, ::PriceSticky) = firms .*= 1.005   # stickier prices
    
    prices = [10.0, 20.0, 30.0]
    set_price!(copy(prices))             # uses default method → +2%
end


# ╔═╡ 0a000000-0000-0000-0000-000000000012
set_price!(copy(prices), PriceSticky())   # uses sticky method → +0.5%

# ╔═╡ 0a000000-0000-0000-0000-000000000013
md"""
The `!` convention signals that a function changes its input: these methods mutate the copied price vector. Multiple dispatch chooses a method from the argument types. In Notebook 04, an additional method for a custom model type changes firms' decisions while the base-model method remains available.
"""

# ╔═╡ 0a000000-0000-0000-0000-000000000014
md"""
---
## 6. Pluto specifics

Pluto notebooks are **reactive**: when you change a cell, every cell that depends on it re-runs automatically.

### One definition per cell
Each global variable must have **one defining cell**. A cell can define several variables; group its expressions in a `begin ... end` block. Other cells may read those variables. Renaming a variable in an exercise avoids a duplicate definition:
"""

# ╔═╡ 0a000000-0000-0000-0000-000000000015
begin
    τ_vat = 0.1529     # VAT rate (from Lecture 2 parameter table)
    τ_firm = 0.0770    # rounded corporate tax rate for this example
end

# ╔═╡ 0a000000-0000-0000-0000-000000000016
md"""
### Interactive sliders with `@bind`

`@bind` connects a widget to a Julia variable. Every time you move the slider, all dependent cells re-execute.
"""

# ╔═╡ 0a000000-0000-0000-0000-000000000017
@bind τ_slider PlutoUI.Slider(0.0:0.01:0.5, default=0.2134, show_value=true)

# ╔═╡ 0a000000-0000-0000-0000-000000000018
# This cell re-runs every time you move the slider above
net_income_demo = 50_000.0 * (1 - τ_slider)

# ╔═╡ 0a000000-0000-0000-0000-000000000019
md"""
Net income at tax rate $(round(τ_slider * 100, digits=1))%: **€$(round(net_income_demo, digits=0))**
"""

# ╔═╡ 0a000000-0000-0000-0000-00000000001a
md"""
### Expensive computations: confirm the settings

A button creates another dependency; it does not stop a cell from rerunning when other inputs change. Wrap an expensive calculation's controls in `PlutoUI.confirm` instead. Moving this slider does not update the bound value until you press **Apply setting**. The default calculation still runs once when the notebook opens.
"""

# ╔═╡ 0a000000-0000-0000-0000-00000000001b
@bind run_demo PlutoUI.confirm(PlutoUI.Slider(1:5, default=2, show_value=true); label="Apply setting")

# ╔═╡ 0a000000-0000-0000-0000-00000000001c
begin
    run_demo   # updates after confirming the slider value
    sleep(0.1) # simulating a slow operation
    "Computation complete for confirmed setting $(run_demo)."
end

# ╔═╡ 0a000000-0000-0000-0000-00000000001d
md"""
---
## ✔ Checklist — you're ready for the tutorials if you can answer:

- [ ] How do you broadcast a function over an array in Julia?
- [ ] What does `fieldnames(typeof(x))` return?
- [ ] What does `@bind` do in a Pluto notebook?
- [ ] Why confirm settings before an expensive computation?

If you can answer these, open **Notebook 01**.
"""

# ╔═╡ 0a000000-0000-0000-0000-00000000001e
md"""
---
## Mini exercise

**Exercise 00.1** — Modify the cell below so `inflation_adjusted` gives the real (inflation-adjusted) value of `nominal_gdp` after 8 quarters of **2% inflation per quarter**. Take the initial price level to be 1; the price level after eight quarters is `(1 + inflation_rate)^8`. This is a units exercise, not an economic forecast.
Then move the `inflation_rate` slider to see how the answer changes.
"""

# ╔═╡ 0a000000-0000-0000-0000-00000000001f
@bind inflation_rate PlutoUI.Slider(0.0:0.005:0.05, default=0.02, show_value=true)

# ╔═╡ 0a000000-0000-0000-0000-000000000020
begin
    nominal_gdp = 400.0   # € billion
    n_quarters = 8
    # TODO: replace the line below with the correct formula
    inflation_adjusted = nominal_gdp   # fix this!
end

# ╔═╡ 0a000000-0000-0000-0000-000000000021
Markdown.parse("Your real GDP: **$(round(inflation_adjusted, digits=2)) € bn**. Check: **$(isapprox(inflation_adjusted, nominal_gdp / (1 + inflation_rate)^n_quarters) ? "correct" : "revise the formula")**. At zero inflation it should equal nominal GDP; with positive inflation it should be lower.")

# ╔═╡ 0a000000-0000-0000-0000-000000000022
PlutoUI.details("Reveal the solution and interpretation", md"""
```julia
inflation_adjusted = nominal_gdp / (1 + inflation_rate)^n_quarters
```
Divide by the compounded **price level**, not by the inflation rate or the number of quarters. Annual and quarterly rates must not be mixed. With eight quarters of 2% inflation, the same nominal amount buys less than it did at the initial price level.

**Transfer exercise:** use `compound_growth` to turn a quarterly rate into an annual rate. Check that it is `(1 + rate)^4 - 1`, rather than exactly `4 * rate`.
""")

# ╔═╡ Cell order:
# ╟─0a000000-0000-0000-0000-000000000002
# ╠═0a000000-0000-0000-0000-000000000001
# ╟─0a000000-0000-0000-0000-000000000003
# ╠═0a000000-0000-0000-0000-000000000004
# ╟─0a000000-0000-0000-0000-000000000005
# ╠═0a000000-0000-0000-0000-000000000006
# ╟─0a000000-0000-0000-0000-000000000007
# ╠═0a000000-0000-0000-0000-000000000008
# ╟─0a000000-0000-0000-0000-000000000009
# ╠═0a000000-0000-0000-0000-00000000000a
# ╠═0a000000-0000-0000-0000-00000000000b
# ╟─0a000000-0000-0000-0000-00000000000c
# ╠═0a000000-0000-0000-0000-00000000000d
# ╠═0a000000-0000-0000-0000-00000000000e
# ╟─0a000000-0000-0000-0000-00000000000f
# ╟─0a000000-0000-0000-0000-000000000010
# ╠═0a000000-0000-0000-0000-000000000011
# ╠═0a000000-0000-0000-0000-000000000012
# ╟─0a000000-0000-0000-0000-000000000013
# ╟─0a000000-0000-0000-0000-000000000014
# ╠═0a000000-0000-0000-0000-000000000015
# ╟─0a000000-0000-0000-0000-000000000016
# ╠═0a000000-0000-0000-0000-000000000017
# ╠═0a000000-0000-0000-0000-000000000018
# ╟─0a000000-0000-0000-0000-000000000019
# ╟─0a000000-0000-0000-0000-00000000001a
# ╠═0a000000-0000-0000-0000-00000000001b
# ╠═0a000000-0000-0000-0000-00000000001c
# ╟─0a000000-0000-0000-0000-00000000001d
# ╟─0a000000-0000-0000-0000-00000000001e
# ╠═0a000000-0000-0000-0000-00000000001f
# ╠═0a000000-0000-0000-0000-000000000020
# ╟─0a000000-0000-0000-0000-000000000021
# ╟─0a000000-0000-0000-0000-000000000022
