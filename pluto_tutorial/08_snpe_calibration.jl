### A Pluto.jl notebook ###
# v0.20.24

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

# ╔═╡ 08000000-0000-0000-0000-000000000001
begin
    import Pkg
    Pkg.activate(dirname(@__FILE__))
    import BeforeIT as Bit
    using Plots, PlutoUI, Statistics, Distributions, LinearAlgebra, Random, Dates
    using PythonCall
end

# ╔═╡ 08000000-0000-0000-0000-000000000002
md"""
# Notebook 08 — Calibrating Free Parameters with Simulation-Based Inference *(Advanced)*

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

# ╔═╡ 08000000-0000-0000-0000-000000000003
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

# ╔═╡ 08000000-0000-0000-0000-000000000004
md"""
---
## 2 — Define the target parameters and observed data

We calibrate the three CANVAS pass-through coefficients from Notebook 07:

$$\theta = (\phi^{DP},\, \phi^{CP},\, \phi^{AE}) \in [0, 1]^3$$

**Observed data $x_{\text{obs}}$:** the macroeconomic time series produced by a forward run of the model at the true $\theta$. Following Wiese et al. (2023), we pass raw trajectories directly to the neural network rather than hand-crafted scalars — the network learns which features identify the parameters.

Note that averaging over Monte Carlo paths *is* itself a summary-statistic choice: it discards the cross-path dispersion, so any parameter identified mainly through volatility rather than through the mean path will be harder to recover here.

We use two observable series over $T$ quarters:
- Quarter-by-quarter **GDP deflator inflation** (period-over-period price level change)
- Quarter-by-quarter **real GDP growth**

giving a $2T$-dimensional summary statistic. In a real application $x_{\text{obs}}$ would come from empirical data; here we use a synthetic simulation at known $\theta_{\text{true}}$ as the target.
"""

# ╔═╡ 08000000-0000-0000-0000-000000000005
begin
    # Scale=0.0001 gives ~62 firms — fast enough for SBI simulation budgets.
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
    """Setup complete — $(length(parameters["I_s"])) firms, H_act=$(round(Int, parameters["H_act"])). True θ = $(θ_true)"""
end

# ╔═╡ 08000000-0000-0000-0000-000000000006
md"""
---
## 3 — The simulator function $\theta \mapsto x$

The simulator runs the CANVAS model at given $\theta$ for $T$ quarters and returns the concatenated inflation and real-GDP-growth time series — a $2T$-dimensional vector.
Each training simulation uses $N$ Monte Carlo paths; averaging reduces noise while keeping runtime tractable.
"""

# ╔═╡ 08000000-0000-0000-0000-000000000007
begin
    # Reuse CANVASModel and pricing override from Notebook 07
    # (copy-pasted here so notebook is self-contained)
    Bit.@object mutable struct SBIModel(Bit.Model) <: Bit.AbstractModel end
    SBI_phi = Ref((dp=1.0, cp=1.0, ae=1.0))

    function Bit.firms_expectations_and_decisions(model::SBIModel)
        firms   = model.firms; P_bar_g = model.agg.P_bar_g
        gamma_e = model.agg.gamma_e; pi_e = model.agg.pi_e
        ϕ = SBI_phi[]
        I = length(firms.G_i)
        gamma_d_i = zeros(I); pi_d_i = zeros(I)
        for i in 1:I
            es = firms.Q_s_i[i] > firms.Q_d_i[i]
            hp = firms.P_i[i] >= P_bar_g[firms.G_i[i]]
            if !es && !hp; pi_d_i[i] = firms.Q_d_i[i]/firms.Q_s_i[i]-1
            elseif !es &&  hp; gamma_d_i[i] = firms.Q_d_i[i]/firms.Q_s_i[i]-1
            elseif  es && !hp; gamma_d_i[i] = firms.Q_d_i[i]/firms.Q_s_i[i]-1
            else pi_d_i[i] = firms.Q_d_i[i]/firms.Q_s_i[i]-1
            end
        end
        Q_s_i  = firms.Q_s_i .* (1 .+ gamma_e) .* (1 .+ gamma_d_i)
        pi_c_i = Bit.cost_push_inflation(firms, model)
        new_P_i = firms.P_i .* (1 .+ ϕ.cp .* pi_c_i) .* (1 .+ ϕ.ae * pi_e) .* (1 .+ ϕ.dp .* pi_d_i)
        I_d_i, DM_d_i, N_d_i = Bit.desired_capital_material_employment(firms, Q_s_i)
        Pi_e_i = firms.Pi_i .* (1 + pi_e) * (1 + gamma_e)
        DD_e_i, K_e_i, L_e_i = Bit.expected_deposits_capital_loans(firms, model, Pi_e_i)
        DL_d_i = max.(0, -DD_e_i .- firms.D_i)
        return Q_s_i, I_d_i, DM_d_i, N_d_i, Pi_e_i, DL_d_i, K_e_i, L_e_i, new_P_i
    end

    function build_sbi_model(p, ic)
        w_act, w_inact = Bit.Workers(p, ic); firms = Bit.Firms(p, ic)
        bank = Bit.Bank(p, ic); cb = Bit.CentralBank(p, ic)
        gov = Bit.Government(p, ic); rotw = Bit.RestOfTheWorld(p, ic)
        agg = Bit.Aggregates(p, ic); prop = Bit.Properties(p, ic); data = Bit.Data()
        m = SBIModel(w_act, w_inact, firms, bank, cb, gov, rotw, agg, prop, data)
        m.firms.Q_s_i .= m.firms.Y_i   # initialise supply so demand-pull ratios are well-defined at t=1
        return m
    end

    "SBI model type defined ✓"
end

# ╔═╡ 08000000-0000-0000-0000-000000000008
begin
    # Simulator: plain forward run at θ, returns concatenated [inflation; gdp_growth] (2T values).
    # Following Wiese et al. (2023) — raw trajectories, no hand-crafted statistics.
    function summarise(θ; seed=1, N=N_paths, T=T_sim, p=parameters, ic=init_cond)
        SBI_phi[] = θ
        Random.seed!(seed)
        ms = Bit.ensemblerun!((build_sbi_model(p, ic) for _ in 1:N), T)

        _defl(m) = m.data.nominal_gdp ./ m.data.real_gdp
        inflation = mean([diff(_defl(m))     ./ _defl(m)[1:end-1]      for m in ms])
        gdp_growth = mean([diff(m.data.real_gdp) ./ m.data.real_gdp[1:end-1] for m in ms])

        return vcat(inflation, gdp_growth)   # 2T-dimensional vector
    end

    "Simulator function defined ✓"
end

# ╔═╡ 08000000-0000-0000-0000-000000000009
md"""
---
## 4 — Generate observed data at the true θ
"""

# ╔═╡ 08000000-0000-0000-0000-00000000000a
@bind run_xobs PlutoUI.Button("▶ Generate x_obs at true θ (1–2 min)")

# ╔═╡ 08000000-0000-0000-0000-00000000000b
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

# ╔═╡ 08000000-0000-0000-0000-00000000000c
md"""
---
## 5 — Approximate Bayesian Computation (ABC baseline)

