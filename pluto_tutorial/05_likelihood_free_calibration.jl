### A Pluto.jl notebook ###
# v0.20.24
# Saved demo SHA256: 5141b65e8e817f1df4a0675e9ca1fcea524a6be3a381ebf79b76d2e804006b88

#> [frontmatter]
#> order = 6
#> title = "Likelihood-free calibration: ABC, NPE, SNRE"
#> layout = "layout.jlhtml"
#> tags = ["tutorial"]

using Markdown
using InteractiveUtils

# This Pluto notebook uses @bind for interactivity. When running this notebook outside of Pluto, the following 'mock version' of @bind gives bound variables a default value (instead of an error).
macro bind(def, element)
    #! format: off
    return quote
        local iv = try Base.loaded_modules[Base.PkgId(Base.UUID("6e696c72-6542-2067-7265-42206c756150"), "AbstractPlutoDingetjes")].Bonds.initial_value catch; b -> missing; end
        local el = $(esc(element))
        global $(esc(def)) = Core.applicable(Base.get, el) ? Base.get(el) : iv(el)
        el
    end
    #! format: on
end

# ╔═╡ fe46785c-aeb2-11f1-b29c-f9f57fb156bb
md"""
# Notebook 05 — Likelihood-free calibration *(advanced)*

> **Question:** can inflation and GDP growth tell us how strongly CANVAS firms pass demand, cost and expectation changes into prices?

Work through Notebook 04 first. Here, the pricing rule stays fixed and its three pass-through coefficients become unknown. We use a **known-truth recovery experiment**: simulate observations at chosen coefficients, hide those coefficients from the estimator, and see what the data can recover.

### Route through the notebook
1. Define the unknown parameters, prior and observation protocol.
2. Build one simulator and generate a synthetic observation.
3. Use **ABC** to retain parameter draws that reproduce similar data.
4. Reuse simulated parameter–data pairs for **NPE** and **NRE-B**.
5. Separate parameter recovery, inference diagnostics and model validation.

The code runs **one round** of each neural method. The `sbi` engines also support sequential inference; an optional exercise explains what a second round changes.

**Read online, run locally:** the website displays the explanations, code and **saved figures from a real run of the default experiment**: the synthetic observation, ABC, NPE and NRE-B. Simulations and training are disabled online; changing controls requires opening the notebook locally. Follow the [local setup guide](https://sghoekstra.github.io/Behavioural_Macro_and_Finance/notebook05/), enable the environment below, then press the numbered buttons in order. First-time Python setup may download packages; subsequent stages can take several minutes depending on your computer.

**Before running:** predict which coefficient could be hardest to identify from two aggregate series. What would a broad posterior mean?
"""

# ╔═╡ fe47a376-aeb2-11f1-b61a-afb43896f469
begin
    import Pkg
    Pkg.activate(dirname(@__FILE__))
    import BeforeIT as Bit
    using PlutoUI, Statistics, Distributions, LinearAlgebra, Random, Dates, JLD2, SHA
end


# ╔═╡ f0050000-0000-4000-8000-000000000001
md"""
**Enable local Python simulations and training:** $(@bind enable_inference PlutoUI.CheckBox(default=false))

Leave this unchecked to read the explanations and saved results. Check it when ready to rerun the experiment; initialise the observation before starting ABC or neural inference.
"""

# ╔═╡ f0050000-0000-4000-8000-000000000002
begin
    python_ready = if enable_inference
        # Load Python's XML extension before the plotting stack, so pyexpat
        # binds conda's Expat library rather than Julia's older version.
        # Keep imports behind runtime evaluation: Pluto's import discovery
        # would otherwise load these modules even in reading mode.
        @eval import PythonCall
        PythonCall.pyimport("pyexpat")
        PythonCall.pyimport("torch")
        @eval import Plots
        true
    else
        false
    end
    python_ready ? md"Local environment loaded. Continue to the observation button in Section 4." :
        md"Reading mode: figures use a saved default run. Python setup, new simulations and training are disabled."
end

# ╔═╡ fe47a3e4-aeb2-11f1-8672-87cfc7b65656
md"""
---
## 1 — What is missing from ordinary Bayesian inference?

Bayes' rule combines a prior with the likelihood:

$$p(\theta \mid x_{\mathrm{obs}}) \propto p(x_{\mathrm{obs}} \mid \theta)\,p(\theta).$$

The **prior** describes plausible coefficients before these observations. The **likelihood** measures how plausible the observed data are under a particular coefficient vector. The **posterior** updates the prior using that likelihood.

We can run the stochastic ABM to generate $x$ at a chosen $\theta$, but cannot evaluate its likelihood directly. Standard likelihood-based MCMC and variational inference therefore need an alternative target. SBI constructs an approximation using repeated simulations. MCMC can still be used later, on an estimated likelihood ratio.

**Pause and check:** an ABM run gives one possible trajectory. Does that tell us the probability density of the observed trajectory? Explain why simulation and likelihood evaluation are different tasks.
"""

# ╔═╡ fe47a3f8-aeb2-11f1-bb78-fdae608fd8dd
md"""
---
## 2 — Specify the statistical experiment first

The unknown coefficients are

$$\theta=(\phi^{DP},\phi^{CP},\phi^{AE})\in[0,1]^3.$$

| Field in Julia | Pricing channel | Meaning of a larger value |
|---|---|---|
| `dp` | Demand pull | Stronger response to the firm's excess-demand price signal |
| `cp` | Cost push | Stronger response to the cost-inflation signal |
| `ae` | Aggregate expectations | Stronger response to expected inflation |

We use independent uniform priors on these three intervals. All other parameters, initial conditions and the pricing mechanism are held fixed. The resulting posterior is **conditional on these choices**; it does not include uncertainty about every ABM parameter or about the mechanism itself.

One simulator output contains $T$ quarterly GDP-deflator inflation rates followed by $T$ real-GDP growth rates. Each rate is averaged over `N_paths` simulated economies. Thus $x$ has length $2T$ and is a summary of an ensemble, rather than a complete ABM state.

**Match observations to simulations:** the synthetic observation uses the same horizon, units, averaging and number of paths as every training example, with a separate seed. Averaging discards cross-path variation. For an empirical application, specify how one observed economy, measurement errors and data transformations are represented by the simulator; an average of simulated economies is not a substitute for that observation model.
"""

