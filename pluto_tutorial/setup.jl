"""
BeforeIT.jl Tutorial — one-time setup script.

Run this BEFORE opening any notebook:

    julia setup.jl

This installs all required packages into the tutorial's shared environment.
It takes a few minutes on first run; subsequent runs are fast.
"""

using Pkg

println("Activating tutorial environment...")
Pkg.activate(@__DIR__)

println("Installing packages (this may take a few minutes the first time)...")
Pkg.instantiate()

println()
println("="^60)
println("  Setup complete!")
println("="^60)
println()
println("  Launch Pluto with:")
println()
println("    julia --project=@. -t auto -e 'using Pluto; Pluto.run()'")
println()
println("  Then open any .jl notebook from the Pluto browser.")
println("  Suggested order: 00 → 01 → 02 → 03 → 04 → 05 → 06")
println("="^60)
