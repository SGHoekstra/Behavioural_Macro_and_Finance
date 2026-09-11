import BeforeIT as  BIT
using Statistics, StatsPlots, Distributions



using Distributions

function generate_varx_timeseries(N, p, alpha, gamma, beta, sigma, exog)
    # N: Number of time steps
    # p: Number of lags
    # alpha: Coefficient matrix for the VAR model (size: d x (d*p))
    # beta: Intercept vector (size: d)
    # sigma: Covariance matrix for the noise (size: d x d)
    # exog: Matrix of exogenous variables (size: N x k), where k is the number of exogenous variables

    d = size(alpha, 1)  # Number of variables in the VAR model
    dist = MvNormal(zeros(d), sigma)  # Multivariate normal distribution for noise

    # Initialize the time series with zeros
    timeseries = zeros(N + p, d)

    # Generate initial values (you can modify this to use actual initial values if available)
    for t in 1:p
        timeseries[t, :] = rand(dist)
    end

    # Generate the time series data
    for t in (p+1):(N + p)
        lagged_values = vec(timeseries[(t-1):-1:(t-p),:]')
        exog_values = exog[t-p, :]  # Exogenous variables at time t-p
        timeseries[t, :] = alpha * lagged_values .+ gamma * exog_values .+ beta .+ rand(dist)
    end

    # Return the generated time series, excluding the initial p values
    return timeseries[(p+1):end, :]
end
using Random

function generate_exogenous_timeseries(N, phi, sigma)
    d = length(phi)  # Number of dimensions (2 in this case)
    exog = zeros(N, d)  # Initialize the exogenous time series array

    # Set initial values for the time series
    for i in 1:d
        exog[1, i] = randn() * sigma[i]
    end

    # Generate the time series data using the AR(1) process
    for t in 2:N
        for i in 1:d
            exog[t, i] = phi[i] * exog[t-1, i] + randn() * sigma[i]
        end
    end

    return exog
end

# Example usage:
phi = [0.8, 0.7]  # AR(1) coefficients for each dimension
sigma = [0.1, 0.1]  # Standard deviation of the noise for each dimension

# Example usage:
N = 500  # Number of time steps
p = 2  # Number of lags
exog_timeseries = generate_exogenous_timeseries(N, phi, sigma)

alpha = [0.9 -0.2; 0.5 -0.1]  # Coefficient matrix (2 variables, 2 lags)
alpha = [0.9 -0.2 0.1 0.05; 
         0.5 -0.1 0.2 -0.3]
gamma = [0.9 -0.2; 0.5 -0.1]  # Coefficient vector for the exogenous variables
beta = [0.1, -0.2]  # Intercept vector
sigma = [0.1 0.05; 0.05 0.1]  # Covariance matrix for the noise

timeseries = generate_varx_timeseries(N, p, alpha, gamma, beta, sigma, exog_timeseries)
alpha_hat, beta_hat,gamma_hat, epsilon_hat = BIT.estimate_VARX(timeseries, exog_timeseries, intercept = true, lags = p)

# Run the forecast function
forecast = BIT.forecast_k_steps_VARX(timeseries, exog_timeseries, 10, intercept = true, lags = p)

forecasts = zeros(100,50,2)

for i in 1:100
    forecasts[i,:,:] = BIT.forecast_k_steps_VAR(timeseries, 50, intercept = true, lags = p)
end

repeat_series = permutedims(repeat(timeseries,1,1,100),(3,1,2))

errorline(hcat(repeat_series,forecasts)[:,:,1]')
errorline!(hcat(repeat_series,forecasts)[:,:,2]')