# ╔═╡ fe47a416-aeb2-11f1-9746-851acfeb8207
begin
    # Small population and demonstration budgets: enough to practise the
    # workflow, not a claim of accurate posterior coverage.
    parameters, init_cond = Bit.get_params_and_initial_conditions(
        Bit.ITALY_CALIBRATION, DateTime(2010, 3, 31); scale=0.0001)
    θ_true = (dp=0.2, cp=0.5, ae=0.7)
    T_sim = 12
    N_paths = 4
    N_obs = N_paths  # same observation distribution as the training simulator
    N_abc = 1000
    N_sbi = 2000
    N_npe_draws = 5000
    N_nre_draws = 2000
    ABC_accept_fraction = 0.10
    N_diagnostic_observations = 50
    N_predictive_draws = 50
    "Setup: $(round(Int, sum(parameters["I_s"]))) firms; T=$(T_sim), $(N_paths) paths per output. Synthetic truth: $(θ_true)."
end

# ╔═╡ f0050000-0000-4000-8000-000000000004
begin
    loaded_demo = JLD2.load(joinpath(@__DIR__, "notebook05_demo.jld2"))
    demo_matches = (loaded_demo["θ_true"], loaded_demo["T_sim"], loaded_demo["N_paths"],
                    loaded_demo["N_abc"], loaded_demo["N_sbi"]) ==
                   (θ_true, T_sim, N_paths, N_abc, N_sbi)
    demo_matches &= loaded_demo["metadata"]["canvas_sha256"] ==
        bytes2hex(SHA.sha256(read(joinpath(@__DIR__, "canvas_model.jl"))))
    demo_matches &= get(loaded_demo, "N_npe_draws", 0) == N_npe_draws &&
                    get(loaded_demo, "N_nre_draws", 0) == N_nre_draws &&
                    get(loaded_demo, "ABC_accept_fraction", 0) == ABC_accept_fraction &&
                    get(loaded_demo, "N_diagnostic_observations", 0) == N_diagnostic_observations &&
                    get(loaded_demo, "N_predictive_draws", 0) == N_predictive_draws
    saved_demo = demo_matches ? loaded_demo : nothing
    demo_epsilon = demo_matches ? loaded_demo["ε"] : nothing
    demo_accepted = demo_matches ? count(d -> d < demo_epsilon, loaded_demo["abc_bank"].distances) : 0
    demo_matches ?
        md"**Saved demonstration:** $(N_abc) ABC draws, $(N_sbi) neural training pairs, $(N_paths) paths per output. The figures show one small-budget recovery experiment, not a comparison of method accuracy. Enable local execution to replace these results with new runs." :
        md"The settings or pricing rule differ from the saved demonstration. Enable local execution and run the numbered stages to generate matching results; the old figures are hidden."
end

# ╔═╡ fe47a420-aeb2-11f1-8d8a-abc5ec0d8da6
md"""
---
## 3 — Build the bridge from coefficients to data

Read `summarise` in four steps:

1. Set the three pricing coefficients and reset the simulation seed.
2. Build fresh CANVAS economies and run each for `T` quarters.
3. Compute percentage changes from GDP levels and deflators.
4. Average the rates across paths and concatenate `[inflation; gdp_growth]`.

The output is in **fractions**, so `0.01` means 1% quarterly growth. Plotting multiplies by 100; estimation uses the fractions. Fresh models prevent one parameter draw from inheriting the final state of another.

`parallel=false` makes this small example reproducible with a single seeded random stream. Parameter draws use a separate RNG. The shared `CANVAS_PHI` reference means that calls at different coefficients must run serially.
"""

# ╔═╡ fe47a436-aeb2-11f1-9b2a-3f8bba375ef7
begin
    include(joinpath(@__DIR__, "canvas_model.jl"))
    "Shared CANVAS pricing rule and model builder loaded."
end

# ╔═╡ fe47a43e-aeb2-11f1-8236-cf09de2a48a6
begin
    function summarise(θ; seed=1, N=N_paths, T=T_sim, p=parameters, ic=init_cond)
        keys(θ) == (:dp, :cp, :ae) || throw(ArgumentError("Use (dp=..., cp=..., ae=...)."))
        all(v -> isfinite(v) && 0 <= v <= 1, values(θ)) ||
            throw(ArgumentError("Pass-through coefficients must be finite and in [0,1]."))
        N >= 1 && T >= 1 || throw(ArgumentError("N and T must be positive."))
        CANVAS_PHI[] = θ
        Random.seed!(seed)
        ms = Bit.ensemblerun!((build_canvas_model(p, ic) for _ in 1:N), T;
                             parallel=false)
        deflator(m) = m.data.nominal_gdp ./ m.data.real_gdp
        inflation = mean([diff(deflator(m)) ./ deflator(m)[1:end-1] for m in ms])
        gdp_growth = mean([diff(m.data.real_gdp) ./ m.data.real_gdp[1:end-1] for m in ms])
        x = vcat(inflation, gdp_growth)
        length(x) == 2T || error("Expected 2T rates. Check t=0 data collection in the model builder.")
        all(isfinite, x) || error("Non-finite output: investigate the simulation before fitting.")
        return x
    end
    "Simulator defined: NamedTuple coefficients → a finite vector of 2T rates."
end

# ╔═╡ fe47a448-aeb2-11f1-8128-47d32eec72fc
md"""
---
## 4 — Create the held-out synthetic observation

Press the button once. Seed `42` belongs only to this observation; ABC and neural training use different seeds. The estimator will see `x_obs`, not `θ_true`. The red lines in later figures reveal the truth to us for interpretation.

**Read the plots:** are these rates or levels? Which quarters seem most informative about the pricing response? One recovered coefficient vector at one seed is a useful smoke check, not evidence of calibrated uncertainty or empirical validity.
"""

# ╔═╡ fe47a45c-aeb2-11f1-8796-d9a46d0f705f
@bind run_xobs PlutoUI.CounterButton("1 — Generate the synthetic observation")

# ╔═╡ fe47a470-aeb2-11f1-b509-5733fe3f376e
begin
    x_obs = if python_ready && run_xobs > 0
        summarise(θ_true; seed=42, N=N_obs)
    else
        saved_demo === nothing ? nothing : saved_demo["x_obs"]
    end
    T_obs = T_sim
    if !python_ready && saved_demo !== nothing
        PlutoUI.LocalResource(joinpath(@__DIR__, "notebook05_figures", "observation.png"))
    elseif x_obs === nothing
        md"Enable the local environment and press button 1 to generate the observation."
    else
        p_infl = Plots.plot(1:T_obs, x_obs[1:T_obs] .* 100,
            xlabel="Quarter", ylabel="Inflation (%)", title="GDP-deflator inflation",
            label="", lw=2, color=:steelblue, marker=:circle, markersize=3)
        Plots.hline!(p_infl, [0], color=:black, linestyle=:dash, label="")
        p_gdp = Plots.plot(1:T_obs, x_obs[T_obs+1:end] .* 100,
            xlabel="Quarter", ylabel="Growth (%)", title="Real GDP growth",
            label="", lw=2, color=:darkorange, marker=:circle, markersize=3)
        Plots.hline!(p_gdp, [0], color=:black, linestyle=:dash, label="")
        Plots.plot(p_infl, p_gdp, layout=(1,2), size=(1050,420),
             bottom_margin=6Plots.mm, top_margin=4Plots.mm)
    end
