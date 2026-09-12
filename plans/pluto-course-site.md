# PlutoPages course site

## Context

Lectures and notebooks are only reachable as raw files on GitHub. Build a static course
site that renders the nine tutorial notebooks with outputs baked in, next to the two
lecture PDFs, so students can read everything in a browser and run locally if they want.

`archive-2024` already carries a working PlutoPages setup (generator, layout, UvA and
Tinbergen assets, deploy workflow). Port and modernise it rather than start over.

## Decisions

- **Deploy to a new `gh-pages` branch.** `output` holds the Fall23 site and stays untouched.
- **Execute all nine notebooks in CI.** `_cache` keyed on the Manifest makes this a
  one-time ~30 min cost, not per-push. Notebook 08 additionally pulls the conda `sbi` env.
- **Modernise the workflow.** `archive-2024` pins `checkout@v2`, `cache@v2`,
  `upload-artifact@v2`; artifact v3-and-below were switched off in Jan 2025, so that
  workflow cannot run today. Move to v4 and Julia 1.12 to match `pluto_tutorial/Manifest.toml`.
- **Lectures are linked PDFs, not rendered.** They are LaTeX beamer, not notebooks.

## Steps

1. **Port the generator.** Copy `PlutoPages/` from `archive-2024` to `main` unchanged.
   Copy `content/_includes/` and `content/assets/`. Drop `content/week0/` and
   `content/Introduction_to_agent_based_modelling/` - those are 2024 material.

2. **Point content at the tutorial.** PlutoPages renders notebooks it finds under
   `content/`. Add a build step that copies `pluto_tutorial/*.jl` into
   `content/notebooks/` before generation, so `pluto_tutorial/` stays the single source
   of truth - its paths are linked from the public site and must not move.

3. **Add frontmatter to each notebook.** PlutoPages reads `title`, `order`, `tags`,
   `layout` from Pluto frontmatter. Nine notebooks plus the cheatsheet. Verify each
   still loads with `Pluto.load_notebook_nobackup` after editing.

4. **Write the site pages.** `content/index.jlmd` (course overview, links to both
   lecture PDFs), `content/installation.md` (the README setup section),
   `content/sidebar data.jl` with a Lectures and a Tutorial collection. Update the
   `:about` block - `archive-2024` still says "Spring 2023" with placeholder author URLs.

5. **Copy the lecture PDFs into the build.** Add `lecture_1_intro_abm/main.pdf` and
   `lecture_2_sfc_abm/lecture.pdf` to `content/assets/lectures/` as a build step, so the
   site is self-contained and links do not depend on GitHub blob URLs.

6. **Workflow.** `.github/workflows/BuildSite.yml`: trigger on push to `main` and
   `workflow_dispatch`; actions at v4; Julia 1.12; cache `_cache` and `~/.julia`;
   deploy `PlutoPages/_site` to `gh-pages` with `github-pages-deploy-action@v4`.
   Set `timeout-minutes: 90` - the cold build runs every notebook.

7. **Enable Pages.** Repository settings must point GitHub Pages at `gh-pages`. Manual
   step in the web UI; flag it rather than attempt it.

## Verification

- `julia --project=PlutoPages/pluto-deployment-environment -e 'include("PlutoPages/generate.jl")'`
  builds locally with zero errored cells. Check `generation_report.html`.
- Every notebook still loads in Pluto after the frontmatter edits (reuse the
  `pluto_load.jl` check written this session).
- `git ls-tree origin/output` byte-identical before and after - the archive is untouched.
- Both lecture PDFs resolve from the built site, and `pluto_tutorial/*.jl` paths on
  `main` are unchanged, so existing links keep working.

## Risks

- Cold CI build is ~30 min and notebook 08 needs a conda env; if it exceeds the runner
  limit, drop 08 from the executed set and link it as a download instead.
- PlutoPages on `archive-2024` is an old vendored copy; if it will not instantiate on
  Julia 1.12, pin the deployment environment to 1.10 rather than chase an upgrade.
