# Fail the build if any exported notebook rendered without output.
#
# generate.jl only inspects PlutoPages.jl's own cells, so a content notebook
# whose first cell throws still exits 0 and produces a site of empty shells.
# A notebook that really ran embeds rendered output in its .plutostate.

const SITE = joinpath(@__DIR__, "_site", "generated_assets")
const EXPECT_PLOTS = ["01_quickstart", "02_model_anatomy", "03_calibration_and_data",
                      "04_shocks_and_cascades", "05_expectations_and_policy",
                      "06_forecasting", "07_extensions_canvas", "08_snpe_calibration"]

function main()
    isdir(SITE) || error("no generated_assets at $SITE — did the build run?")
    states = filter(f -> endswith(f, ".plutostate"), readdir(SITE))
    bad = String[]
    for nb in EXPECT_PLOTS
        match = filter(f -> startswith(f, nb), states)
        if isempty(match)
            push!(bad, "$nb: no .plutostate emitted")
            continue
        end
        blob = read(joinpath(SITE, first(match)))
        hasbytes(needle) = findfirst(Vector{UInt8}(needle), blob) !== nothing
        has_img = hasbytes("image/png") || hasbytes("image/svg+xml")
        has_err = hasbytes("not found in current path")
        has_err && push!(bad, "$nb: package environment not found — cell 1 failed")
        (!has_img && !has_err) && push!(bad, "$nb: no rendered image output")
    end
    if isempty(bad)
        println("check_build: all $(length(EXPECT_PLOTS)) notebooks rendered output ✓")
    else
        println("check_build FAILED:")
        foreach(b -> println("  ", b), bad)
        exit(1)
    end
end
main()