end

# ╔═╡ fe47a484-aeb2-11f1-ab62-c9fb038b7b75
md"""
---
## 5 — ABC: retain simulations close to the observation

**Approximate Bayesian Computation** makes the comparison explicit:

1. Draw coefficients from the prior.
2. Simulate an output using exactly the observation protocol above.
3. Measure $d(x_i,x_{\mathrm{obs}})=\|x_i-x_{\mathrm{obs}}\|_2$.
4. Keep coefficients whose distance is below a tolerance $\epsilon$.

The accepted draws approximate a posterior conditional on this data representation, distance and tolerance. A histogram displays these draws; the histogram is not the inference algorithm.

Smaller tolerances make the comparison stricter and usually leave fewer draws. High-dimensional outputs and weak identification can make useful acceptance rates difficult to achieve. There is no universal simulation budget or exponential acceptance law determined only by the number of parameters.

**Before pressing:** inflation and growth are both rates, but their typical variation can differ. With an unscaled Euclidean distance, which series could dominate? Standardising using training simulations is an alternative, but changes what counts as a close match.

The button generates a bank of distances once. Move the tolerance slider afterwards to reuse that bank without rerunning the ABM.
"""

# ╔═╡ fe47a48e-aeb2-11f1-ba58-7f92563411e7
@bind run_abc PlutoUI.CounterButton("2 — Generate the ABC bank (1,000 parameter draws)")

# ╔═╡ fe47a4a2-aeb2-11f1-b008-a52edb0e1db3
begin
    abc_bank = if python_ready && run_abc > 0 && x_obs !== nothing
        let rng = Xoshiro(808)
            draws = [(dp=rand(rng), cp=rand(rng), ae=rand(rng)) for _ in 1:N_abc]
            # Prior draws are made independently of summarise's global RNG resets.
            distances = [norm(summarise(θ; seed=10_000+i) .- x_obs)
                         for (i, θ) in enumerate(draws)]
            println("ABC bank complete: ", length(distances), " finite distances.")
            flush(stdout)
            (parameters=draws, distances=distances)
        end
    else
        saved_demo === nothing ? nothing : saved_demo["abc_bank"]
    end
    abc_bank === nothing ? md"Generate the observation, then press button 2. ABC is optional before the neural methods." :
    (!python_ready || run_abc == 0) ? md"Saved ABC result: **$(demo_accepted)/$(N_abc) accepted** at ε=$(demo_epsilon). Enable local execution to replot the stored distances at a different tolerance." :
        md"Computed $(length(abc_bank.distances)) distances. Try the tolerance slider; it does not launch new simulations."
end


# ╔═╡ f0050000-0000-4000-8000-000000000003
begin
    nb5_default_epsilon = abc_bank === nothing ? 0.005 :
        quantile(abc_bank.distances, ABC_accept_fraction)
    nb5_tolerances = sort(unique(vcat(nb5_default_epsilon .* [0.5, 0.75, 1.0, 1.5, 2.0], [0.03])))
    md"""
    ABC tolerance $\epsilon$: $(@bind ε PlutoUI.Slider(nb5_tolerances; default=nb5_default_epsilon, show_value=true))

    The default is the **10th percentile of this bank's distances**, retaining approximately
    the closest 10% of prior simulations. This is an explicit, data-dependent tolerance rule,
    not an accuracy guarantee. A larger simulation budget permits exploring smaller tolerances
    while retaining useful numbers of draws. The reading-mode figure uses the saved default;
    the slider replots only with local execution enabled.
    """
end

# ╔═╡ fe47a4ac-aeb2-11f1-aad4-dbf9faa34303
begin
    abc_accepted = abc_bank === nothing ? NamedTuple[] :
        abc_bank.parameters[abc_bank.distances .< ε]
    n_accepted = length(abc_accepted)
    if !python_ready && saved_demo !== nothing
        PlutoUI.LocalResource(joinpath(@__DIR__, "notebook05_figures", "abc.png"))
    elseif abc_bank === nothing
        md"No ABC bank yet."
    elseif n_accepted < 3
        md"ABC accepted **$(n_accepted)/$(N_abc)** draws at ε=$(ε). Too few draws to interpret a marginal histogram. Increase the tolerance to explore the stored bank."
    else
        p1_abc = Plots.histogram([s.dp for s in abc_accepted], bins=10, xlims=(0,1),
            title="Demand pull", xlabel="ϕ^DP", label="Accepted", color=:steelblue, alpha=0.7)
        Plots.vline!(p1_abc, [θ_true.dp], color=:red, lw=2, label="Synthetic truth")
        p2_abc = Plots.histogram([s.cp for s in abc_accepted], bins=10, xlims=(0,1),
            title="Cost push", xlabel="ϕ^CP", label="", color=:steelblue, alpha=0.7)
        Plots.vline!(p2_abc, [θ_true.cp], color=:red, lw=2, label="")
        p3_abc = Plots.histogram([s.ae for s in abc_accepted], bins=10, xlims=(0,1),
            title="Expectations", xlabel="ϕ^AE", label="", color=:steelblue, alpha=0.7)
        Plots.vline!(p3_abc, [θ_true.ae], color=:red, lw=2, label="")
        Plots.plot(p1_abc, p2_abc, p3_abc, layout=(1,3), size=(1050,420),
             bottom_margin=6Plots.mm, top_margin=4Plots.mm)
    end
end

# ╔═╡ fe47a4c8-aeb2-11f1-b2eb-316721706547
md"""
---
## 6 — NPE: learn a conditional density from simulated pairs

**Neural Posterior Estimation** replaces the acceptance rule with a learned distribution:

1. Draw $\theta_i$ from the prior and simulate $x_i$.
2. Fit a conditional density $q_\eta(\theta\mid x)$ by maximising
   $$\sum_i \log q_\eta(\theta_i\mid x_i).$$
3. Condition the fitted density on `x_obs` and draw candidate coefficient vectors.

Here a normalising flow is the density model: it transforms a simple distribution into a flexible distribution over the three coefficients. Training estimates how coefficients and outputs relate across the simulated examples. It does not make unidentified coefficients identifiable, and a small simulation budget can produce a poor approximation.

A prior-trained, **single-round** estimator can be reused for observations represented by the same simulator within its training domain. Sampling is usually fast after training, with rejection of draws outside the bounded prior support.

**Sequential NPE** adds rounds targeted to a particular observation. Draw new coefficients from the current posterior, simulate, and retrain with the appropriate proposal correction. This changes the training distribution; treating those draws as prior draws would give the wrong target. See the [official sequential guide](https://sbi.readthedocs.io/en/latest/how_to_guide/02_multiround_inference.html).
"""

