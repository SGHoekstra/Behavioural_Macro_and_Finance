---
title: "Likelihood-free calibration: ABC, NPE, SNRE"
order: 6
tags: ["tutorial"]
layout: "md.jlmd"
---

# Notebook 05 — Likelihood-free calibration

**This notebook is run locally rather than rendered here.** Everything else on this
site has its output baked in; this one does not, for the reason below.

## What it covers

The CANVAS extension from Notebook 04 adds three pass-through coefficients that
Notebook 04 sets by hand. This notebook recovers them from data instead, without ever
writing down a likelihood:

- **ABC** — accept simulations whose trajectories fall within ε of the observation. The
  simplest likelihood-free method, and the least efficient.
- **NPE / SNPE-C** — train a normalising flow to approximate the posterior directly, so
  evaluating it is one forward pass.
- **SNRE-B** — train a classifier to estimate the likelihood *ratio*, then sample by MCMC.

It follows Dyer et al. (2024) and Wiese et al. (2023), and calls the Mackelab
[`sbi`](https://github.com/mackelab/sbi) package from Julia through PythonCall.

## Running it

```
cd pluto_tutorial
julia setup.jl
julia -t auto -e 'using Pluto; Pluto.run()'
```

then open `05_likelihood_free_calibration.jl`. On first run it pulls a Python
environment (`sbi`, torch) of a few hundred megabytes, and a full pass takes roughly
25 minutes. It has been verified end to end at the shipped simulation budget.

## Why it is not rendered

Inside the site build on Linux, `torch` loads `pyexpat`, which must bind to conda's
`libexpat`. Plots reaches Julia's `Expat_jll` through GR and Cairo, and because the
Linux dynamic linker resolves symbols globally, `pyexpat` can bind to the wrong one and
fail with `undefined symbol: XML_SetHashSalt16Bytes`.

The same import order succeeds in a plain Julia process on the same runner, so this is
specific to the notebook worker rather than to the notebook. Rather than publish a page
with a live `ImportError` on it, the notebook ships as source.
