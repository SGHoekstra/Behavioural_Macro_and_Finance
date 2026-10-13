# Model-level regression checks for admissible zero-sales/supply states.
# Run: julia --project=pluto_tutorial PlutoPages/tools/check_canvas_boundaries.jl
import BeforeIT as Bit
using Dates, Random, Test
include(joinpath(@__DIR__, "..", "..", "pluto_tutorial", "canvas_model.jl"))
p, ic = Bit.get_params_and_initial_conditions(
    Bit.ITALY_CALIBRATION, DateTime(2010, 3, 31); scale=0.0001)
Random.seed!(42)
m = build_canvas_model(p, ic)
m.agg.gamma_e = 0
m.agg.pi_e = 0
i = 1
g = m.firms.G_i[i]
CANVAS_PHI[] = (dp=1.0, cp=0.0, ae=0.0)

function decision(supply, demand, sector_price)
    m.firms.Q_s_i[i] = supply
    m.firms.Q_d_i[i] = demand
    m.firms.P_i[i] = 1
    m.agg.P_bar_g[g] = sector_price
    result = Bit.firms_expectations_and_decisions(m)
    @test all(isfinite, result[1])
    @test all(q -> q >= 0, result[1])
    @test all(p -> isfinite(p) && p > 0, result[end])
    return result[1][i], result[end][i]
end

@testset "CANVAS zero-state decisions" begin
    for sector_price in (0.5, 2.0), (supply, demand) in ((0.0, 0.0), (0.0, 2.0), (1.0, 0.0))
        quantity, price = decision(supply, demand, sector_price)
        @test quantity == demand
        @test price == 1
    end
    # A firm with no previous supply can resume when orders return.
    @test decision(0.0, 2.0, 2.0) == (2.0, 1.0)
    @test decision(2.0, 0.0, 2.0) == (0.0, 1.0)
    @test decision(0.0, 0.0, 2.0) == (0.0, 1.0)
end

@testset "Positive-state quadrants retain their economics" begin
    @test decision(1.0, 2.0, 0.5) == (2.0, 1.0) # output expansion
    @test decision(1.0, 2.0, 2.0) == (1.0, 2.0) # price increase
    @test decision(2.0, 1.0, 0.5) == (2.0, 0.5) # price reduction
    @test decision(2.0, 1.0, 2.0) == (1.0, 1.0) # output reduction
    @test decision(2.0, 2.0, 2.0) == (2.0, 1.0)
    quantity, price = decision(1.0, 1e-20, 0.5)
    @test quantity == 1
    @test price ≈ 1e-20
end

@testset "Malformed states stop before invalid quotes propagate" begin
    @test_throws DomainError decision(-1.0, 1.0, 1.0)
    @test_throws DomainError decision(1.0, NaN, 1.0)
    decision(1.0, 1.0, 1.0)
    m.firms.P_i[i] = 0
    @test_throws DomainError Bit.firms_expectations_and_decisions(m)
end

# A short actual trajectory also exercises the inherited decisions and markets.
Random.seed!(42)
CANVAS_PHI[] = (dp=1.0, cp=1.0, ae=1.0)
trajectory = build_canvas_model(p, ic)
Bit.run!(trajectory, 4)
@test all(isfinite, trajectory.data.real_gdp)
@test all(p -> isfinite(p) && p > 0, trajectory.firms.P_i)
println("PASS: zero states, restart, all four ordinary quadrants, tiny positive demand, malformed inputs and a four-quarter trajectory.")