# ╔═╡ fe47a4de-aeb2-11f1-a8a6-8dd6f18757b5
md"""
---
## 7 — Run one round of NPE and NRE-B with `sbi`

Julia runs the economies. PythonCall passes the resulting arrays to Python's [`sbi`](https://sbi.readthedocs.io/) library. `CondaPkg.toml` specifies `sbi>=0.26`; the enable checkbox triggers Python setup.

| Method | What is trained? | How are posterior draws obtained here? |
|---|---|---|
| NPE, using the SNPE-C engine | A density of coefficients conditional on outputs | Draw from the flow, reject outside the prior |
| NRE-B, using the SNRE-B engine | A compatibility score based on a likelihood-to-evidence ratio | Combine the score with the prior and run MCMC |

Both methods reuse **the same neural training bank**. They need no new ABM runs while fitting their networks. ABC has its own smaller bank for the tolerance exercise, so these demonstration budgets do not constitute a fair efficiency comparison.

Run button 3 to generate pairs, then button 4 for NPE. Button 5 for NRE is optional. Keep the small default budgets first; inspect failures and diagnostics before paying for larger runs.
"""

# ╔═╡ fe47a4e8-aeb2-11f1-a0c6-cf432609d50c
begin
    _torch, _np, _sbi_inf, _sbi_utils, _mcmc_par = if python_ready
        (PythonCall.pyimport("torch"), PythonCall.pyimport("numpy"), PythonCall.pyimport("sbi.inference"),
         PythonCall.pyimport("sbi.utils"),
         PythonCall.pyimport("sbi.inference.posteriors.posterior_parameters").MCMCPosteriorParameters)
    else
        (nothing, nothing, nothing, nothing, nothing)
    end
    python_ready ? md"Python inference imports ready (torch $(PythonCall.pyconvert(String, _torch.__version__)))." :
        md"Python inference imports are disabled in reading mode."
end

# ╔═╡ fe47a4f2-aeb2-11f1-b056-f167b82071b2
md"""
### Step 1 — Generate training pairs and inspect the dimensions

Every row of the coefficient matrix is `[dp, cp, ae]`. The corresponding row of the output matrix is `[T inflation rates; T growth rates]`.

For the default `N_sbi=2000` and `T_sim=12`, the shapes are **2,000 × 3** and **2,000 × 24**. Conversion to `Float32` matches PyTorch's default training precision; it does not change the meaning or units of the observations.

Failed or non-finite simulations are reported and **block training**. Silently deleting parameter-dependent failures can change the distribution being estimated. Diagnose the model or observation protocol first. The error messages below give the first few affected draws.
"""

# ╔═╡ fe47a506-aeb2-11f1-a7b7-5308423c8cfe
@bind run_sbi_sims PlutoUI.CounterButton("3 — Generate neural training pairs (2,000 draws)")

# ╔═╡ fe47a510-aeb2-11f1-a698-ef70514f417b
begin
    sbi_bank = if python_ready && run_sbi_sims > 0 && x_obs !== nothing
        let rng = Xoshiro(99)
            draws = [(dp=rand(rng), cp=rand(rng), ae=rand(rng)) for _ in 1:N_sbi]
            θs = typeof(θ_true)[]
            xs = Vector{Float32}[]
            failures = String[]
            for (i, θ) in enumerate(draws)
                try
                    x = Float32.(summarise(θ; seed=20_000+i))
                    all(isfinite, x) || error("Conversion produced a non-finite output.")
                    push!(θs, θ)
                    push!(xs, x)
                catch err
                    err isa InterruptException && rethrow()
                    push!(failures, "draw $(i), θ=$(θ): $(sprint(showerror, err))")
                end
                if i % 200 == 0
                    println("Training simulations: ", i, "/", N_sbi, "; failures: ", length(failures))
                    flush(stdout)
                end
            end
            (parameters=θs, outputs=xs, failures=failures)
        end
    else
        saved_demo === nothing ? nothing : saved_demo["sbi_bank"]
    end
    _n_failed = sbi_bank === nothing ? 0 : length(sbi_bank.failures)
    _sbi_ready = python_ready && sbi_bank !== nothing && _n_failed == 0 && length(sbi_bank.parameters) >= 50
    _θ_mat, _x_mat, _θ_tensor, _x_tensor, _x_obs_t, _sbi_prior = if _sbi_ready
        let θmat=Float32.(reduce(vcat, [[t.dp t.cp t.ae] for t in sbi_bank.parameters])),
            xmat=reduce(vcat, [permutedims(x) for x in sbi_bank.outputs])
            θtensor = _torch.from_numpy(_np.asarray(θmat, dtype=_np.float32))
            xtensor = _torch.from_numpy(_np.asarray(xmat, dtype=_np.float32))
            xobs = _torch.tensor(Float32.(x_obs))
            prior = _sbi_utils.BoxUniform(low=_torch.zeros(3), high=_torch.ones(3))
            (θmat, xmat, θtensor, xtensor, xobs, prior)
        end
    else
        (nothing, nothing, nothing, nothing, nothing, nothing)
    end
    if sbi_bank === nothing
        md"Generate the observation, then press button 3."
    elseif _n_failed > 0
        let messages=join(first(sbi_bank.failures, min(3, _n_failed)), " | ")
            md"Training blocked: **$(_n_failed)/$(N_sbi)** simulations failed. First errors: $(messages)."
        end
    elseif !python_ready
        md"Saved training bank: **$(length(sbi_bank.parameters)) pairs**, no failed draws. Enable local execution to train the networks."
    elseif !_sbi_ready
        md"Use at least 50 valid examples for this demonstration. A small training set is not a posterior-accuracy guarantee."
    else
        md"Training bank ready: coefficient matrix **$(size(_θ_mat))**, output matrix **$(size(_x_mat))**; no failed draws."
    end
end

# ╔═╡ fe47a51a-aeb2-11f1-b61f-b1712369fe7d
md"""
### Step 2a — Fit NPE, condition on the observation, sample

Read the next cell as **append → train → build → condition → sample**. The SNPE-C engine receives only one prior-sampled bank here, so this is single-round NPE.

Training stops after a capped number of epochs or lack of improvement on held-out training examples. That validation loss checks network fitting; it does not validate the economics. Fixed seeds make this run repeatable. They do not establish robustness across network initialisations or simulated observations.

**Read the histograms:** a red truth line near substantial posterior mass is encouraging. A narrow peak away from it is a failure to investigate. Also inspect parameter correlations: similar marginal widths can conceal very different trade-offs between the three pricing channels.
"""

# ╔═╡ fe47a52e-aeb2-11f1-850a-c7a03de04063
@bind run_snpe PlutoUI.CounterButton("4 — Train NPE and draw posterior samples")

