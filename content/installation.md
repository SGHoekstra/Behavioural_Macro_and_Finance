---
title: "Running the notebooks"
order: 2
tags: ["start"]
layout: "md.jlmd"
---

# Running the notebooks

Every notebook on this site is rendered with its output already computed, so you can
read straight through without installing anything. To move the sliders and change the
model you need Julia.

## Requirements

**Julia 1.12 or later** — install it with [juliaup](https://github.com/JuliaLang/juliaup).
The committed `Manifest.toml` was resolved on 1.12.1; on an older Julia, delete it and
let `Pkg.instantiate()` re-resolve, which loses exact version pinning.

Notebook 08 additionally pulls a Python environment (`sbi`) through PythonCall/CondaPkg
on first run — a few hundred megabytes. Notebooks 00–07 are pure Julia.

## Setup

Clone the repository, then run this once:

```
cd pluto_tutorial
julia setup.jl
```

That installs Pluto into your global Julia environment and every tutorial package into
the shared `pluto_tutorial` environment. Then launch Pluto:

```
julia -t auto -e 'using Pluto; Pluto.run()'
```

Open any notebook from the Pluto file browser. Each notebook activates the shared
environment itself, so there is nothing to precompile per notebook.

## Order

Work through 00 to 08 in sequence — each assumes the previous ones. `cheatsheet.jl` is a
standalone reference; keep it open in a second tab. Exercises are at the bottom of each
notebook.
