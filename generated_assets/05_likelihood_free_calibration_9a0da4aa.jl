### A Pluto.jl notebook ###
# v0.20.24

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
# Notebook 05 — Likelihood-free calibration with simulation-based inference *(advanced)*

> **Question this notebook answers:** the CANVAS pass-through coefficients $\phi^{DP}, \phi^{CP}, \phi^{AE}$ are free parameters. How do we calibrate them without a tractable likelihood?

### Lecture 2 slides covered
- *The Likelihood Problem in Agent-Based Models*
- *Neural Posterior Estimation (Dyer et al., 2024)*
- *Sequential Neural Posterior Estimation (SNPE)*
- *Results: decisive improvement over KDE*

### Learning goals
1. Understand why standard Bayesian methods fail for ABMs (intractable likelihood).
2. Build a simulator function $\theta \mapsto x$ compatible with SBI libraries.
3. Run a simple Approximate Bayesian Computation (ABC) as a baseline.
4. See how Neural Posterior Estimation (NPE) overcomes the ABC curse of dimensionality.
5. Run SNPE-C and SNRE-B end-to-end using the Python `sbi` package via `PythonCall`.
"""

# ╔═╡ fe47a376-aeb2-11f1-b61a-afb43896f469
begin
    import Pkg
    Pkg.activate(joinpath(@__DIR__, "..", "..", "pluto_tutorial"); io=devnull)
    import BeforeIT as Bit
    using Plots, PlutoUI, Statistics, Distributions, LinearAlgebra, Random, Dates
    using PythonCall
end

# ╔═╡ fe47a3e4-aeb2-11f1-8672-87cfc7b65656
md"""
---
## 1 — The likelihood problem

Recall from Lecture 2: to do Bayesian inference we want

$$p(\theta \mid x_{\text{obs}}) \propto p(x_{\text{obs}} \mid \theta)\, p(\theta)$$

For the ABM, $p(x \mid \theta)$ is **intractable** — we can *simulate* $x \sim \text{ABM}(\theta)$ but cannot *evaluate* the likelihood at any specific $x$.

Standard methods fail:
- **MCMC** needs the likelihood at every proposal step.
- **Variational inference** needs the likelihood in the ELBO expectation.
- **Grid search** is exponential in the number of parameters.

What works: **likelihood-free** methods that only need a simulator.
"""

# ╔═╡ fe47a3f8-aeb2-11f1-bb78-fdae608fd8dd
md"""
---
## 2 — Define the target parameters and observed data

We calibrate the three CANVAS pass-through coefficients from Notebook 04:

$$\theta = (\phi^{DP},\, \phi^{CP},\, \phi^{AE}) \in [0, 1]^3$$

**Observed data $x_{\text{obs}}$:** the macroeconomic time series produced by a forward run of the model at the true $\theta$. Following Wiese et al. (2023), we pass raw trajectories directly to the neural network rather than hand-crafted scalars — the network learns which features identify the parameters.

Note that averaging over Monte Carlo paths *is* itself a summary-statistic choice: it discards the cross-path dispersion, so any parameter identified mainly through volatility rather than through the mean path will be harder to recover here.

We use two observable series over $T$ quarters:
- Quarter-by-quarter **GDP deflator inflation** (period-over-period price level change)
- Quarter-by-quarter **real GDP growth**