# ╔═╡ fe47a538-aeb2-11f1-ac52-bdf95b720ba4
begin
    snpe_engine, snpe_post_py, snpe_samples = if python_ready && run_snpe > 0 && _sbi_ready
        let
            _torch.manual_seed(0)
            engine = _sbi_inf.SNPE(prior=_sbi_prior)
            engine.append_simulations(_θ_tensor, _x_tensor)
            estimator = engine.train(max_num_epochs=300, stop_after_epochs=20,
                                     show_train_summary=true)
            posterior = engine.build_posterior(estimator).set_default_x(_x_obs_t)
            raw = posterior.sample([N_npe_draws])
            samples = PythonCall.pyconvert(Matrix{Float64}, raw.detach().cpu().numpy().reshape(-1, 3))
            (engine, posterior, samples)
        end
    else
        (nothing, nothing, saved_demo === nothing ? nothing : saved_demo["snpe_samples"])
    end
    snpe_samples === nothing ? md"Generate a valid training bank, then press button 4." :
    snpe_engine === nothing ? md"Saved NPE result: **$(size(snpe_samples, 1)) approximate posterior draws** from the default run. Press button 4 locally to retrain." :
        md"NPE produced **$(size(snpe_samples, 1)) approximate posterior draws**. Check the training summary and compare the three marginals below."
end

# ╔═╡ fe47a542-aeb2-11f1-86f9-154ba253a889
begin
    if !python_ready && saved_demo !== nothing
        PlutoUI.LocalResource(joinpath(@__DIR__, "notebook05_figures", "npe.png"))
    elseif snpe_samples === nothing
        md"No NPE draws yet."
    else
        p1_snpe = Plots.histogram(snpe_samples[:,1], bins=20, normalize=true, xlims=(0,1),
            title="NPE: demand pull", xlabel="ϕ^DP", label="Approximate posterior", color=:steelblue, alpha=0.7)
        Plots.vline!(p1_snpe, [θ_true.dp], color=:red, lw=2, label="Synthetic truth")
        p2_snpe = Plots.histogram(snpe_samples[:,2], bins=20, normalize=true, xlims=(0,1),
            title="NPE: cost push", xlabel="ϕ^CP", label="", color=:steelblue, alpha=0.7)
        Plots.vline!(p2_snpe, [θ_true.cp], color=:red, lw=2, label="")
        p3_snpe = Plots.histogram(snpe_samples[:,3], bins=20, normalize=true, xlims=(0,1),
            title="NPE: expectations", xlabel="ϕ^AE", label="", color=:steelblue, alpha=0.7)
        Plots.vline!(p3_snpe, [θ_true.ae], color=:red, lw=2, label="")
        Plots.plot(p1_snpe, p2_snpe, p3_snpe, layout=(1,3), size=(1050,420),
             bottom_margin=6Plots.mm, top_margin=4Plots.mm)
    end
end

# ╔═╡ fe47a560-aeb2-11f1-9155-67117e02ae01
md"""
### Step 2b — NRE-B: learn which coefficients belong with an output

**Neural Ratio Estimation** learns how compatible a coefficient vector is with the observed data. The target likelihood-to-evidence ratio is

$$r(\theta,x)=\frac{p(\theta,x)}{p(\theta)p(x)}=\frac{p(x\mid\theta)}{p(x)}.$$

For NRE-B, training presents an output with several candidate coefficient vectors: one generated that output and the others are independent alternatives. A **contrastive, one-out-of-K classifier** learns to recognise the compatible pair. This differs from the binary joint-versus-independent classifier used by NRE-A; see the [official NRE-B description](https://sbi.readthedocs.io/en/latest/api_reference/_autosummary/sbi.inference.NRE_B.html).

At fixed `x_obs`, multiply the learned ratio by the prior to obtain an approximate posterior up to a normalising constant. Here `sbi` samples that target using slice MCMC. Other sampling choices exist; MCMC is the choice in this example, not a defining requirement of every ratio estimator.

**Before running:** both methods see the same data. If NPE and NRE disagree, does that prove the economic model is wrong? Distinguish network approximation error, sampling error, weak identification and misspecification.

The small MCMC run below illustrates the workflow. Its draws are correlated; a histogram alone does not check chain mixing or effective sample size.
"""

# ╔═╡ fe47a574-aeb2-11f1-b9d3-15da0a71e396
@bind run_snre PlutoUI.CounterButton("5 — Train NRE-B and sample with MCMC (optional)")

# ╔═╡ fe47a57e-aeb2-11f1-b49a-35077214ebb5
begin
    snre_engine, snre_post_py, snre_samples = if python_ready && run_snre > 0 && _sbi_ready
        let
            _torch.manual_seed(0)
            engine = _sbi_inf.SNRE_B(prior=_sbi_prior)
            engine.append_simulations(_θ_tensor, _x_tensor)
            classifier = engine.train(num_atoms=min(10, fld(length(sbi_bank.parameters), 10)), max_num_epochs=300,
                                      stop_after_epochs=20, show_train_summary=true)
            posterior = engine.build_posterior(classifier,
                posterior_parameters=_mcmc_par(method="slice_np_vectorized",
                    num_chains=4, thin=1, warmup_steps=500)).set_default_x(_x_obs_t)
            _torch.manual_seed(0)
            _np.random.seed(0)
            raw = posterior.sample([N_nre_draws])
            samples = PythonCall.pyconvert(Matrix{Float64}, raw.detach().cpu().numpy().reshape(-1, 3))
            (engine, posterior, samples)
        end
    else
        (nothing, nothing, saved_demo === nothing ? nothing : saved_demo["snre_samples"])
    end
    snre_samples === nothing ? md"Generate a valid training bank, then press button 5." :
    snre_engine === nothing ? md"Saved NRE-B result: **$(size(snre_samples, 1)) MCMC draws** from the default run. These draws are correlated; press button 5 locally to retrain." :
        md"NRE-B produced **$(size(snre_samples, 1)) MCMC draws** from an approximate posterior. The draws are correlated; inspect the chain diagnostics below."
end

