# Fail the build if any exported notebook rendered without output.
#
# generate.jl only inspects PlutoPages.jl's own cells, so a content notebook
# whose first cell throws still exits 0 and produces a site of empty shells.
# A notebook that really ran embeds rendered output in its .plutostate.

const SITE = joinpath(@__DIR__, "_site", "generated_assets")
const EXPECT_PLOTS = ["01_meet_the_model", "02_calibration_and_forecasting",
                      "03_shocks_expectations_policy", "04_extensions_canvas",
                      "05_likelihood_free_calibration"]

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
        if !has_img && !has_err
            # Surface whatever the notebook actually said, so a CI failure is
            # self-explaining instead of just "no images".
            txt = String(copy(blob))
            m = match(r"(?:ArgumentError|UndefVarError|LoadError|Failed to precompile)[^\"]{0,140}", txt)
            hint = m === nothing ? "no error text found either" : String(m.match)
            push!(bad, "$nb: no rendered image output — $hint")
        end
        # A build path in the output means Pkg's activate banner leaked into
        # the published page.
        hasbytes("Activating") && push!(bad, "$nb: Pkg activate banner leaked into the page")
    end
    # The lecture PDFs are the other half of the course. PlutoPages drops any
    # extension missing from its passthrough list without warning, so assert.
    site = joinpath(@__DIR__, "_site")
    for pdf in ("assets/lectures/lecture_1_intro_abm.pdf",
                "assets/lectures/lecture_2_sfc_abm.pdf")
        f = joinpath(site, pdf)
        if !isfile(f)
            push!(bad, "$pdf: missing from the built site")
        elseif filesize(f) < 100_000
            push!(bad, "$pdf: only $(filesize(f)) bytes — not a real PDF")
        end
    end

    # PlutoPages rewrites its root_url placeholder to a RELATIVE path at write
    # time, so every generated link comes out as "./assets/..." or ".". A
    # root-relative "/lectures/" is therefore always hand-written and always
    # wrong: the site is served from /Behavioural_Macro_and_Finance/, so it
    # 404s in production while resolving fine against _site locally.
    for (root, _, files) in walkdir(site), f in files
        endswith(f, ".html") || continue
        for m in eachmatch(r"(?:href|src)=\"(/[^\"]*)\"", read(joinpath(root, f), String))
            t = m.captures[1]
            startswith(t, "//") && continue   # protocol-relative, fine
            push!(bad, "$(relpath(joinpath(root, f), site)): root-relative link \"$t\" 404s in production")
        end
    end
    unique!(bad)

    if isempty(bad)
        println("check_build: $(length(EXPECT_PLOTS)) notebooks rendered output, both lecture PDFs present ✓")
    else
        println("check_build FAILED:")
        foreach(b -> println("  ", b), bad)
        exit(1)
    end
end
main()
