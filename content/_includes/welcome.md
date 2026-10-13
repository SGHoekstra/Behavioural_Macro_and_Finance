---
layout: "md.jlmd"
---

# Behavioural Macro and Finance

Agent-based models of the macroeconomy, taught with
[BeforeIT.jl](https://github.com/bancaditalia/BeforeIT.jl) — the Julia implementation of
the Poledna et al. macro ABM, calibrated on Austrian and Italian national accounts.

The course combines two lectures with five tutorials and an optional Julia primer.
The notebooks move from inspecting a calibrated economy to comparing interventions,
extending the model and estimating its parameters. Each lesson asks you to predict an
outcome, run a controlled experiment and explain what the result establishes.

## Start here

- **[Lecture slides](lectures/)** — both decks as PDF.
- **[Running the notebooks](installation/)** — install Julia and Pluto, or just read online.
- **Core route: tutorials 01–03** — understand the model, assess forecasts and compare policy responses.
- **Advanced route: tutorials 04–05** — build an extension and investigate likelihood-free inference.

Read the saved notebook outputs online, or run the source notebooks locally to change
parameters. Tutorial 05 has an online guide; its inference experiments run locally.

## What the tutorial covers

**00 — Julia + Pluto primer.** Optional; skip it if you already write Julia.

**01 — Meet the model.** Run the Austrian economy forward and read off GDP, then open the
box: the agent types and their counts, the input–output network, what happens inside a
quarter, and whether the stock-flow accounting closes.

**02 — Calibration, no-burn-in and forecasting.** Identify data-based estimates and
policy assumptions, inspect initialization without a burn-in, and compare indexed model
paths with a simple benchmark. Interpret simulation bands and distinguish dispersion
across paths from evidence of forecasting accuracy.

**03 — Shocks, expectations and policy.** Compare shocks with matched baselines using
the same random seeds. Interpret output, consumption, wages and interest rates, then
investigate how expectations and the euro-area monetary policy rule affect the response.

**04 — Extending the model: CANVAS.** Implement a CANVAS-inspired pricing extension,
apply a persistent wage-norm intervention and vary pass-through channels. Compare each
configuration with its own baseline and interpret price levels and cumulative inflation.

**05 — Likelihood-free calibration.** Estimate the extension's parameters from simulated
observations with ABC, NPE and optional NRE. Work through parameter recovery, posterior
checks and the limits of these experiments for empirical and policy validation. Reading
mode is lightweight; inference requires a local Python environment, and runtime depends
on the simulation budget and hardware.

The tutorials connect to the lecture material and include guided exercises with hints
and diagnostic checks. Record the seed, horizon, units and baseline for each experiment.

> **Acknowledgement** \\
> The design of this website is based on _**Computational Thinking**, a live online Julia/Pluto textbook._ [(computationalthinking.mit.edu)](https://computationalthinking.mit.edu)