# ╔═╡ fe47a588-aeb2-11f1-8e59-3947a4232ada
begin
    if !python_ready && saved_demo !== nothing
        PlutoUI.LocalResource(joinpath(@__DIR__, "notebook05_figures", "nre.png"))
    elseif snre_samples === nothing
        md"No NRE draws yet."
    else
        p1_snre = Plots.histogram(snre_samples[:,1], bins=20, normalize=true, xlims=(0,1),
            title="NRE-B: demand pull", xlabel="ϕ^DP", label="Approximate posterior", color=:darkorange, alpha=0.7)
        Plots.vline!(p1_snre, [θ_true.dp], color=:red, lw=2, label="Synthetic truth")
        p2_snre = Plots.histogram(snre_samples[:,2], bins=20, normalize=true, xlims=(0,1),
            title="NRE-B: cost push", xlabel="ϕ^CP", label="", color=:darkorange, alpha=0.7)
        Plots.vline!(p2_snre, [θ_true.cp], color=:red, lw=2, label="")
        p3_snre = Plots.histogram(snre_samples[:,3], bins=20, normalize=true, xlims=(0,1),
            title="NRE-B: expectations", xlabel="ϕ^AE", label="", color=:darkorange, alpha=0.7)
        Plots.vline!(p3_snre, [θ_true.ae], color=:red, lw=2, label="")
        Plots.plot(p1_snre, p2_snre, p3_snre, layout=(1,3), size=(1050,420),
             bottom_margin=6Plots.mm, top_margin=4Plots.mm)
    end
end

# ╔═╡ f0050000-0000-4000-8000-000000000005
md"""
### Step 3 — Measure recovery, prediction and sampling quality

The optional sixth stage records the median and central 90% interval for the known
truth, generates **50 fresh posterior-predictive outputs per neural method**, and
runs **50 prior-predictive NPE calibration experiments**, each with 1,000 conditional
posterior draws. All new observations use the original four-path observation protocol
and seeds outside the fitting ranges. This stage does not retrain the networks.

NPE calibration ranks count posterior draws below each simulated true coefficient.
Uniform ranks are a necessary check for calibrated marginals; 50 experiments have
limited power, and marginal checks can miss errors in joint dependence. The reported
90% interval coverage is measured across these new experiments, not inferred from
the one red truth line. NRE calibration across new observations remains a separate,
more expensive exercise.

For NRE, diagnostics use **four separate chains**, after discarding 500 warmup draws
per chain and transforming back to coefficient units. Rank-normalised R-hat, bulk
ESS and tail ESS assess the sampler. They do not validate the learned ratio or the
economic mechanism. See the [SBI diagnostic guide](https://sbi.readthedocs.io/en/stable/how_to_guide/12_mcmc_diagnostics_with_arviz.html).
"""

# ╔═╡ f0050000-0000-4000-8000-000000000006
@bind run_diagnostics PlutoUI.CounterButton("6 — Check recovery, prediction and chain mixing (optional)")

# ╔═╡ f0050000-0000-4000-8000-000000000007
begin
    function nb5_check_inference(npe, nre, npe_samples, nre_samples)
        recovery = Dict{String, Any}()
        predictive = Dict{String, Any}()
        for (method, samples, base_seed) in (("NPE", npe_samples, 40_000), ("NRE", nre_samples, 50_000))
            recovery[method] = Dict("median" => vec(median(samples; dims=1)),
                "lower" => [quantile(samples[:, k], 0.05) for k in 1:3],
                "upper" => [quantile(samples[:, k], 0.95) for k in 1:3])
            indices = randperm(Xoshiro(base_seed), size(samples, 1))[1:N_predictive_draws]
            outputs = reduce(vcat, [permutedims(summarise(
                (dp=samples[row, 1], cp=samples[row, 2], ae=samples[row, 3]); seed=base_seed+i))
                for (i, row) in enumerate(indices)])
            predictive[method] = outputs
        end
        println("Posterior-predictive outputs complete: ", N_predictive_draws, " per method.")
        flush(stdout)

        rng = Xoshiro(2026)
        truths = [(dp=rand(rng), cp=rand(rng), ae=rand(rng)) for _ in 1:N_diagnostic_observations]
        ranks = zeros(Int, N_diagnostic_observations, 3)
        covered = falses(N_diagnostic_observations, 3)
        _torch.manual_seed(2026)
        for (i, truth) in enumerate(truths)
            x = summarise(truth; seed=30_000+i)
            xt = _torch.tensor(Float32.(x))
            raw = npe.sample([1000]; x=xt, show_progress_bars=false)
            draws = PythonCall.pyconvert(Matrix{Float64}, raw.detach().cpu().numpy())
            all(isfinite, draws) && all(v -> 0 <= v <= 1, draws) || error("Invalid NPE diagnostic draws.")
            for k in 1:3
                ranks[i, k] = count(v -> v < values(truth)[k], draws[:, k])
                covered[i, k] = quantile(draws[:, k], 0.05) <= values(truth)[k] <= quantile(draws[:, k], 0.95)
            end
            if i % 10 == 0
                println("NPE calibration experiments: ", i, "/", N_diagnostic_observations)
                flush(stdout)
            end
        end

        # SBI retains warmup in the sampler object. Request only the final
        # retained draws per chain; never reshape the already-flattened sample.
        transformed = nre.posterior_sampler.get_samples(
            num_samples=div(N_nre_draws, 4), group_by_chain=true)
        shape = PythonCall.pyconvert(Tuple{Int, Int, Int}, transformed.shape)
        shape == (4, div(N_nre_draws, 4), 3) || error("Unexpected per-chain shape: $shape")
        original = nre.theta_transform.inv(_torch.from_numpy(transformed.reshape(-1, 3))).reshape(shape...)
        chains = PythonCall.pyconvert(Array{Float64, 3}, original.detach().cpu().numpy())
        flattened = reduce(vcat, [chains[c, :, :] for c in 1:4])
        isapprox(flattened, nre_samples; atol=1e-6, rtol=1e-6) || error("Chain diagnostics do not match the retained posterior draws.")
        az = PythonCall.pyimport("arviz")
        idata = az.from_dict(posterior=Dict("theta" => original.detach().cpu().numpy()))
        rhat = PythonCall.pyconvert(Vector{Float64}, az.rhat(idata; method="rank")["theta"].values)
        bulk = PythonCall.pyconvert(Vector{Float64}, az.ess(idata; method="bulk")["theta"].values)
        tail = PythonCall.pyconvert(Vector{Float64}, az.ess(idata; method="tail")["theta"].values)
        all(isfinite, vcat(rhat, bulk, tail)) || error("Non-finite MCMC diagnostics.")
        return Dict("recovery" => recovery, "predictive" => predictive,
            "sbc_ranks" => ranks, "sbc_covered" => covered, "sbc_truths" => truths,
            "sbc_draws" => 1000, "chains" => chains, "rhat" => rhat,
            "ess_bulk" => bulk, "ess_tail" => tail)
    end
    inference_checks = if python_ready && run_diagnostics > 0 && snpe_post_py !== nothing && snre_post_py !== nothing
        nb5_check_inference(snpe_post_py, snre_post_py, snpe_samples, snre_samples)
    elseif !python_ready && saved_demo !== nothing
        get(saved_demo, "diagnostics", nothing)
    else
        nothing
    end
    if inference_checks === nothing
        md"Run both neural methods before pressing button 6."
    else
        let d=inference_checks, labels=("Demand pull", "Cost push", "Expectations")
            fmt(x) = string(round(x; digits=3))
            rows = ["| $(labels[k]) | $(fmt(d["rhat"][k])) | $(round(Int, d["ess_bulk"][k])) | $(round(Int, d["ess_tail"][k])) | $(round(Int, sum(d["sbc_covered"][:, k])))/$(N_diagnostic_observations) |" for k in 1:3]
            recovery_rows = ["| $method: $(labels[k]) | $(fmt(values(θ_true)[k])) | $(fmt(d["recovery"][method]["median"][k])) | [$(fmt(d["recovery"][method]["lower"][k])), $(fmt(d["recovery"][method]["upper"][k]))] |" for method in ("NPE", "NRE") for k in 1:3]
            Markdown.parse("### Measured diagnostics\n\n| Coefficient | NRE R-hat | Bulk ESS | Tail ESS | NPE 90% interval coverage |\n|---|---:|---:|---:|---:|\n" * join(rows, "\n") *
                "\n\nCoverage here uses $N_diagnostic_observations new prior-predictive observations. These estimates are noisy; inspect the rank histograms as well. R-hat should be close to one, and ESS can be much lower than the nominal number of draws.\n\n| Recovery at the original observation | Truth | Median | Central 90% interval |\n|---|---:|---:|---|\n" * join(recovery_rows, "\n"))
        end
    end
