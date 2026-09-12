# Copy course material into content/ before the site build.
#
# pluto_tutorial/ is the single source of truth: the public site links those
# paths directly, so nothing there may move or be rewritten. PlutoPages runs
# the notebooks it is given and writes back to them, so we build from copies.
# content/notebooks/ and content/assets/lectures/ are generated, not tracked.

const ROOT = normpath(joinpath(@__DIR__, ".."))

const NOTEBOOKS = [
    ("00_julia_pluto_primer.jl",    "Julia + Pluto primer",                        1),
    ("01_quickstart.jl",            "Hello, BeforeIT",                             2),
    ("02_model_anatomy.jl",         "Anatomy of the model",                        3),
    ("03_calibration_and_data.jl",  "Calibration and data",                        4),
    ("04_shocks_and_cascades.jl",   "Shocks and bankruptcy cascades",              5),
    ("05_expectations_and_policy.jl","Expectations, policy and fiscal closure",    6),
    ("06_forecasting.jl",           "Forecasting and validation",                  7),
    ("07_extensions_canvas.jl",     "Extending the model: CANVAS",                 8),
    ("08_snpe_calibration.jl",      "Likelihood-free calibration: ABC, NPE, SNRE", 9),
    ("cheatsheet.jl",               "BeforeIT cheatsheet",                        10),
]

const LECTURES = [
    ("lecture_1_intro_abm/main.pdf",   "lecture_1_intro_abm.pdf"),
    ("lecture_2_sfc_abm/lecture.pdf",  "lecture_2_sfc_abm.pdf"),
]

# Each notebook activates its own directory. Under content/notebooks/ that would
# be an empty project, so repoint it at the real tutorial environment. Copying
# the environment files here instead would make CondaPkg build the whole Python
# environment inside content/, which PlutoPages then tries to render as site
# pages — numpy's LICENSE.md files and all.
const ACTIVATE_FROM = "Pkg.activate(dirname(@__FILE__))"
const ACTIVATE_TO   = "Pkg.activate(joinpath(@__DIR__, \"..\", \"..\", \"pluto_tutorial\"))"

"Insert PlutoPages frontmatter after the `# v0.20.x` header line, idempotently."
function with_frontmatter(src::String, title::String, order::Int)
    occursin("#> [frontmatter]", src) && return src
    lines = split(src, '\n')
    # line 1 is "### A Pluto.jl notebook ###", line 2 is the version
    fm = ["", "#> [frontmatter]", "#> title = \"$title\"", "#> order = $order",
          "#> layout = \"layout.jlhtml\"", "#> tags = [\"tutorial\"]"]
    return join(vcat(lines[1:2], fm, lines[3:end]), '\n')
end

function main()
    nbdir = mkpath(joinpath(ROOT, "content", "notebooks"))

    for (file, title, order) in NOTEBOOKS
        src = joinpath(ROOT, "pluto_tutorial", file)
        isfile(src) || error("missing notebook: $src")
        body = replace(read(src, String), ACTIVATE_FROM => ACTIVATE_TO)
        @assert occursin("pluto_tutorial", body) "activate rewrite failed for $file"
        write(joinpath(nbdir, file), with_frontmatter(body, title, order))
    end
    println("synced $(length(NOTEBOOKS)) notebooks -> content/notebooks/")

    pdfdir = mkpath(joinpath(ROOT, "content", "assets", "lectures"))
    for (src, dest) in LECTURES
        from = joinpath(ROOT, src)
        isfile(from) || error("missing lecture pdf: $from")
        cp(from, joinpath(pdfdir, dest); force = true)
    end
    println("synced $(length(LECTURES)) lecture PDFs -> content/assets/lectures/")
end

main()
