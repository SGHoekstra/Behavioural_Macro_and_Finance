---
title: "Running inference exercises"
order: 3
tags: ["start"]
layout: "md.jlmd"
---

# Running Notebook 05 inference exercises

**[Read the full notebook online](https://sghoekstra.github.io/Behavioural_Macro_and_Finance/notebooks/05_likelihood_free_calibration/).**
It displays its explanations, code, exercises and **saved figures from an actual
default run**: the synthetic observation and the ABC, NPE and NRE-B results. The online
controls do not rerun the experiment. This guide explains
how to run its simulations and neural training in a local Julia/Python environment,
generate posterior draws and inspect how well the coefficients are recovered.

[Open the notebook source](https://github.com/SGHoekstra/Behavioural_Macro_and_Finance/blob/main/pluto_tutorial/05_likelihood_free_calibration.jl)

## The question

In Notebook 04, you chose how strongly CANVAS firms pass demand, costs and expected
inflation into their prices. Can inflation and GDP growth reveal those three
coefficients instead?

Notebook 05 uses a **known-truth recovery experiment**. It generates a synthetic
observation at chosen coefficients, then gives the estimator only the observation.
The true coefficients provide a reference for interpreting the inferred distribution.
All other model parameters and the pricing mechanism remain fixed.

Before running, predict which pricing channel could be hardest to distinguish from
the others using just two aggregate series.

## Three ways to infer the coefficients

| Method | What it does | What to inspect |
|---|---|---|
| **ABC** | Draw coefficients from the prior, simulate data, retain draws close to the observation | Distance definition, tolerance and accepted count |
| **NPE** | Train a conditional density of coefficients given simulated outputs | Network fit, posterior shape and parameter correlations |
| **NRE-B** | Train a contrastive classifier to estimate a likelihood-to-evidence ratio, combine it with the prior and sample with MCMC | Network fit, chain mixing and effective sample size |

The executable example runs **one prior-sampled round** of each neural method. It uses
engines that can also run sequentially; calling an engine “SNPE” or “SNRE” does not
by itself add a second simulation round. The optional sequential exercise focuses
new simulations on the current posterior and explains why NPE needs a proposal
correction.

A sharper histogram is not automatically a better posterior. Weak identification,
network error and a misspecified simulator can all affect the result.

## Run in stages

After cloning the course repository, follow the installation page and run:

```bash
cd Behavioural_Macro_and_Finance/pluto_tutorial
julia setup.jl
julia -t auto -e 'using Pluto; Pluto.run()'
```

Open `05_likelihood_free_calibration.jl` in Pluto. Opening the notebook starts in
**reading mode**: saved results and their plots are available, while new simulation
and training stages are disabled. Enabling the local
environment may install Python, PyTorch and `sbi` on first use.

1. **Enable the local environment.** Read the observation protocol and small-budget settings.
2. **Generate the synthetic observation.** Twelve quarterly inflation rates and twelve growth rates form a 24-value vector.
3. **Generate the ABC bank, optionally.** Move its tolerance slider to reuse the stored distances without new ABM runs.
4. **Generate the neural training bank.** Inspect the coefficient/output matrix dimensions and any failed simulations.
5. **Train NPE.** Interpret all three marginals and inspect their joint relationships.
6. **Train NRE-B, optionally.** It reuses the neural bank and samples using MCMC.

The default experiment uses **four simulated paths per output**, **100 ABC parameter
draws** and **200 neural training draws**. NPE draws 1,000 approximate posterior
samples; the optional NRE run draws 200 MCMC samples. These are teaching budgets,
not an accuracy guarantee. Runtime varies by computer; start with the defaults
before increasing the cost.

## Match the observation to the simulator

The synthetic observation and every training output use the same horizon, units,
four-path averaging and data transformations, with distinct seeds. Coefficient draws
use a separate random-number generator from the economy simulations.

This averaged observation is an idealised experiment. An empirical application must
specify how data from one economy, measurement errors and transformations enter the
observation model. Changing the observation protocol requires changing training too.
Failed or non-finite simulations block neural fitting rather than being silently
removed from the estimation sample.

## Recovery, diagnostics and validation

- **Recovery** asks whether inference locates chosen coefficients in data from the same simulator.
- **Inference calibration** checks posterior probabilities across repeated held-out synthetic experiments.
- **Posterior prediction** asks whether posterior draws reproduce observed or additional features.
- **Model and policy validation** require independent data, alternative mechanisms or intervention responses.

A same-model recovery exercise cannot establish that the model represents the real
economy or predicts a policy intervention reliably. Even good prediction of the two
fitted series can leave different pricing mechanisms observationally similar.

## Exercises to start with

The full notebook gives six exercises with hints. Begin with the two that need no
new economy simulations: vary the ABC tolerance and plot cost-push versus expectation
coefficients from the NPE draws. Then compare a coarser data representation, generate
a small posterior-predictive sample, discuss a misspecification test, or attempt a
second sequential round.

For background, see Dyer et al. (2024),
[*Black-Box Bayesian Inference for Agent-Based Models*](https://doi.org/10.1016/j.jedc.2024.104827),
and the official [`sbi` Bayesian workflow](https://sbi.readthedocs.io/en/latest/tutorials/01_Bayesian_workflow.html)
and [sequential-inference guide](https://sbi.readthedocs.io/en/latest/how_to_guide/02_multiround_inference.html).
