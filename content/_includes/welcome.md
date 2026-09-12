---
layout: "md.jlmd"
---

# Behavioural Macro and Finance

Agent-based models of the macroeconomy, taught with
[BeforeIT.jl](https://github.com/bancaditalia/BeforeIT.jl) — the Julia implementation of
the Poledna et al. macro ABM, calibrated on Austrian and Italian national accounts.

The course is two lectures and a nine-notebook tutorial. The lectures set up the theory;
the notebooks build the model from a standing start, one mechanism at a time, and end
with likelihood-free calibration of a model extension.

## Start here

- **[Lecture slides](/lectures/)** — both decks as PDF.
- **[Running the notebooks](/installation/)** — install Julia and Pluto, or just read online.
- **Tutorial** — nine notebooks in the sidebar, in order.

## What the tutorial covers

Notebook 00 is a Julia and Pluto primer; skip it if you already write Julia. From 01 you
run the Austrian economy forward and read off GDP. By 02 you are inspecting the agents and
checking that the stock-flow accounting closes. 03 covers calibration and the model's
unusual no-burn-in property. 04 fires shocks and watches bankruptcy cascades propagate
through the input–output network. 05 swaps out expectation formation and the Taylor rule.
06 builds fan charts and benchmarks against an AR(1). 07 extends the model with a CANVAS
wage–price spiral, and 08 calibrates that extension with ABC, NPE and SNRE.

Every notebook names the Lecture 2 slides it covers, and ends with exercises.

> **Acknowledgement** \\
> The design of this website is based on _**Computational Thinking**, a live online Julia/Pluto textbook._ [(computationalthinking.mit.edu)](https://computationalthinking.mit.edu)
