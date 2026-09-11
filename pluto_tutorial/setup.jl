"""
BeforeIT.jl Tutorial — one-time setup script.

Run this BEFORE opening any notebook:

    julia setup.jl

It installs Pluto into your default (global) Julia environment, and every
tutorial package into this folder's shared environment. The first run takes a
few minutes; subsequent runs are fast.
"""

using Pkg

# Pluto lives in the global environment, not the tutorial project: it is the
# program that *runs* the notebooks, not a dependency of them.
println("Installing Pluto into the global environment...")
Pkg.activate()
Pkg.add("Pluto")

println("Installing tutorial packages (this may take a few minutes the first time)...")
Pkg.activate(@__DIR__)
Pkg.instantiate()

println()
println("="^60)
println("  Setup complete!")
println("="^60)
println()
println("  Launch Pluto with:")
println()
println("    julia -t auto -e 'using Pluto; Pluto.run()'")
println()
println("  Then open any .jl notebook from the Pluto browser.")
println("  Suggested order: 00 → 01 → 02 → 03 → 04 → 05 → 06 → 07 → 08")
println("  (cheatsheet.jl is a reference, not part of the sequence.)")
println("="^60)
