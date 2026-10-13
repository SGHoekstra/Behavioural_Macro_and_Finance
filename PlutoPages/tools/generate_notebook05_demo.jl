# Regenerate the saved small-budget teaching run and its four figures.
# Runs the notebook's actual simulation/inference cells; no separate simulator.
# Usage: julia --project=pluto_tutorial PlutoPages/tools/generate_notebook05_demo.jl
# First-time Python/PyTorch installation can take several minutes.
# Add --check to validate source syntax and controls without loading dependencies.
function assert_parseable(text, label)
    function walk(expression)
        expression isa Expr || return
        if expression.head in (:error, :incomplete)
            detail = isempty(expression.args) ? "Incomplete expression" : first(expression.args)
            message = detail isa Exception ? sprint(showerror, detail) : string(detail)
            error("$label has a syntax error:\n$message")
        end
        foreach(walk, expression.args)
    end
    walk(Meta.parseall(text))
    return nothing
end
assert_parseable(read(@__FILE__, String), "Generator")

root = normpath(joinpath(@__DIR__, "..", ".."))
source = joinpath(root, "pluto_tutorial", "05_likelihood_free_calibration.jl")
source_code = read(source, String)
code = replace(source_code,
    r"(?ms)^# ╔═╡ f0050000-0000-4000-8000-000000000004\r?\n.*?(?=^# ╔═╡ |\z)" => "",
    r"(?m)^# [╠╟][═─]f0050000-0000-4000-8000-000000000004\r?\n?" => "")
# Regeneration must work without an earlier saved result or its PNG files.
count("PlutoUI.CheckBox(default=false)", code) == 1 ||
    error("Expected exactly one inference-enable checkbox.")
code = replace(code, "PlutoUI.CheckBox(default=false)" => "PlutoUI.CheckBox(default=true)")
for name in ("run_xobs", "run_abc", "run_sbi_sims", "run_snpe", "run_snre")
    pattern = Regex("(?m)^@bind " * name * raw" PlutoUI.CounterButton\([^\n]*\)$")
    length(collect(eachmatch(pattern, code))) == 1 ||
        error("Expected exactly one execution control: $name")
    global code = replace(code, pattern => "$name = 1")
end
assert_parseable(code, "Transformed notebook")
if ARGS == ["--check"]
    println("PASS: generator/notebook syntax, saved-cell removal and all five execution controls.")
    exit(0)
elseif !isempty(ARGS)
    error("Only the optional --check argument is supported.")
end

using Dates, SHA
ENV["GKSwstype"] = "100"
println("Running the notebook's five stages at ", now(UTC), " UTC.")
flush(stdout)
try
    # The filename preserves @__DIR__/Pkg.activate/include paths in the notebook.
    Base.include_string(Main, code, source)
catch err
    if isdefined(Main, :sbi_bank) && sbi_bank !== nothing && !isempty(sbi_bank.failures)
        println(stderr, "Neural training bank failures:")
        foreach(message -> println(stderr, message), sbi_bank.failures)
    end
    if isdefined(Main, :CANVAS_PHI)
        println(stderr, "Last active pricing coefficients: ", CANVAS_PHI[])
    end
    rethrow()
end

import JLD2
@assert T_sim == 12 && N_paths == 4 && N_abc == 100 && N_sbi == 200 "Demo budgets changed; inspect the protocol before saving."
@assert length(x_obs) == 24 && all(isfinite, x_obs)
@assert length(abc_bank.parameters) == N_abc && length(abc_bank.distances) == N_abc
@assert all(isfinite, abc_bank.distances)
@assert isempty(sbi_bank.failures) "Failed training simulations must be diagnosed, not dropped."
@assert length(sbi_bank.parameters) == N_sbi && length(sbi_bank.outputs) == N_sbi
@assert all(x -> length(x) == 24 && all(isfinite, x), sbi_bank.outputs)
@assert size(snpe_samples) == (1000, 3) && all(isfinite, snpe_samples)
@assert size(snre_samples) == (200, 3) && all(isfinite, snre_samples)
@assert all(v -> 0 <= v <= 1, snpe_samples) && all(v -> 0 <= v <= 1, snre_samples)
@assert n_accepted >= 3 "Too few ABC draws at the default tolerance to render the marginal figure."

