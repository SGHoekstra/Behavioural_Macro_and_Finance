# Regenerate the saved small-budget teaching run and its four figures.
# Runs the notebook's actual simulation/inference cells; no separate simulator.
# Usage: julia --project=pluto_tutorial PlutoPages/tools/generate_notebook05_demo.jl
# First-time Python/PyTorch installation can take several minutes.
# Add --check to validate source syntax and controls without loading dependencies.
# Add --render-only to redraw an existing dataset without simulations or Python.
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
elseif !(isempty(ARGS) || ARGS == ["--render-only"])
    error("Supported options: --check or --render-only.")
end

using Dates, SHA
ENV["GKSwstype"] = "100"
output = joinpath(root, "pluto_tutorial", "notebook05_demo.jld2")

function validate_demo(data)
    @assert (data["T_sim"], data["N_paths"], data["N_abc"], data["N_sbi"]) == (12, 4, 100, 200)
    @assert length(data["x_obs"]) == 24 && all(isfinite, data["x_obs"])
    abc = data["abc_bank"]
    @assert length(abc.parameters) == data["N_abc"] && length(abc.distances) == data["N_abc"]
    @assert all(isfinite, abc.distances)
    bank = data["sbi_bank"]
    @assert isempty(bank.failures) "Failed training simulations must be diagnosed, not dropped."
    @assert length(bank.parameters) == data["N_sbi"] && length(bank.outputs) == data["N_sbi"]
    @assert all(x -> length(x) == 24 && all(isfinite, x), bank.outputs)
    for (name, rows) in (("snpe_samples", 1000), ("snre_samples", 200))
        samples = data[name]
        @assert size(samples) == (rows, 3) && all(isfinite, samples)
        @assert all(v -> 0 <= v <= 1, samples)
    end
    accepted = abc.parameters[abc.distances .< data["ε"]]
    @assert length(accepted) >= 3 "Too few ABC draws at the saved tolerance to render the marginal figure."
    return accepted
end

function render_demo!(data, output, source, root)
    accepted = validate_demo(data)
    horizon = data["T_sim"]
    observation = data["x_obs"]
    truth = data["θ_true"]
    true_values = (truth.dp, truth.cp, truth.ae)
    channels = ("demand pull", "cost push", "expectations")
    axis_labels = ("ϕ^DP", "ϕ^CP", "ϕ^AE")
    style = (; bottom_margin=6Plots.mm, left_margin=4Plots.mm, top_margin=4Plots.mm,
        guidefontsize=10, tickfontsize=9, titlefontsize=12, legend=false)

    inflation_plot = Plots.plot(1:horizon, 100 .* observation[1:horizon];
        xlabel="Quarter", ylabel="Inflation (%)", title="GDP-deflator inflation",
        lw=2, color=:steelblue, marker=:circle, markersize=3, style...)
    Plots.hline!(inflation_plot, [0]; color=:black, linestyle=:dash, label="")
    growth_plot = Plots.plot(1:horizon, 100 .* observation[(horizon + 1):end];
        xlabel="Quarter", ylabel="Growth (%)", title="Real GDP growth",
        lw=2, color=:darkorange, marker=:circle, markersize=3, style...)
    Plots.hline!(growth_plot, [0]; color=:black, linestyle=:dash, label="")

    function marginal_figure(columns, method, color; density)
        panels = map(1:3) do column
            title = method == "ABC" ? uppercasefirst(channels[column]) : "$method: $(channels[column])"
            panel = Plots.histogram(columns[column]; bins=density ? 20 : 10,
                normalize=density, xlims=(0, 1), title, xlabel=axis_labels[column],
                ylabel=density ? "Density" : "Accepted draws", color, alpha=0.7, style...)
            Plots.vline!(panel, [true_values[column]]; color=:red, lw=2, label="")
            panel
        end
        return Plots.plot(panels...; layout=(1, 3), size=(1050, 420))
    end

    figures = (
        "observation.png" => Plots.plot(inflation_plot, growth_plot; layout=(1, 2), size=(1050, 420)),
        "abc.png" => marginal_figure([[getproperty(draw, field) for draw in accepted]
            for field in (:dp, :cp, :ae)], "ABC", :steelblue; density=false),
        "npe.png" => marginal_figure([data["snpe_samples"][:, column] for column in 1:3],
            "NPE", :steelblue; density=true),
        "nre.png" => marginal_figure([data["snre_samples"][:, column] for column in 1:3],
            "NRE-B", :darkorange; density=true),
    )
    figure_dir = joinpath(root, "pluto_tutorial", "notebook05_figures")
    mkpath(figure_dir)
    for (filename, figure) in figures
        Plots.savefig(figure, joinpath(figure_dir, filename))
    end

    # Preserve the simulation/training provenance and change rendering metadata only.
    metadata = data["metadata"]
    metadata["figure_sha256"] = Dict(filename => bytes2hex(sha256(read(joinpath(figure_dir, filename))))
        for (filename, _) in figures)
    metadata["rendered_at"] = string(now(UTC)) * "Z"
    metadata["render_git_commit"] = String(strip(read(`git -C $root rev-parse HEAD`, String)))
    metadata["render_julia"] = string(VERSION)
    metadata["render_plots"] = string(Base.pkgversion(Plots))
    JLD2.jldsave(output; (Symbol(key) => value for (key, value) in data)...)
    reloaded = JLD2.load(output)
    @assert all(key -> key == "metadata" || isequal(data[key], reloaded[key]), keys(data)) "Rendering changed saved numerical results."

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
    println("Saved ", output, " (", filesize(output), " bytes) and four rendered PNG figures.")
    println("ABC accepted ", length(accepted), "/", data["N_abc"], " at ε=", data["ε"],
        "; NPE/NRE shapes ", size(data["snpe_samples"]), " / ", size(data["snre_samples"]), ".")
    flush(stdout)
    return nothing
end

if ARGS == ["--render-only"]
    import JLD2, Plots
    println("Rendering existing numerical results only; no simulations, training or Python setup.")
    data = JLD2.load(output)
    render_demo!(data, output, source, root)
    exit(0)
end

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
)
data = Dict("metadata" => metadata, "θ_true" => θ_true, "T_sim" => T_sim,
    "N_paths" => N_paths, "N_abc" => N_abc, "N_sbi" => N_sbi, "ε" => ε,
    "x_obs" => x_obs, "abc_bank" => abc_bank, "sbi_bank" => sbi_bank,
    "snpe_samples" => snpe_samples, "snre_samples" => snre_samples)
render_demo!(data, output, source, root)
