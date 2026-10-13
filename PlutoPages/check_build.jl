# Fail the build if any exported notebook rendered without output.
#
# generate.jl only inspects PlutoPages.jl's own cells, so a content notebook
# whose first cell throws still exits 0 and produces a site of empty shells.
# A notebook that really ran embeds rendered output in its .plutostate.

import Pluto

const SITE = joinpath(@__DIR__, "_site", "generated_assets")
const EXPECT_PLOTS = ["01_meet_the_model", "02_calibration_and_forecasting",
                      "03_shocks_expectations_policy", "04_extensions_canvas"]
const EXPECT_NOTEBOOKS = ["00_julia_pluto_primer"; EXPECT_PLOTS;
                          "05_likelihood_free_calibration"; "cheatsheet"]

function inspect_state(nb, state)
    bad = String[]
    results = state["cell_results"]
    isempty(results) && push!(bad, "$nb: no cell results")
    has_img = false
    for id in state["cell_order"]
        cell = results[id]
        output = cell["output"]
        body = get(output, "body", nothing)
        mime = get(output, "mime", "")
        has_img |= mime in ("image/png", "image/svg+xml")
        if cell["errored"]
            message = body isa AbstractDict ? get(body, "msg", repr(body)) : string(body)
            push!(bad, "$nb: cell $id errored — $(replace(message, '\n' => ' '))")
        end
        if get(cell, "running", false) || get(cell, "queued", false)
            push!(bad, "$nb: cell $id has not finished")
        end
        if body isa AbstractString && occursin("Activating", body)
            push!(bad, "$nb: Pkg activate banner leaked into cell $id")
        end
    end
    nb in EXPECT_PLOTS && !has_img && push!(bad, "$nb: no rendered image output")
    bad
end

function main()
    isdir(SITE) || error("no generated_assets at $SITE — did the build run?")
    states = filter(f -> endswith(f, ".plutostate"), readdir(SITE))
    bad = String[]
    for nb in EXPECT_NOTEBOOKS
        matching_states = filter(f -> startswith(f, nb), states)
        if isempty(matching_states)
            push!(bad, "$nb: no .plutostate emitted")
            continue
        end
        # Inspect cell flags, rather than matching error words in source or prose.
        # Report every failed cell in notebook order so the originating error is visible.
        state = Pluto.unpack(read(joinpath(SITE, first(matching_states))))
        append!(bad, inspect_state(nb, state))
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
        println("check_build: $(length(EXPECT_NOTEBOOKS)) notebooks completed, $(length(EXPECT_PLOTS)) rendered plots, both lecture PDFs present ✓")
    else
        println("check_build FAILED:")
        foreach(b -> println("  ", b), bad)
        exit(1)
    end
end
abspath(PROGRAM_FILE) == (@__FILE__) && main()