figure_dir = joinpath(root, "pluto_tutorial", "notebook05_figures")
mkpath(figure_dir)
figures = (
    "observation.png" => Plots.plot(p_infl, p_gdp; layout=(1, 2), size=(800, 300),
        plot_title="Synthetic observation: $(N_obs)-path average"),
    "abc.png" => Plots.plot(p1_abc, p2_abc, p3_abc; layout=(1, 3), size=(800, 280),
        plot_title="ABC: $(n_accepted)/$(N_abc) accepted at ε=$(ε)"),
    "npe.png" => Plots.plot(p1_snpe, p2_snpe, p3_snpe; layout=(1, 3), size=(800, 280)),
    "nre.png" => Plots.plot(p1_snre, p2_snre, p3_snre; layout=(1, 3), size=(800, 280)),
)
for (filename, figure) in figures
    Plots.savefig(figure, joinpath(figure_dir, filename))
end

py_metadata = PythonCall.pyimport("importlib.metadata")
metadata = Dict(
    "generated_at" => string(now(UTC)) * "Z",
    "julia" => string(VERSION),
    "beforeit" => string(Base.pkgversion(Bit)),
    "python" => PythonCall.pyconvert(String, PythonCall.pyimport("sys").version),
    "sbi" => PythonCall.pyconvert(String, py_metadata.version("sbi")),
    "torch" => PythonCall.pyconvert(String, _torch.__version__),
    "numpy" => PythonCall.pyconvert(String, _np.__version__),
    "canvas_sha256" => bytes2hex(sha256(read(joinpath(root, "pluto_tutorial", "canvas_model.jl")))),
    "notebook_source_sha256" => bytes2hex(sha256(source_code)),
    "executed_source_sha256" => bytes2hex(sha256(code)),
    "source_git_commit" => strip(read(`git -C $root rev-parse HEAD`, String)),
    "observation_seed" => 42,
    "abc_draw_seed" => 808,
    "abc_simulation_seeds" => collect(10_001:(10_000 + N_abc)),
    "sbi_draw_seed" => 99,
    "sbi_simulation_seeds" => collect(20_001:(20_000 + N_sbi)),
    "network_seed" => 0,
    "nre_sampling_seed" => 0,
    "numpy_mcmc_seed" => 0,
    "figure_sha256" => Dict(filename => bytes2hex(sha256(read(joinpath(figure_dir, filename))))
        for (filename, _) in figures),
)
output = joinpath(root, "pluto_tutorial", "notebook05_demo.jld2")
JLD2.jldsave(output; metadata, θ_true, T_sim, N_paths, N_abc, N_sbi, ε,
    x_obs, abc_bank, sbi_bank, snpe_samples, snre_samples)

# PlutoSliderServer caches notebook contents rather than external data files.
fingerprint = "# Saved demo SHA256: " * bytes2hex(sha256(read(output)))
current = read(source, String)
if occursin(r"(?m)^# Saved demo SHA256:.*$", current)
    current = replace(current, r"(?m)^# Saved demo SHA256:.*$" => fingerprint)
else
    occursin(r"(?m)^# v[^\r\n]+$", current) || error("Notebook version header not found.")
    current = replace(current, r"(?m)^# v[^\r\n]+$" => header -> header * "\n" * fingerprint; count=1)
end
write(source, current)
println("Saved ", output, " (", filesize(output), " bytes) and four PNG figures.")
println("ABC accepted ", n_accepted, "/", N_abc, " at ε=", ε,
    "; NPE/NRE shapes ", size(snpe_samples), " / ", size(snre_samples), ".")
flush(stdout)