giving a $2T$-dimensional summary statistic. In a real application $x_{\text{obs}}$ would come from empirical data; here we use a synthetic simulation at known $\theta_{\text{true}}$ as the target.
"""

# ╔═╡ fe47a416-aeb2-11f1-9746-851acfeb8207
begin
    # Scale=0.0001 gives 481 firms across 62 sectors — small enough for SBI budgets.
    # Finite-size noise is handled by MC averaging:
    #   N_obs   — large, for x_obs; mimics empirical data aggregated over many draws.
    #   N_paths — smaller, for each training simulation; balances noise vs. runtime.
    #
    # N_obs > N_paths is deliberate and helps: the distance ‖x_sim - x_obs‖
    # carries variance from BOTH terms, so a smoother x_obs removes one of the
    # two noise sources. Measured over 12 replications at scale 0.0001,
    # T_sim = 12: with N_obs = 64 the distance at the true θ is 0.0196 ± 0.003
    # against 0.0459 ± 0.006 at a wrong θ (8.8σ separation); setting
    # N_obs = N_paths = 8 degrades that to 5.4σ.
    #
    # The caveat is interpretive, not numerical. Real data is a SINGLE
    # realisation, so a posterior conditioned on a 64-path average is tighter
    # than one conditioned on an actual economy would be. Read the posteriors
    # below as "what could be recovered from an idealised, noise-averaged
    # observation", not as an empirical uncertainty estimate.
    parameters, init_cond = Bit.get_params_and_initial_conditions(
        Bit.ITALY_CALIBRATION, DateTime(2010, 3, 31); scale = 0.0001)

    # "True" pass-through values (we will try to recover these)
    θ_true = (dp = 0.2, cp = 0.5, ae = 0.7)

    T_sim   = 12
    N_obs   = 64  # MC replications for x_obs — large N gives a smooth "empirical" target
    N_paths = 8   # MC replications for each training simulation (speed/quality trade-off)
    """Setup complete — $(round(Int, sum(parameters["I_s"]))) firms across $(length(parameters["I_s"])) sectors, H_act=$(round(Int, parameters["H_act"])). True θ = $(θ_true)"""
end

# ╔═╡ fe47a420-aeb2-11f1-8d8a-abc5ec0d8da6
md"""
---
## 3 — The simulator function $\theta \mapsto x$

The simulator runs the CANVAS model at given $\theta$ for $T$ quarters and returns the concatenated inflation and real-GDP-growth time series — a $2T$-dimensional vector.
Each training simulation uses $N$ Monte Carlo paths; averaging reduces noise while keeping runtime tractable.
"""

# ╔═╡ fe47a436-aeb2-11f1-9b2a-3f8bba375ef7
begin
    # Same CANVAS model as Notebook 04, loaded from the shared file rather than
    # restated here. This notebook calibrates the pass-through coefficients that
    # notebook set by hand.
    include(joinpath(@__DIR__, "..", "..", "pluto_tutorial", "canvas_model.jl"))
    "CANVASModel, its pricing override and build_canvas_model loaded ✓"
end

# ╔═╡ fe47a43e-aeb2-11f1-8236-cf09de2a48a6
begin
    # Simulator: plain forward run at θ, returns concatenated [inflation; gdp_growth] (2T values).
    # Following Wiese et al. (2023) — raw trajectories, no hand-crafted statistics.
    function summarise(θ; seed=1, N=N_paths, T=T_sim, p=parameters, ic=init_cond)
        CANVAS_PHI[] = θ
        Random.seed!(seed)
        ms = Bit.ensemblerun!((build_canvas_model(p, ic) for _ in 1:N), T)

        _defl(m) = m.data.nominal_gdp ./ m.data.real_gdp
        inflation = mean([diff(_defl(m))     ./ _defl(m)[1:end-1]      for m in ms])
        gdp_growth = mean([diff(m.data.real_gdp) ./ m.data.real_gdp[1:end-1] for m in ms])

        return vcat(inflation, gdp_growth)   # 2T-dimensional vector
    end

    "Simulator function defined ✓"
end

# ╔═╡ fe47a448-aeb2-11f1-8128-47d32eec72fc
md"""
---
## 4 — Generate observed data at the true θ
"""

# ╔═╡ fe47a45c-aeb2-11f1-8796-d9a46d0f705f
@bind run_xobs PlutoUI.Button("▶ Generate x_obs at true θ (1–2 min)")

# ╔═╡ fe47a470-aeb2-11f1-b509-5733fe3f376e
begin
    run_xobs
    x_obs = summarise(θ_true, seed=42, N=N_obs)
    T_obs = T_sim
    p_infl = plot(x_obs[1:T_obs] .* 100,
        xlabel="Quarter", ylabel="Inflation (%)", title="GDP deflator inflation",
        label="", lw=2, color=:steelblue, marker=:circle, markersize=3)
    hline!(p_infl, [0], lw=1, color=:black, linestyle=:dash, label="")
    p_gdp = plot(x_obs[T_obs+1:end] .* 100,
        xlabel="Quarter", ylabel="Growth (%)", title="Real GDP growth",
        label="", lw=2, color=:darkorange, marker=:circle, markersize=3)
    hline!(p_gdp, [0], lw=1, color=:black, linestyle=:dash, label="")
    plot(p_infl, p_gdp, layout=(1,2), size=(800,300),
         plot_title="x_obs at true θ=$(θ_true)")
end

# ╔═╡ fe47a484-aeb2-11f1-ab62-c9fb038b7b75
md"""
---
## 5 — Approximate Bayesian Computation (ABC baseline)

