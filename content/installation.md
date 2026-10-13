---
title: "Running the notebooks"
order: 2
tags: ["start"]
layout: "md.jlmd"
---

# Running the notebooks

Notebooks 00–04 and the cheatsheet have their output already computed, so you can
read them without installing anything. These are saved examples: online controls do not
rerun the model. To change inputs and run exercises, open the notebooks locally in Pluto.
Notebook 05 is also available online in reading mode, with explanations, code and
exercises. To generate observations and fit the neural estimators, run it locally
with Julia and Python; follow the [inference setup guide](https://sghoekstra.github.io/Behavioural_Macro_and_Finance/notebook05/).

## Requirements

**Julia 1.12 or later** — install it with [juliaup](https://github.com/JuliaLang/juliaup).
The committed `Manifest.toml` was resolved on 1.12.1; on an older Julia, delete it and
let `Pkg.instantiate()` re-resolve, which loses exact version pinning.

Notebook 05 additionally pulls a Python environment (`sbi`) through PythonCall/CondaPkg
on first run — a few hundred megabytes. Notebooks 00–04 are pure Julia.

## Setup

Clone the repository, then run this once:

```bash
git clone https://github.com/SGHoekstra/Behavioural_Macro_and_Finance.git
cd Behavioural_Macro_and_Finance/pluto_tutorial
julia setup.jl
```

That installs Pluto into your global Julia environment and every tutorial package into
the shared `pluto_tutorial` environment. Then launch Pluto:

```
julia -t auto -e 'using Pluto; Pluto.run()'
```

Open any notebook from the Pluto file browser. Each notebook activates the shared
environment itself, so the same package versions are used throughout. The first
opening can still compile packages and functions; allow it to finish before changing
controls. Keep the terminal running while you use Pluto.

## Order

Work through 01 to 05 in sequence — each assumes the previous ones. 00 is an optional Julia
and Pluto primer, and `cheatsheet.jl` is a standalone reference to keep open in a second
tab. Exercises and interpretation checks are at the bottom of each notebook. Use fresh
variable names in your exercise cells; Pluto allows one defining cell per global
variable. Prefer **Apply settings** controls for expensive examples so changing several
inputs launches one new calculation rather than a sequence of reruns.

Notebook 05 uses staged run controls and small demonstration budgets. Installing
its Python environment and increasing simulation or training budgets can take
considerably longer. Follow its guide before launching a full inference exercise.

## A useful workflow

1. Read the question and predict a result before running the example.
2. Record the calibration, seed, horizon and measurement units.
3. Change one setting or mechanism at a time and compare like with like.
4. Explain the result economically, including one assumption that limits the conclusion.
5. Complete a core exercise before moving to the advanced extension.

If a run appears slow, check Pluto's running-cell indicator and the terminal before
launching another simulation. Start with the supplied defaults. Restarting Pluto is
useful after changing a model type or its methods, because those definitions can
persist within the Julia process.
