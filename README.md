# Behavioural Macro and Finance

Course material for **Behavioural Macro and Finance** (University of Amsterdam).
Agent-based macroeconomics with [BeforeIT.jl](https://github.com/bancaditalia/BeforeIT.jl) —
the Julia implementation of the Poledna et al. macro ABM.

**[Read the course online](https://sghoekstra.github.io/Behavioural_Macro_and_Finance/)**
· **[Lecture slides](https://sghoekstra.github.io/Behavioural_Macro_and_Finance/lectures/)**

## Lecture slides

| | Topic | Slides |
|---|---|---|
| Lecture 1 | Introduction to agent-based models | [Read PDF](https://sghoekstra.github.io/Behavioural_Macro_and_Finance/assets/lectures/lecture_1_intro_abm.pdf) |
| Lecture 2 | Stock-flow consistent ABMs | [Read PDF](https://sghoekstra.github.io/Behavioural_Macro_and_Finance/assets/lectures/lecture_2_sfc_abm.pdf) |

LaTeX sources sit alongside each PDF.

## Pluto tutorial

Six numbered [Pluto](https://plutojl.org) notebooks (00–05), including an optional
Julia primer, build up the Lecture 2 model from a standing start. A standalone
cheatsheet accompanies the sequence. Read notebooks 00–04 and the cheatsheet online;
notebook 05 has an overview page and runs locally.

### Requirements

- **Julia 1.12 or later.** Install via [juliaup](https://github.com/JuliaLang/juliaup).
  The committed `Manifest.toml` was resolved on 1.12.1; on an older Julia, delete
  it and let `Pkg.instantiate()` re-resolve (you lose exact version pinning).
- Notebook 05 additionally pulls a Python environment (`sbi`) through
  PythonCall/CondaPkg on first run — a few hundred MB. Notebooks 00–04 are pure Julia.

### Setup

Run once:

```bash
cd pluto_tutorial
julia setup.jl
```

This installs Pluto globally and every tutorial package into the shared
`pluto_tutorial` environment. Then launch:

```bash
julia -t auto -e 'using Pluto; Pluto.run()'
```

Open any notebook from the Pluto file browser. Every notebook activates the
shared environment itself, so package versions are shared across notebooks. Initial package
and function compilation can still take time; keep the terminal running.

### Notebooks

| | Notebook source | Read online | Covers |
|---|---|---|---|
| 00 | [00_julia_pluto_primer.jl](pluto_tutorial/00_julia_pluto_primer.jl) | [Read online](https://sghoekstra.github.io/Behavioural_Macro_and_Finance/notebooks/00_julia_pluto_primer/) | *Optional* — Julia syntax, structs, multiple dispatch, Pluto's reactivity model |
| 01 | [01_meet_the_model.jl](pluto_tutorial/01_meet_the_model.jl) | [Read online](https://sghoekstra.github.io/Behavioural_Macro_and_Finance/notebooks/01_meet_the_model/) | Run the Austria 2010:Q1 calibration, then open it up: agents, the input–output network, the quarter sequence, stock-flow consistency |
| 02 | [02_calibration_and_forecasting.jl](pluto_tutorial/02_calibration_and_forecasting.jl) | [Read online](https://sghoekstra.github.io/Behavioural_Macro_and_Finance/notebooks/02_calibration_and_forecasting/) | Parameter tables and balance sheets, the no-burn-in property, Austria vs Italy, fan charts and an AR(1) benchmark |
| 03 | [03_shocks_expectations_policy.jl](pluto_tutorial/03_shocks_expectations_policy.jl) | [Read online](https://sghoekstra.github.io/Behavioural_Macro_and_Finance/notebooks/03_shocks_expectations_policy/) | The five AR(1) shock processes, bankruptcy cascades, non-linear responses, expectation formation and the Taylor rule |
| 04 | [04_extensions_canvas.jl](pluto_tutorial/04_extensions_canvas.jl) | [Read online](https://sghoekstra.github.io/Behavioural_Macro_and_Finance/notebooks/04_extensions_canvas/) | *Advanced* — extending the model with a CANVAS wage–price spiral |
| 05 | [05_likelihood_free_calibration.jl](pluto_tutorial/05_likelihood_free_calibration.jl) | [Overview and local setup](https://sghoekstra.github.io/Behavioural_Macro_and_Finance/notebook05/) | *Advanced* — calibrating that extension: ABC, NPE and SNRE. Needs Python (`sbi`); run locally, not rendered on the site |

The cheatsheet is a standalone reference, not part of the sequence:
[read online](https://sghoekstra.github.io/Behavioural_Macro_and_Finance/notebooks/cheatsheet/)
or [open the source](pluto_tutorial/cheatsheet.jl).
`canvas_model.jl` is not a notebook — it holds the CANVAS extension that notebooks 04 and
05 share, so the model is defined once rather than restated in both.

Work through 01 to 05 in order — each assumes the previous ones. Exercises are at the
bottom of each notebook.

## Learning route

- **Core:** 01 → 02 → 03. Run and inspect a calibrated economy, evaluate forecasts, then compare interventions and expectations. Start with 00 if Julia or Pluto is new to you.
- **Advanced:** 04 → 05. Change a behavioural mechanism, then learn how simulation-based inference estimates its parameters and what parameter recovery can establish.
- **Reference:** keep the cheatsheet open alongside your notebook.

For each notebook, predict an effect, run the default example, change one setting,
and explain a figure in economic terms. Record units, the calibration date, the seed
and horizon. The guided exercises include starter code, hints or checks; use distinct
variable names when adding exercise cells in Pluto.

The online pages contain saved output rather than a live simulation service. Expensive
controls use confirmation to batch settings; notebook 05 additionally separates simulation
and training into stages. Small defaults support learning, not precise policy estimates.

## Branches

- `main` — current course material.
- `archive-2024` — the 2024 version of the course, preserved deliberately. It was
  built as a PlutoPages site, so its layout differs from this branch.
- `output` — build output deployed from `archive-2024`. Generated, not edited by hand.
