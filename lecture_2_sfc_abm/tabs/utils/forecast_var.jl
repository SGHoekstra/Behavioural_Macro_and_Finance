import BeforeIT as  BIT
using Statistics, StatsPlots, Distributions



function generate_var_timeseries(N, p, alpha, beta, sigma)
    # N: Number of time steps
    # p: Number of lags
    # alpha: Coefficient matrix for the VAR model (size: d x (d*p))
    # beta: Intercept vector (size: d)
    # sigma: Covariance matrix for the noise (size: d x d)

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
        timeseries[t, :] = alpha * lagged_values .+ beta .+ rand(dist)
    end

    # Return the generated time series, excluding the initial p values
    return timeseries[(p+1):end, :]
end

# Example usage:
N = 500  # Number of time steps
p = 2  # Number of lags
alpha = [0.9 -0.2; 0.5 -0.1]  # Coefficient matrix (2 variables, 2 lags)
alpha = [0.9 -0.2 0.1 0.05; 
         0.5 -0.1 0.2 -0.3]
beta = [0.1, -0.2]  # Intercept vector
sigma = [0.1 0.05; 0.05 0.1]  # Covariance matrix for the noise

timeseries = generate_var_timeseries(N, p, alpha, beta, sigma)
alpha_hat, beta_hat, epsilon_hat = BIT.estimate_VAR(timeseries, intercept = false, lags = p)

# Run the forecast function
forecast = BIT.forecast_k_steps_VAR(timeseries, 10, intercept = true, lags = p)

forecasts = zeros(100,50,2)

for i in 1:100
    forecasts[i,:,:] = BIT.forecast_k_steps_VAR(timeseries, 50, intercept = true, lags = p)
end

repeat_series = permutedims(repeat(timeseries,1,1,100),(3,1,2))

errorline(hcat(repeat_series,forecasts)[:,:,1]')
errorline!(hcat(repeat_series,forecasts)[:,:,2]')