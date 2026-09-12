---
layout: "md.jlmd"
---

# Behavioural Macro and Finance

Agent-based models of the macroeconomy, taught with
[BeforeIT.jl](https://github.com/bancaditalia/BeforeIT.jl) — the Julia implementation of
the Poledna et al. macro ABM, calibrated on Austrian and Italian national accounts.

The course is two lectures and a five-part tutorial. The lectures set up the theory; the
notebooks build the model from a standing start, one mechanism at a time, and end with
likelihood-free calibration of a model extension.

## Start here

- **[Lecture slides](lectures/)** — both decks as PDF.
- **[Running the notebooks](installation/)** — install Julia and Pluto, or just read online.
- **Tutorial** — five notebooks in the sidebar, in order, plus an optional Julia primer.

## What the tutorial covers

**00 — Julia + Pluto primer.** Optional; skip it if you already write Julia.

**01 — Meet the model.** Run the Austrian economy forward and read off GDP, then open the
box: the agent types and their counts, the input–output network, what happens inside a
quarter, and whether the stock-flow accounting closes.

**02 — Calibration, no-burn-in and forecasting.** Where the parameters come from, the
model's unusual ability to run from t=0 without a spin-up, and what that buys you — fan
charts, and a benchmark against an AR(1).

**03 — Shocks, expectations and policy.** The five exogenous AR(1) processes, bankruptcy
cascades propagating through the production network, and how expectation formation and the
Taylor rule change the response.

**04 — Extending the model: CANVAS.** Add a wage–price spiral by overriding a single
function, and trace the pass-through channels.

**05 — Likelihood-free calibration.** Recover that extension's parameters from data with
ABC, NPE and SNRE. This one needs a Python environment and takes a while.

Every notebook names the Lecture 2 slides it covers, and ends with exercises.

> **Acknowledgement** \\
> The design of this website is based on _**Computational Thinking**, a live online Julia/Pluto textbook._ [(computationalthinking.mit.edu)](https://computationalthinking.mit.edu)
