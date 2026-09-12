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

    I = length(firms.G_i)
    gamma_d_i = zeros(I)
    pi_d_i    = zeros(I)

    for i in 1:I
        if firms.Q_s_i[i] <= firms.Q_d_i[i] && firms.P_i[i] >= P_bar_g[firms.G_i[i]]
            gamma_d_i[i] = firms.Q_d_i[i] / firms.Q_s_i[i] - 1   # expand production
        elseif firms.Q_s_i[i] <= firms.Q_d_i[i] && firms.P_i[i] < P_bar_g[firms.G_i[i]]
            pi_d_i[i]    = firms.Q_d_i[i] / firms.Q_s_i[i] - 1   # raise price
        elseif firms.Q_s_i[i] > firms.Q_d_i[i] && firms.P_i[i] >= P_bar_g[firms.G_i[i]]
            pi_d_i[i]    = firms.Q_d_i[i] / firms.Q_s_i[i] - 1   # cut price
        else
            gamma_d_i[i] = firms.Q_d_i[i] / firms.Q_s_i[i] - 1   # cut production
        end
    end

    Q_s_i  = firms.Q_s_i .* (1 .+ gamma_e) .* (1 .+ gamma_d_i)
    pi_c_i = Bit.cost_push_inflation(firms, model)

    new_P_i = firms.P_i .*
              (1 .+ ϕ.cp .* pi_c_i) .*
              (1 .+ ϕ.ae * pi_e)    .*
              (1 .+ ϕ.dp .* pi_d_i)

    I_d_i, DM_d_i, N_d_i = Bit.desired_capital_material_employment(firms, Q_s_i)
    Pi_e_i                = firms.Pi_i .* (1 + pi_e) * (1 + gamma_e)
    DD_e_i, K_e_i, L_e_i = Bit.expected_deposits_capital_loans(firms, model, Pi_e_i)
    DL_d_i                = max.(0, -DD_e_i .- firms.D_i)

    return Q_s_i, I_d_i, DM_d_i, N_d_i, Pi_e_i, DL_d_i, K_e_i, L_e_i, new_P_i
end

"""
    build_canvas_model(p, ic)

Build a `CANVASModel` from parameters and initial conditions.

`Q_s_i` is seeded from `Y_i` so the demand-pull ratio `Q_d_i / Q_s_i` is well
defined in the first quarter instead of dividing by zero.
"""
function build_canvas_model(p, ic)
    w_act, w_inact = Bit.Workers(p, ic)
    firms = Bit.Firms(p, ic);          bank = Bit.Bank(p, ic)
    cb    = Bit.CentralBank(p, ic);    gov  = Bit.Government(p, ic)
    rotw  = Bit.RestOfTheWorld(p, ic); agg  = Bit.Aggregates(p, ic)
    prop  = Bit.Properties(p, ic);     data = Bit.Data()
    m = CANVASModel(w_act, w_inact, firms, bank, cb, gov, rotw, agg, prop, data)
    m.firms.Q_s_i .= m.firms.Y_i
    return m
end
