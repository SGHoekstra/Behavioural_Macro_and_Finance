# Copy course material into content/ before the site build.
#
# pluto_tutorial/ is the single source of truth: the public site links those
# paths directly, so nothing there may move or be rewritten. PlutoPages runs
# the notebooks it is given and writes back to them, so we build from copies.
# content/notebooks/ and content/assets/lectures/ are generated, not tracked.

const ROOT = normpath(joinpath(@__DIR__, ".."))

const NOTEBOOKS = [
    ("00_julia_pluto_primer.jl",           "Julia + Pluto primer",                        1),
    ("01_meet_the_model.jl",               "Meet the model",                              2),
    ("02_calibration_and_forecasting.jl",  "Calibration, no-burn-in and forecasting",     3),
    ("03_shocks_expectations_policy.jl",   "Shocks, expectations and policy",             4),
    ("04_extensions_canvas.jl",            "Extending the model: CANVAS",                 5),
    ("05_likelihood_free_calibration.jl",  "Likelihood-free calibration: ABC, NPE, SNRE", 6),
    ("cheatsheet.jl",                      "BeforeIT cheatsheet",                         7),
]

# Plain .jl files the notebooks `include` — copied verbatim, no frontmatter, and
# never rendered as pages (PlutoPages only renders files it can parse as
# notebooks, and this is not one).
const SUPPORT_FILES = ["canvas_model.jl"]

# The site serves the HANDOUT builds, not the presentation PDFs. Beamer emits
# one page per overlay step, so lecture 1's 27 frames become 91 pages of
# incremental reveals — unreadable as a document. Rebuilt with the class option
# `handout`, it is 28. Lecture 2 has no overlays and is unchanged at 61, but it
# uses the handout too so there is one rule rather than a special case.
#
# Regenerate after editing a deck (there is no LaTeX in CI, so these are
# committed):
#   cd lecture_1_intro_abm && pdflatex --shell-escape -jobname=main-handout \
#     "\PassOptionsToClass{handout}{beamer}\input{main.tex}"
const LECTURES = [
    ("lecture_1_intro_abm/main-handout.pdf",  "lecture_1_intro_abm.pdf"),
    ("lecture_2_sfc_abm/lecture-handout.pdf", "lecture_2_sfc_abm.pdf"),
]

# Each notebook activates its own directory. Under content/notebooks/ that would
# be an empty project, so repoint it at the real tutorial environment. Copying
# the environment files here instead would make CondaPkg build the whole Python
# environment inside content/, which PlutoPages then tries to render as site
# pages — numpy's LICENSE.md files and all.
const ACTIVATE_FROM = "Pkg.activate(dirname(@__FILE__))"
# io=devnull keeps Pkg's "Activating project at /abs/path" banner out of the
# published page. On a runner that path is /home/runner/work/..., which is
# noise at best and confusing to a student at worst.
const ACTIVATE_TO   = "Pkg.activate(joinpath(@__DIR__, \"..\", \"..\", \"pluto_tutorial\"); io=devnull)"

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
    # Wipe and recreate: this directory is generated. Without the wipe, a
    # notebook removed from NOTEBOOKS lingers here from an earlier sync and
    # still gets rendered into the site.
    nbdir = joinpath(ROOT, "content", "notebooks")
    isdir(nbdir) && rm(nbdir; recursive = true)
    mkpath(nbdir)

    for (file, title, order) in NOTEBOOKS
        src = joinpath(ROOT, "pluto_tutorial", file)
        isfile(src) || error("missing notebook: $src")
        body = replace(read(src, String), ACTIVATE_FROM => ACTIVATE_TO)
        @assert occursin("pluto_tutorial", body) "activate rewrite failed for $file"
        write(joinpath(nbdir, file), with_frontmatter(body, title, order))
    end
    for file in SUPPORT_FILES
        cp(joinpath(ROOT, "pluto_tutorial", file), joinpath(nbdir, file); force = true)
    end
    println("synced $(length(NOTEBOOKS)) notebooks and $(length(SUPPORT_FILES)) support files -> content/notebooks/")

    pdfdir = mkpath(joinpath(ROOT, "content", "assets", "lectures"))
    for (src, dest) in LECTURES
        from = joinpath(ROOT, src)
        isfile(from) || error("missing lecture pdf: $from")
        cp(from, joinpath(pdfdir, dest); force = true)
    end
    println("synced $(length(LECTURES)) lecture PDFs -> content/assets/lectures/")
end

main()