ABC accepts simulations where $\|x_{\text{sim}} - x_{\text{obs}}\| < \epsilon$.

This is the simplest likelihood-free method — and the least efficient. The acceptance rate drops exponentially as the dimension of $\theta$ grows. For the 3-parameter problem here, we need a large simulation budget.
"""

# ╔═╡ 08000000-0000-0000-0000-00000000000d
@bind run_abc PlutoUI.Button("▶ Run ABC (100 simulations, ~5 min)")

# ╔═╡ 08000000-0000-0000-0000-00000000000e
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

# ╔═╡ 08000000-0000-0000-0000-00000000000f
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

# ╔═╡ 08000000-0000-0000-0000-000000000010
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

# ╔═╡ 08000000-0000-0000-0000-000000000011
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

# ╔═╡ 08000000-0000-0000-0000-000000000016
begin
    _torch     = pyimport("torch")
    _np        = pyimport("numpy")
    _sbi_inf   = pyimport("sbi.inference")
    _sbi_utils = pyimport("sbi.utils")
    md"Python `sbi` imports ✓  (torch $(pyconvert(String, _torch.__version__)))"
end

# ╔═╡ 08000000-0000-0000-0000-000000000017
md"""
---
### Step 1 — Generate simulation pairs $\{(\theta_i, x_i)\}$

We draw $\theta_i \sim \text{Uniform}([0,1]^3)$ and evaluate the `summarise` function in Julia.
The resulting matrices are converted to PyTorch tensors via NumPy's buffer protocol.

> **Note:** 500 simulations with `N=4` MC paths each takes roughly 5–10 minutes.
> Increase `N_sbi` for a tighter posterior; decrease for quick exploration.
"""

# ╔═╡ 08000000-0000-0000-0000-000000000018
@bind run_sbi_sims PlutoUI.Button("▶ Step 1 — Generate simulations (~5–10 min)")

# ╔═╡ 08000000-0000-0000-0000-000000000019
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

# ╔═╡ 08000000-0000-0000-0000-00000000001a
md"""
---
### Step 2a — SNPE-C (Sequential Neural Posterior Estimation)

`sbi` trains a **masked autoregressive flow** (MAF) as the density estimator.
After training we call `posterior.sample(n, x=x_obs)` — no MCMC needed, one forward pass.
"""

# ╔═╡ 08000000-0000-0000-0000-00000000001b
@bind run_snpe PlutoUI.Button("▶ Step 2a — Train SNPE and sample (~1–2 min)")

# ╔═╡ 08000000-0000-0000-0000-00000000001c
begin
    run_snpe; run_sbi_sims   # ensure simulations exist

    snpe_engine  = _sbi_inf.SNPE(prior=_sbi_prior)
    snpe_engine.append_simulations(_θ_tensor, _x_tensor)
    snpe_de      = snpe_engine.train()
    snpe_post_py = snpe_engine.build_posterior(snpe_de)

    snpe_raw     = snpe_post_py.sample([1000], x=_x_obs_t)
    snpe_samples = pyconvert(Matrix{Float64}, snpe_raw.detach().cpu().numpy())

    md"SNPE: **$(size(snpe_samples, 1)) posterior samples** drawn ✓"
end

# ╔═╡ 08000000-0000-0000-0000-00000000001d
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

# ╔═╡ 08000000-0000-0000-0000-00000000001e
md"""
---
### Step 2b — SNRE-B (Sequential Neural Ratio Estimation)

