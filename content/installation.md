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

Notebook 05 additionally pulls a Python environment (`sbi`) through PythonCall/CondaPkg
on first run — a few hundred megabytes. Notebooks 00–04 are pure Julia.

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

Work through 01 to 05 in sequence — each assumes the previous ones. 00 is an optional Julia
and Pluto primer, and `cheatsheet.jl` is a standalone reference to keep open in a second
tab. Exercises are at the bottom of each notebook.

Notebook 05 is the heavy one: it pulls the Python `sbi` environment and takes roughly
20 minutes to run through. Notebooks 01–04 are pure Julia.