end

# ╔═╡ f0050000-0000-4000-8000-000000000008
begin
    function nb5_predictive_figure(checks, observation, horizon)
        panels = map(1:2) do channel
            cols = channel == 1 ? (1:horizon) : (horizon+1:2horizon)
            panel = Plots.plot(1:horizon, 100 .* observation[cols]; color=:black, lw=2,
                label="Observation", title=channel == 1 ? "Inflation: posterior prediction" : "Growth: posterior prediction",
                xlabel="Quarter", ylabel="Rate (%)")
            for (method, color) in (("NPE", :steelblue), ("NRE", :darkorange))
                outputs = checks["predictive"][method][:, cols]
                med = [quantile(outputs[:, k], 0.5) for k in 1:horizon]
                lo = [quantile(outputs[:, k], 0.1) for k in 1:horizon]
                hi = [quantile(outputs[:, k], 0.9) for k in 1:horizon]
                Plots.plot!(panel, 1:horizon, 100 .* med; ribbon=(100 .* (med-lo), 100 .* (hi-med)),
                    color, fillalpha=0.15, label="$method median / 10th–90th percentiles", lw=1.5)
            end
            panel
        end
        Plots.plot(panels...; layout=(1, 2), size=(1050, 420), bottom_margin=6Plots.mm, left_margin=4Plots.mm, titlefontsize=11, legendfontsize=7)
    end
    if !python_ready && inference_checks !== nothing
        PlutoUI.LocalResource(joinpath(@__DIR__, "notebook05_figures", "predictive.png"))
    elseif inference_checks !== nothing
        nb5_predictive_figure(inference_checks, x_obs, T_sim)
    else
        md"Posterior-predictive figure appears after diagnostics."
    end
end

# ╔═╡ f0050000-0000-4000-8000-000000000009
begin
    function nb5_rank_figure(checks)
        panels = map(1:3) do k
            p = Plots.histogram(checks["sbc_ranks"][:, k] ./ checks["sbc_draws"]; bins=0:0.2:1,
                xlims=(0, 1), title=("NPE ranks: demand", "NPE ranks: costs", "NPE ranks: expectations")[k],
                xlabel="Fraction of draws below truth", ylabel="Experiments", label="", color=:steelblue)
            Plots.hline!(p, [size(checks["sbc_ranks"], 1)/5]; color=:black, ls=:dash, label="")
            p
        end
        Plots.plot(panels...; layout=(1, 3), size=(1050, 420), bottom_margin=6Plots.mm, titlefontsize=11)
    end
    if !python_ready && inference_checks !== nothing
        PlutoUI.LocalResource(joinpath(@__DIR__, "notebook05_figures", "ranks.png"))
    elseif inference_checks !== nothing
        nb5_rank_figure(inference_checks)
    else
        md"NPE calibration ranks appear after diagnostics."
    end
end

# ╔═╡ f0050000-0000-4000-8000-000000000010
begin
    function nb5_chain_figure(checks)
        chains = checks["chains"]
        panels = map(1:3) do k
            Plots.plot(permutedims(chains[:, :, k]); title=("NRE chains: demand", "NRE chains: costs", "NRE chains: expectations")[k],
                xlabel="Retained draw per chain", ylabel="Coefficient", ylims=(0, 1), label=["1" "2" "3" "4"], lw=0.8, alpha=0.7)
        end
        Plots.plot(panels...; layout=(1, 3), size=(1050, 420), bottom_margin=6Plots.mm, titlefontsize=11)
    end
    if !python_ready && inference_checks !== nothing
        PlutoUI.LocalResource(joinpath(@__DIR__, "notebook05_figures", "chains.png"))
    elseif inference_checks !== nothing
        nb5_chain_figure(inference_checks)
    else
        md"NRE chain traces appear after diagnostics."
    end
end

# ╔═╡ fe47a59e-aeb2-11f1-80fd-7da834c0a7bf
md"""
---
## 8 — What did this experiment establish?

| Check | Question | What it cannot establish alone |
|---|---|---|
| Known-truth recovery | Does the estimator locate chosen coefficients in synthetic data? | Credible intervals with correct repeated-experiment coverage |
| Inference calibration | Across many prior draws and held-out observations, are posterior probabilities calibrated? | That the simulator describes the real economy |
| Posterior predictive check | Do posterior draws reproduce observed and additional features? | Uniqueness of the mechanism or correct intervention effects |
| Empirical / policy validation | Does the model predict independent data or intervention responses? | Universal reliability across regimes and policy changes |

Do not interpret a tighter posterior as automatically better. It can reflect informative data, an overconfident neural approximation, an incorrect observation protocol, or a misspecified model.

A broad ridge may reveal weak identification: different pass-through combinations produce similar aggregate trajectories. A model can also fit these two series while missing employment, sectoral inflation or the response to a wage intervention. Use additional observations and alternative mechanisms to investigate that possibility.

The demonstration does not assert that one method outperforms the others. Comparing methods needs equal simulation budgets, repeated held-out experiments and accuracy diagnostics, not just narrower histograms.
"""