ABC accepts simulations where $\|x_{\text{sim}} - x_{\text{obs}}\| < \epsilon$.

This is the simplest likelihood-free method — and the least efficient. The acceptance rate drops exponentially as the dimension of $\theta$ grows. For the 3-parameter problem here, we need a large simulation budget.
"""

# ╔═╡ fe47a48e-aeb2-11f1-ba58-7f92563411e7
@bind run_abc PlutoUI.Button("▶ Run ABC (100 simulations, ~5 min)")

# ╔═╡ fe47a4a2-aeb2-11f1-b008-a52edb0e1db3
begin
    run_abc

    N_abc = 100
    # ε is in the same units as the 2T-dim trajectory norm. Calibrated by
    # measurement rather than by a scale argument: at scale 0.0001 with
    # T_sim = 12, ‖x_obs‖ ≈ 0.085, and ‖x_sim - x_obs‖ is 0.0196 ± 0.003 at
    # the true θ against 0.0459 ± 0.006 at a badly wrong one. ε = 0.03 sits
    # between them — over 12 replications it accepted 12/12 at the true θ and
    # 0/12 at the wrong θ.
    ε = 0.03

    Random.seed!(808)
    prior_samples = [(dp = rand(), cp = rand(), ae = rand()) for _ in 1:N_abc]
    abc_accepted  = NamedTuple{(:dp,:cp,:ae)}[]

    # Seed by loop index, matching the NPE section below. The previous version
    # used seed = rand(1:1000): `summarise` reseeds the global RNG on every
    # call, so each draw came from a stream that call had just reset, and 100
    # draws from 1000 values collide with ~99% probability — different θ
    # silently sharing a random stream.
    for (i, θ) in enumerate(prior_samples)
        x_sim = summarise(θ; seed = 1000 + i, N = N_paths)
        dist  = norm(x_sim .- x_obs)
        if dist < ε
            push!(abc_accepted, θ)
        end
    end

    n_accepted = length(abc_accepted)
    accept_rate = n_accepted / N_abc * 100

    md"""
    ABC: **$(n_accepted) / $(N_abc)** samples accepted ($(round(accept_rate, digits=1))% acceptance rate, ε=$(ε)).

    A higher ε gives more accepted samples but a looser posterior.
    A lower ε gives a tighter posterior but fewer samples.
    With 3 parameters, the curse of dimensionality means you need an enormous simulation budget to get a useful posterior — this is why NPE (Section 6) is so much more efficient.
    """
end

# ╔═╡ fe47a4ac-aeb2-11f1-aad4-dbf9faa34303
begin
    run_abc
    if length(abc_accepted) >= 3
        dp_vals = [s.dp for s in abc_accepted]
        cp_vals = [s.cp for s in abc_accepted]
        ae_vals = [s.ae for s in abc_accepted]

        p1_abc = histogram(dp_vals, bins=10, title="ABC posterior: ϕ^DP",
                       xlabel="ϕ^DP", label="", color=:steelblue, alpha=0.7)
        vline!(p1_abc, [θ_true.dp], lw=2, color=:red, label="True")
        p2_abc = histogram(cp_vals, bins=10, title="ABC posterior: ϕ^CP",
                       xlabel="ϕ^CP", label="", color=:steelblue, alpha=0.7)
        vline!(p2_abc, [θ_true.cp], lw=2, color=:red, label="True")
        p3_abc = histogram(ae_vals, bins=10, title="ABC posterior: ϕ^AE",
                       xlabel="ϕ^AE", label="", color=:steelblue, alpha=0.7)
        vline!(p3_abc, [θ_true.ae], lw=2, color=:red, label="True")
        plot(p1_abc, p2_abc, p3_abc, layout=(1,3), size=(800, 280))
    else
        md"Not enough ABC samples accepted — try increasing ε or N_abc."
    end
end

# ╔═╡ fe47a4c8-aeb2-11f1-b2eb-316721706547
md"""
---
## 6 — Neural Posterior Estimation (NPE): the key idea