SNRE trains a **binary classifier** $d_\phi(\theta, x)$ to distinguish joint samples from product-of-marginals samples.
The Bayes-optimal classifier satisfies:

$$d_\phi(\theta, x) = \frac{p(\theta, x)}{p(\theta, x) + p(\theta)p(x)} \implies \log\frac{d_\phi}{1-d_\phi} = \log\frac{p(x|\theta)}{p(x)}$$

Because we only have the unnormalised ratio, sampling requires **MCMC** (here: slice sampling).
This makes SNRE slower at sample time but it can be more robust when the summary statistic space is complex.
"""

# ╔═╡ 08000000-0000-0000-0000-00000000001f
@bind run_snre PlutoUI.Button("▶ Step 2b — Train SNRE and sample via MCMC (~3–5 min)")

# ╔═╡ 08000000-0000-0000-0000-000000000020
begin
    run_snre; run_sbi_sims   # ensure simulations exist

    snre_engine  = _sbi_inf.SNRE(prior=_sbi_prior)
    snre_engine.append_simulations(_θ_tensor, _x_tensor)
    snre_cls     = snre_engine.train()
    snre_post_py = snre_engine.build_posterior(
        snre_cls,
        mcmc_method        = "slice_np_vectorized",
        mcmc_parameters = pydict(Dict("num_chains" => 4, "thin" => 5, "warmup_steps" => 100))
    )

    snre_raw     = snre_post_py.sample([200], x=_x_obs_t)   # MCMC → fewer samples
    snre_samples = pyconvert(Matrix{Float64}, snre_raw.detach().cpu().numpy())

    md"SNRE: **$(size(snre_samples, 1)) posterior samples** via MCMC ✓"
end

# ╔═╡ 08000000-0000-0000-0000-000000000021
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

# ╔═╡ 08000000-0000-0000-0000-000000000014
md"""
The NPE/NRE posteriors are **much tighter** than the ABC posterior, concentrated near the true values, using far fewer simulations (500 vs the millions ABC would need for comparable quality).

| Method | Simulation budget | Sampling cost | Posterior type |
|--------|------------------|---------------|----------------|
| ABC    | high (millions for dim > 2) | O(1) once accepted | histogram |
| SNPE-C | medium (500–10k) | cheap (flow forward pass) | full density |
| SNRE-B | medium (500–10k) | slow (MCMC per query) | unnormalised ratio |

The key advantage highlighted in Lecture 2: both NPE and NRE recover the **full posterior** (not just a point estimate), enabling proper uncertainty quantification of the pass-through coefficients.
"""

# ╔═╡ 08000000-0000-0000-0000-000000000015
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
# ╟─08000000-0000-0000-0000-000000000002
# ╠═08000000-0000-0000-0000-000000000001
# ╟─08000000-0000-0000-0000-000000000003
# ╟─08000000-0000-0000-0000-000000000004
# ╠═08000000-0000-0000-0000-000000000005
# ╟─08000000-0000-0000-0000-000000000006
# ╠═08000000-0000-0000-0000-000000000007
# ╠═08000000-0000-0000-0000-000000000008
# ╟─08000000-0000-0000-0000-000000000009
# ╠═08000000-0000-0000-0000-00000000000a
# ╠═08000000-0000-0000-0000-00000000000b
# ╟─08000000-0000-0000-0000-00000000000c
# ╠═08000000-0000-0000-0000-00000000000d
# ╠═08000000-0000-0000-0000-00000000000e
# ╠═08000000-0000-0000-0000-00000000000f
# ╟─08000000-0000-0000-0000-000000000010
# ╟─08000000-0000-0000-0000-000000000011
# ╠═08000000-0000-0000-0000-000000000016
# ╟─08000000-0000-0000-0000-000000000017
# ╠═08000000-0000-0000-0000-000000000018
# ╠═08000000-0000-0000-0000-000000000019
# ╟─08000000-0000-0000-0000-00000000001a
# ╠═08000000-0000-0000-0000-00000000001b
# ╠═08000000-0000-0000-0000-00000000001c
# ╠═08000000-0000-0000-0000-00000000001d
# ╟─08000000-0000-0000-0000-00000000001e
# ╠═08000000-0000-0000-0000-00000000001f
# ╠═08000000-0000-0000-0000-000000000020
# ╠═08000000-0000-0000-0000-000000000021
# ╟─08000000-0000-0000-0000-000000000014
# ╟─08000000-0000-0000-0000-000000000015