# ╔═╡ fe47a5a6-aeb2-11f1-aac1-bbb9e8e11248
md"""
---
## Exercises — predict, change one thing, explain

### 05.1 — The tolerance trade-off *(no new ABM runs)*

Move `ε` to half and twice its default value. Record the accepted count and describe the three histograms. Compare with the previous loose tolerance of 0.03. Is a visually sharper peak based on three draws convincing evidence of precision?

**Hint:** with a fixed bank, decreasing the tolerance cannot increase the number of accepted draws. Posterior width need not change monotonically in a tiny sample.

### 05.2 — Inspect joint identification *(no new ABM runs)*

After NPE, use `Plots.scatter(snpe_samples[:,2], snpe_samples[:,3])` and `cor(snpe_samples[:,2], snpe_samples[:,3])`. Do cost push and expected inflation compensate for one another? Compare the joint cloud with the two marginal histograms.

**Hint:** label both axes and restrict them to `[0,1]`. A diagonal cloud can show a trade-off even when each marginal has a visible peak. Do not assume this trade-off occurs before seeing the plot.

### 05.3 — Compare two representations *(reuse the stored bank)*

Define a new representation that averages inflation and growth within each of three four-quarter blocks. It has six values instead of 24. Apply it to **both** `x_obs` and every stored training output, then fit a separate NPE engine with the same coefficient draws. Which timing information was discarded?

**Hint:** start with `mean(x[1:4])` and repeat for `5:8`, `9:12` and the corresponding growth blocks. Keep coefficients, observation seed and training budget fixed. Retraining costs time; no new ABM simulations are needed.

### 05.4 — Recovery and posterior prediction *(at most 10 new outputs)*

Draw ten coefficient vectors from the fitted NPE posterior. Convert each row to `(dp=..., cp=..., ae=...)`, simulate with ten fresh seeds, and overlay the inflation and growth paths on `x_obs`. Describe one feature the model reproduces and one it struggles with, if any.

**Hint:** retain `N=N_paths`, `T=T_sim` and the same data transformations. Use seeds outside the observation and training ranges. This checks the fitted features, so choose an additional variable for a stronger subsequent test.

### 05.5 — Design a misspecification test *(discussion first)*

Suppose the real observation was generated under a different expectation rule or with measurement error, but inference uses this simulator unchanged. Could a narrow posterior still result? Propose an observable or an intervention response that might separate parameter error from mechanism error.

**Hint:** a same-model recovery exercise cannot test a mechanism it assumes to be correct. Explain what would remain ambiguous even after a successful posterior predictive check.

### 05.6 — Add a second SNPE round *(optional stretch)*

Use `snpe_post_py` conditioned on `x_obs` as a proposal for **100** new draws. Simulate those draws with fresh seeds, append them to the **same** engine with `proposal=snpe_post_py`, retrain and build a new posterior. Compare with round one before increasing the budget.

**Hint:** keep the old posterior object as the proposal and call `append_simulations(new_theta, new_x, proposal=old_posterior)`. Proposal correction is essential. A targeted sequential estimator is not guaranteed to remain accurate for unrelated observations; see the [sequential guide](https://sbi.readthedocs.io/en/latest/how_to_guide/02_multiround_inference.html).

---
## Further reading

- Dyer, J., Cannon, P., Farmer, J. Doyne and Schmon, S. M. (2024). [*Black-Box Bayesian Inference for Agent-Based Models*](https://doi.org/10.1016/j.jedc.2024.104827), *Journal of Economic Dynamics and Control* — the economic-ABM application behind the SBI lecture.
- [`sbi`: Bayesian workflow and diagnostics](https://sbi.readthedocs.io/en/latest/tutorials/01_Bayesian_workflow.html) — distinguish approximation checks from model checks.
- [`sbi4abm` examples](https://github.com/joelnmdyer/sbi4abm) — implementation examples for economic ABMs.
"""

# ╔═╡ Cell order:
# ╟─fe46785c-aeb2-11f1-b29c-f9f57fb156bb
# ╠═fe47a376-aeb2-11f1-b61a-afb43896f469
# ╟─f0050000-0000-4000-8000-000000000001
# ╠═f0050000-0000-4000-8000-000000000002
# ╟─fe47a3e4-aeb2-11f1-8672-87cfc7b65656
# ╟─fe47a3f8-aeb2-11f1-bb78-fdae608fd8dd
# ╠═fe47a416-aeb2-11f1-9746-851acfeb8207
# ╠═f0050000-0000-4000-8000-000000000004
# ╟─fe47a420-aeb2-11f1-8d8a-abc5ec0d8da6
# ╠═fe47a436-aeb2-11f1-9b2a-3f8bba375ef7
# ╠═fe47a43e-aeb2-11f1-8236-cf09de2a48a6
# ╟─fe47a448-aeb2-11f1-8128-47d32eec72fc
# ╠═fe47a45c-aeb2-11f1-8796-d9a46d0f705f
# ╠═fe47a470-aeb2-11f1-b509-5733fe3f376e
# ╟─fe47a484-aeb2-11f1-ab62-c9fb038b7b75
# ╠═fe47a48e-aeb2-11f1-ba58-7f92563411e7
# ╠═fe47a4a2-aeb2-11f1-b008-a52edb0e1db3
# ╠═f0050000-0000-4000-8000-000000000003
# ╠═fe47a4ac-aeb2-11f1-aad4-dbf9faa34303
# ╟─fe47a4c8-aeb2-11f1-b2eb-316721706547
# ╟─fe47a4de-aeb2-11f1-a8a6-8dd6f18757b5
# ╠═fe47a4e8-aeb2-11f1-a0c6-cf432609d50c
# ╟─fe47a4f2-aeb2-11f1-b056-f167b82071b2
# ╠═fe47a506-aeb2-11f1-a7b7-5308423c8cfe
# ╠═fe47a510-aeb2-11f1-a698-ef70514f417b
# ╟─fe47a51a-aeb2-11f1-b61f-b1712369fe7d
# ╠═fe47a52e-aeb2-11f1-850a-c7a03de04063
# ╠═fe47a538-aeb2-11f1-ac52-bdf95b720ba4
# ╠═fe47a542-aeb2-11f1-86f9-154ba253a889
# ╟─fe47a560-aeb2-11f1-9155-67117e02ae01
# ╠═fe47a574-aeb2-11f1-b9d3-15da0a71e396
# ╠═fe47a57e-aeb2-11f1-b49a-35077214ebb5
# ╠═fe47a588-aeb2-11f1-8e59-3947a4232ada
# ╟─f0050000-0000-4000-8000-000000000005
# ╠═f0050000-0000-4000-8000-000000000006
# ╠═f0050000-0000-4000-8000-000000000007
# ╠═f0050000-0000-4000-8000-000000000008
# ╠═f0050000-0000-4000-8000-000000000009
# ╠═f0050000-0000-4000-8000-000000000010
# ╟─fe47a59e-aeb2-11f1-80fd-7da834c0a7bf
# ╟─fe47a5a6-aeb2-11f1-aac1-bbb9e8e11248