Lecture 2 describes NPE from Dyer et al. (2024):

1. **Sample** $\theta_i \sim p(\theta)$ (prior), **simulate** $x_i \sim \text{ABM}(\theta_i)$ — build dataset $\{(\theta_i, x_i)\}$.
2. **Train** a neural network $q_\phi(\theta \mid x)$ (a normalising flow) on this dataset:
   $$\hat\phi = \arg\max_\phi \sum_i \log q_\phi(\theta_i \mid x_i)$$
3. **Query** at the observed data: sample $\theta \sim q_{\hat\phi}(\theta \mid x_{\text{obs}})$.

The network learns a **density** over $\theta$ conditioned on $x$. Once trained (offline), it is amortised: any new $x_{\text{obs}}$ gets an instant posterior without rerunning the ABM.

**Sequential NPE (SNPE)** iteratively refines by using the current posterior as the next proposal, concentrating simulations near the posterior mode. The Lecture 2 algorithm box shows the importance-reweighted loss that corrects for the shifted proposal.
"""

# ╔═╡ fe47a4de-aeb2-11f1-a8a6-8dd6f18757b5
md"""
---
## 7 — Running SNPE and SNRE with Python `sbi` via PythonCall

We call the [Mackelab `sbi` package](https://github.com/mackelab/sbi) directly from Julia using `PythonCall.jl`.
`CondaPkg.toml` in this directory declares `sbi>=0.23` as a pip dependency — Julia resolves it automatically.

Two algorithms:
- **SNPE-C** (`sbi.inference.SNPE`): fits a normalising flow $q_\phi(\theta \mid x)$ by maximum likelihood on simulated pairs. Posterior evaluation is cheap (one forward pass).
- **SNRE-B** (`sbi.inference.SNRE`): trains a binary classifier to distinguish joint draws $(\theta, x) \sim p(\theta)p(x|\theta)$ from marginal draws $(\theta, x) \sim p(\theta)p(x)$. The log-ratio approximates $\log p(x|\theta)/p(x)$. Sampling requires MCMC because only the unnormalised ratio is available.

**Workflow (both methods share steps 1–2):**
1. Import `sbi` via PythonCall and define a uniform prior.
2. Generate `N_sbi` simulation pairs $\{(\theta_i, x_i)\}$ entirely in Julia, then hand the arrays to `sbi`.
3. Train the density estimator / classifier.
4. Draw posterior samples and plot.
"""

# ╔═╡ fe47a4e8-aeb2-11f1-a0c6-cf432609d50c
begin
    _torch     = pyimport("torch")
    _np        = pyimport("numpy")
    _sbi_inf   = pyimport("sbi.inference")
    _sbi_utils = pyimport("sbi.utils")
    _mcmc_par  = pyimport("sbi.inference.posteriors.posterior_parameters").MCMCPosteriorParameters
    md"Python `sbi` imports ✓  (torch $(pyconvert(String, _torch.__version__)))"
end

# ╔═╡ fe47a4f2-aeb2-11f1-b056-f167b82071b2
md"""
---
### Step 1 — Generate simulation pairs $\{(\theta_i, x_i)\}$

We draw $\theta_i \sim \text{Uniform}([0,1]^3)$ and evaluate the `summarise` function in Julia.
The resulting matrices are converted to PyTorch tensors via NumPy's buffer protocol.

> **Note:** 500 simulations at `N_paths = 8` MC paths each takes roughly 5–10 minutes.
> Increase `N_sbi` for a tighter posterior; decrease for quick exploration.
"""

# ╔═╡ fe47a506-aeb2-11f1-a7b7-5308423c8cfe
@bind run_sbi_sims PlutoUI.Button("▶ Step 1 — Generate simulations (~5–10 min)")

# ╔═╡ fe47a510-aeb2-11f1-a698-ef70514f417b
begin
    run_sbi_sims

    N_sbi = 500
    Random.seed!(99)
    _θ_sbi, _x_sbi, _n_failed = let
        θs = NamedTuple{(:dp,:cp,:ae),Tuple{Float64,Float64,Float64}}[]
        xs = Vector{Float32}[]
        n  = 0
        for i in 1:N_sbi
            θ = (dp=rand(), cp=rand(), ae=rand())
            try
                x = Float32.(summarise(θ; N=N_paths, seed=i))
                if !any(isnan, x) && !any(isinf, x)
                    push!(θs, θ); push!(xs, x)
                else
                    n += 1
                end
            catch
                n += 1
            end
        end
        θs, xs, n
    end

    # Build (N, 3) and (N, 2T) Float32 matrices
    _θ_mat = Float32.(reduce(vcat, [[t.dp t.cp t.ae] for t in _θ_sbi]))  # N×3
    _x_mat = Float32.(reduce(vcat, [x' for x in _x_sbi]))                # N×(2T)

    # Convert to PyTorch tensors via NumPy (PythonCall supports Julia array buffer protocol)
    _θ_tensor   = _torch.from_numpy(_np.asarray(_θ_mat, dtype=_np.float32))
    _x_tensor   = _torch.from_numpy(_np.asarray(_x_mat, dtype=_np.float32))
    _x_obs_t    = _torch.tensor(Float32.(x_obs)).unsqueeze(0)  # shape (1, 2T)

    _sbi_prior = _sbi_utils.BoxUniform(
        low  = _torch.zeros(3, dtype=_torch.float32),
        high = _torch.ones(3, dtype=_torch.float32)
    )

    md"Generated **$(length(_θ_sbi)) / $(N_sbi)** simulation pairs ✓  ($(_n_failed) skipped due to NaN/error)"
end

# ╔═╡ fe47a51a-aeb2-11f1-b61f-b1712369fe7d
md"""
---
### Step 2a — SNPE-C (Sequential Neural Posterior Estimation)

`sbi` trains a **masked autoregressive flow** (MAF) as the density estimator.
After training we call `posterior.sample(n, x=x_obs)` — no MCMC needed, one forward pass.
"""

# ╔═╡ fe47a52e-aeb2-11f1-850a-c7a03de04063
@bind run_snpe PlutoUI.Button("▶ Step 2a — Train SNPE and sample (~1–2 min)")

# ╔═╡ fe47a538-aeb2-11f1-ac52-bdf95b720ba4
begin
    run_snpe; run_sbi_sims   # ensure simulations exist

    # Seed torch as well as Julia: Random.seed!(99) above fixes the simulated
    # training pairs, but the flow's weight initialisation and batch shuffling
    # come from torch's RNG. Without this the posterior moves between runs.
    _torch.manual_seed(0)
    snpe_engine  = _sbi_inf.SNPE(prior=_sbi_prior)
    snpe_engine.append_simulations(_θ_tensor, _x_tensor)
    snpe_de      = snpe_engine.train()
    snpe_post_py = snpe_engine.build_posterior(snpe_de)

    snpe_raw     = snpe_post_py.sample([1000], x=_x_obs_t)
    snpe_samples = pyconvert(Matrix{Float64}, snpe_raw.detach().cpu().numpy())

    md"SNPE: **$(size(snpe_samples, 1)) posterior samples** drawn ✓"
end

# ╔═╡ fe47a542-aeb2-11f1-86f9-154ba253a889
begin
    run_snpe; run_sbi_sims
    if @isdefined(snpe_samples) && size(snpe_samples, 1) >= 2
        p1_snpe = histogram(snpe_samples[:,1], bins=30, normalize=true,
                       title="SNPE posterior: ϕ^DP", xlabel="ϕ^DP",
                       label="Posterior", color=:steelblue, alpha=0.7)
        vline!(p1_snpe, [θ_true.dp], lw=2, color=:red, label="True")
        p2_snpe = histogram(snpe_samples[:,2], bins=30, normalize=true,
                       title="SNPE posterior: ϕ^CP", xlabel="ϕ^CP",
                       label="", color=:steelblue, alpha=0.7)
        vline!(p2_snpe, [θ_true.cp], lw=2, color=:red, label="True")
        p3_snpe = histogram(snpe_samples[:,3], bins=30, normalize=true,
                       title="SNPE posterior: ϕ^AE", xlabel="ϕ^AE",
                       label="", color=:steelblue, alpha=0.7)
        vline!(p3_snpe, [θ_true.ae], lw=2, color=:red, label="True")
        plot(p1_snpe, p2_snpe, p3_snpe, layout=(1,3), size=(800, 280), plot_title="SNPE-C posterior")
    else
        md"Run SNPE first (Step 2a)."
    end
end

# ╔═╡ fe47a560-aeb2-11f1-9155-67117e02ae01
md"""
---
### Step 2b — SNRE-B (Sequential Neural Ratio Estimation)

SNRE trains a **binary classifier** $d_\phi(\theta, x)$ to distinguish joint samples from product-of-marginals samples.
The Bayes-optimal classifier satisfies:

$$d_\phi(\theta, x) = \frac{p(\theta, x)}{p(\theta, x) + p(\theta)p(x)} \implies \log\frac{d_\phi}{1-d_\phi} = \log\frac{p(x|\theta)}{p(x)}$$

Because we only have the unnormalised ratio, sampling requires **MCMC** (here: slice sampling).
This makes SNRE slower at sample time but it can be more robust when the summary statistic space is complex.
"""

# ╔═╡ fe47a574-aeb2-11f1-b9d3-15da0a71e396
@bind run_snre PlutoUI.Button("▶ Step 2b — Train SNRE and sample via MCMC (~3–5 min)")

# ╔═╡ fe47a57e-aeb2-11f1-b49a-35077214ebb5
begin
    run_snre; run_sbi_sims   # ensure simulations exist

    _torch.manual_seed(0)   # see the note in the SNPE cell
    snre_engine  = _sbi_inf.SNRE(prior=_sbi_prior)
    snre_engine.append_simulations(_θ_tensor, _x_tensor)
    snre_cls     = snre_engine.train()
    # sbi 0.26 deprecates the mcmc_parameters dict in favour of a typed
    # PosteriorParameters object; the old form still works but warns and is
    # slated for removal.
    snre_post_py = snre_engine.build_posterior(
        snre_cls,
        mcmc_method          = "slice_np_vectorized",
        posterior_parameters = _mcmc_par(num_chains = 4, thin = 5, warmup_steps = 100)
    )

    # Reseed before sampling: training above consumed the torch stream, and the
    # slice sampler draws proposals from NumPy's RNG and chain inits from
    # torch's. Seeding both is required — either alone still varies run to run.
    _torch.manual_seed(0)
    _np.random.seed(0)
    snre_raw     = snre_post_py.sample([200], x=_x_obs_t)   # MCMC → fewer samples
    snre_samples = pyconvert(Matrix{Float64}, snre_raw.detach().cpu().numpy())

    md"SNRE: **$(size(snre_samples, 1)) posterior samples** via MCMC ✓"
end

# ╔═╡ fe47a588-aeb2-11f1-8e59-3947a4232ada
begin
    run_snre; run_sbi_sims
    if @isdefined(snre_samples) && size(snre_samples, 1) >= 2
        p1_snre = histogram(snre_samples[:,1], bins=20, normalize=true,
                       title="SNRE posterior: ϕ^DP", xlabel="ϕ^DP",
                       label="Posterior", color=:darkorange, alpha=0.7)
        vline!(p1_snre, [θ_true.dp], lw=2, color=:red, label="True")
        p2_snre = histogram(snre_samples[:,2], bins=20, normalize=true,
                       title="SNRE posterior: ϕ^CP", xlabel="ϕ^CP",
                       label="", color=:darkorange, alpha=0.7)
        vline!(p2_snre, [θ_true.cp], lw=2, color=:red, label="True")
        p3_snre = histogram(snre_samples[:,3], bins=20, normalize=true,
                       title="SNRE posterior: ϕ^AE", xlabel="ϕ^AE",
                       label="", color=:darkorange, alpha=0.7)
        vline!(p3_snre, [θ_true.ae], lw=2, color=:red, label="True")
        plot(p1_snre, p2_snre, p3_snre, layout=(1,3), size=(800, 280), plot_title="SNRE-B posterior")
    else
        md"Run SNRE first (Step 2b)."
    end
end

# ╔═╡ fe47a59e-aeb2-11f1-80fd-7da834c0a7bf
md"""
The NPE/NRE posteriors are **much tighter** than the ABC posterior, concentrated near the true values, using far fewer simulations (500 vs the millions ABC would need for comparable quality).

| Method | Simulation budget | Sampling cost | Posterior type |
|--------|------------------|---------------|----------------|
| ABC    | high (millions for dim > 2) | O(1) once accepted | histogram |
| SNPE-C | medium (500–10k) | cheap (flow forward pass) | full density |
| SNRE-B | medium (500–10k) | slow (MCMC per query) | unnormalised ratio |

The key advantage highlighted in Lecture 2: both NPE and NRE recover the **full posterior** (not just a point estimate), enabling proper uncertainty quantification of the pass-through coefficients.
"""

# ╔═╡ fe47a5a6-aeb2-11f1-aac1-bbb9e8e11248
md"""
---
## ✔ What you learned

- ABM likelihoods are intractable — you can simulate but not evaluate $p(x \mid \theta)$.
- **ABC** works but is exponentially inefficient in parameter dimension (curse of dimensionality).
- **SNPE-C** trains a conditional normalising flow $q_\phi(\theta \mid x)$ offline, then queries it instantly for any $x_{\text{obs}}$.
- **SNRE-B** trains a classifier whose log-ratio approximates the log-likelihood ratio; sampling uses MCMC.
- Both are called via `PythonCall.jl` wrapping the Mackelab `sbi` package — simulations are generated in Julia, arrays handed to Python.
- The simulator function `θ → x` is the bridge between BeforeIT and any SBI library.

---
## Further reading

- Dyer, J. et al. (2024). *Black-box Bayesian inference for economic agent-based models.* — the paper behind the Lecture 2 SBI slides.
- `github.com/joelnmdyer/sbi4abm` — code, examples, tutorial.
- `github.com/mackelab/sbi` — the Python SBI library used here.
- Cranmer, K. et al. (2020). *The frontier of simulation-based inference.* PNAS — broader review.

---
## Exercises

**Exercise 08.1** — Add a 5th summary statistic to the `summarise` function (e.g., the slope of the excess inflation series: `(excess[end] - excess[1]) / T`). Does this extra information narrow the posterior?

**Exercise 08.2** — Change $N_{\text{ABC}}$ from 100 to 500 and ε from 0.015 to 0.010. How does the acceptance rate change? How does the posterior tighten?

**Exercise 08.3** — Increase `N_sbi` to 2000 and re-run Steps 1 and 2a. How does the SNPE posterior width compare?

**Exercise 08.4** *(stretch)* — Run two rounds of sequential SNPE: after the first round, use the posterior as the proposal for a second round of 500 simulations. See the `sbi` docs for `append_simulations(..., proposal=posterior)`.
"""

# ╔═╡ Cell order:
# ╟─fe46785c-aeb2-11f1-b29c-f9f57fb156bb
# ╠═fe47a376-aeb2-11f1-b61a-afb43896f469
# ╟─fe47a3e4-aeb2-11f1-8672-87cfc7b65656
# ╟─fe47a3f8-aeb2-11f1-bb78-fdae608fd8dd
# ╠═fe47a416-aeb2-11f1-9746-851acfeb8207
# ╟─fe47a420-aeb2-11f1-8d8a-abc5ec0d8da6
# ╠═fe47a436-aeb2-11f1-9b2a-3f8bba375ef7
# ╠═fe47a43e-aeb2-11f1-8236-cf09de2a48a6
# ╟─fe47a448-aeb2-11f1-8128-47d32eec72fc
# ╠═fe47a45c-aeb2-11f1-8796-d9a46d0f705f
# ╠═fe47a470-aeb2-11f1-b509-5733fe3f376e
# ╟─fe47a484-aeb2-11f1-ab62-c9fb038b7b75
# ╠═fe47a48e-aeb2-11f1-ba58-7f92563411e7
# ╠═fe47a4a2-aeb2-11f1-b008-a52edb0e1db3
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
# ╟─fe47a59e-aeb2-11f1-80fd-7da834c0a7bf
# ╟─fe47a5a6-aeb2-11f1-aac1-bbb9e8e11248
