# Shared CANVAS model extension.
#
# Notebooks 04 (the extension itself) and 05 (calibrating it) both need this
# model. It used to be written out in full in both, and the two copies had
# drifted into different shapes for identical logic, so editing one silently
# diverged from the other. Defined once here and `include`d by both.
#
# Set the pass-through coefficients before running:
#     CANVAS_PHI[] = (dp = 1.0, cp = 1.0, ae = 1.0)

Bit.@object mutable struct CANVASModel(Bit.Model) <: Bit.AbstractModel end

# Pass-through coefficients — updated by the sliders below before each run
const CANVAS_PHI = Ref((dp=1.0, cp=1.0, ae=1.0))

function Bit.firms_expectations_and_decisions(model::CANVASModel)
    firms   = model.firms
    P_bar_g = model.agg.P_bar_g
    gamma_e = model.agg.gamma_e
    pi_e    = model.agg.pi_e
    ϕ       = CANVAS_PHI[]

    all(v -> isfinite(v) && 0 <= v <= 1, values(ϕ)) ||
        throw(DomainError(ϕ, "CANVAS pass-through coefficients must lie in [0,1]."))
    isfinite(gamma_e) && gamma_e > -1 ||
        throw(DomainError(gamma_e, "Expected gross output growth must be positive."))
    isfinite(pi_e) && pi_e > -1 ||
        throw(DomainError(pi_e, "Expected gross inflation must be positive."))
    all(q -> isfinite(q) && q >= 0, firms.Q_s_i) &&
        all(q -> isfinite(q) && q >= 0, firms.Q_d_i) ||
        throw(DomainError((firms.Q_s_i, firms.Q_d_i), "Supply and demand must be finite and nonnegative."))
    all(p -> isfinite(p) && p > 0, firms.P_i) &&
        all(p -> isfinite(p) && p > 0, P_bar_g) ||
        throw(DomainError(firms.P_i, "Firm and sector prices must be finite and strictly positive."))

    I = length(firms.G_i)
    Q_s_i     = similar(firms.Q_s_i)
    demand_multiplier = ones(I)

    for i in 1:I
        supply, demand = firms.Q_s_i[i], firms.Q_d_i[i]
        expensive = firms.P_i[i] >= P_bar_g[firms.G_i[i]]
        if supply == 0 || demand == 0
            # Explicit boundary rule: use observed demand as the quantity target.
            # No sales / no supply provide no usable relative-demand price signal.
            # Cost and aggregate-expectation pricing channels still apply below.
            Q_s_i[i] = demand * (1 + gamma_e)
        elseif (supply <= demand && expensive) || (supply > demand && !expensive)
            # Algebraically equivalent to supply * (demand / supply), without
            # a division or the indeterminate product 0 * Inf.
            Q_s_i[i] = demand * (1 + gamma_e)
        else
            Q_s_i[i] = supply * (1 + gamma_e)
            # Equivalent to 1 + dp * (demand / supply - 1), but avoids
            # cancellation to zero for small positive demand and dp == 1.
            demand_multiplier[i] = (1 - ϕ.dp) + ϕ.dp * (demand / supply)
        end
    end

    pi_c_i = Bit.cost_push_inflation(firms, model)

    new_P_i = firms.P_i .*
              (1 .+ ϕ.cp .* pi_c_i) .*
              (1 .+ ϕ.ae * pi_e)    .*
              demand_multiplier

    all(q -> isfinite(q) && q >= 0, Q_s_i) ||
        throw(DomainError(Q_s_i, "CANVAS produced an invalid quantity target."))
    all(p -> isfinite(p) && p > 0, new_P_i) ||
        throw(DomainError(new_P_i, "CANVAS pricing requires finite, strictly positive quotes; inspect the channel signals."))

    I_d_i, DM_d_i, N_d_i = Bit.desired_capital_material_employment(firms, Q_s_i)
    Pi_e_i                = firms.Pi_i .* (1 + pi_e) * (1 + gamma_e)
    DD_e_i, K_e_i, L_e_i = Bit.expected_deposits_capital_loans(firms, model, Pi_e_i)
    DL_d_i                = max.(0, -DD_e_i .- firms.D_i)

    return Q_s_i, I_d_i, DM_d_i, N_d_i, Pi_e_i, DL_d_i, K_e_i, L_e_i, new_P_i
end

"""
    build_canvas_model(p, ic)

Build a `CANVASModel` from parameters and initial conditions.

Use BeforeIT's tuple constructor to assign workers to firms, initialise
household incomes and balance sheets, and collect the initial observation.

`Q_s_i` is seeded from `Y_i`. At zero supply or demand, the decision rule
targets observed demand and omits the demand-price adjustment. It therefore
supports inactive firms and restart decisions without dividing by zero.
"""
function build_canvas_model(p, ic)
    w_act, w_inact = Bit.Workers(p, ic)
    firms = Bit.Firms(p, ic);          bank = Bit.Bank(p, ic)
    cb    = Bit.CentralBank(p, ic);    gov  = Bit.Government(p, ic)
    rotw  = Bit.RestOfTheWorld(p, ic); agg  = Bit.Aggregates(p, ic)
    prop  = Bit.Properties(p, ic);     data = Bit.Data()
    m = CANVASModel((w_act, w_inact, firms, bank, cb, gov, rotw, agg, prop, data))
    m.firms.Q_s_i .= m.firms.Y_i
    return m
end
