# Behavioural Macro and Finance

Course material for **Behavioural Macro and Finance** (University of Amsterdam).
Agent-based macroeconomics with [BeforeIT.jl](https://github.com/bancaditalia/BeforeIT.jl) —
the Julia implementation of the Poledna et al. macro ABM.

## Lecture slides

| | Topic | Slides |
|---|---|---|
| Lecture 1 | Introduction to agent-based models | [`lecture_1_intro_abm/main.pdf`](lecture_1_intro_abm/main.pdf) |
| Lecture 2 | Stock-flow consistent ABMs | [`lecture_2_sfc_abm/lecture.pdf`](lecture_2_sfc_abm/lecture.pdf) |

LaTeX sources sit alongside each PDF.

## Pluto tutorial

Nine interactive [Pluto](https://plutojl.org) notebooks that build up the
Lecture 2 model from a standing start.

### Requirements

- **Julia 1.12 or later.** Install via [juliaup](https://github.com/JuliaLang/juliaup).
  The committed `Manifest.toml` was resolved on 1.12.1; on an older Julia, delete
  it and let `Pkg.instantiate()` re-resolve (you lose exact version pinning).
- Notebook 08 additionally pulls a Python environment (`sbi`) through
  PythonCall/CondaPkg on first run — a few hundred MB. Notebooks 00–07 are pure Julia.

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
shared environment itself, so there is nothing to precompile per notebook.

### Notebooks

| | Notebook | Covers |
|---|---|---|
| 00 | `00_julia_pluto_primer.jl` | Julia syntax, structs, multiple dispatch, Pluto's reactivity model |
| 01 | `01_quickstart.jl` | Load the Austria 2010:Q1 calibration, run the model, Monte Carlo fan chart |
| 02 | `02_model_anatomy.jl` | Agents, the input–output network, the quarter sequence, stock-flow consistency checks |
| 03 | `03_calibration_and_data.jl` | Parameter tables, initial balance sheets, Austria vs Italy |
| 04 | `04_shocks_and_cascades.jl` | The five AR(1) shock processes, bankruptcy cascades, non-linear responses |
| 05 | `05_expectations_and_policy.jl` | Expectation formation, the Taylor rule, fiscal closure |
| 06 | `06_forecasting.jl` | Fan charts, an AR(1) benchmark, forecast validation |
| 07 | `07_extensions_canvas.jl` | *Advanced* — extending the model with a CANVAS wage–price spiral |
| 08 | `08_snpe_calibration.jl` | *Advanced* — likelihood-free calibration: ABC, NPE and SNRE |

`cheatsheet.jl` is a standalone reference, not part of the sequence.

Work through them in order — each assumes the previous ones. Exercises are at
the bottom of each notebook.

## Branches

- `main` — current course material.
- `archive-2024` — the 2024 version of the course, preserved deliberately. It was
  built as a PlutoPages site, so its layout differs from this branch.
- `output` — build output deployed from `archive-2024`. Generated, not edited by hand.
