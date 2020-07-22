"""
    synthetic_data(; θ=θchoice(), ntrials=2000, rng=1)
Returns default parameters and ntrials of synthetic data (clicks and choices) organized into a choicedata type.
"""
function synthetic_data(θ::DDMθ, dt::Float64=5e-4, ntrials::Int=2000, rng::Int=1, centered::Bool=false)

    # generating clicks
    clicks = synthetic_clicks(ntrials, rng)
    binned_clicks = bin_clicks.(clicks,centered=centered,dt=dt)
    inputs = choiceinputs.(clicks, binned_clicks, dt, centered)

    # making data_dict
    sessbnd = [rand()<0.001 for i in 1:ntrials]
    data_dict = make_data_dict(inputs, sessbnd)

    # simulating choices and recomputing nTs based on RTs
    choices, RT = rand(θ, inputs, data_dict, rng=rng)
    map((clicks, RT) -> clicks.T = round(RT, digits =length(string(dt))-2), clicks, RT)
    binned_clicks = bin_clicks.(clicks, centered=centered, dt=dt)
    inputs = choiceinputs.(clicks, binned_clicks, dt, centered)

    return choicedata.(inputs, choices, sessbnd)

end


"""
    rand(θ, inputs, data_dict)
Produces synthetic clicks and choices for n trials using model parameters θ.
"""
function rand(θ::DDMθ, inputs, data_dict; rng::Int = 1, centered::Bool=false)

    dt = data_dict["dt"]
    ntrials = data_dict["ntrials"]

    σ2_s, C = transform_log_space(θ, data_dict["teps"])
    rng = sample(Random.seed!(rng), 1:ntrials, ntrials; replace=false)
    choices, RT = rand(inputs, data_dict, θ, θ.hist_θz, σ2_s, C, rng)   

    return choices, RT

end


"""
    rand(θ, inputs, rng)
Produces L/R choice for one trial, given model parameters and inputs.
# """
function rand(inputs, data_dict, θ::DDMθ, hist_θz, σ2_s, C, rng::Vector{Int}) 

    ntrials = data_dict["ntrials"]
    
    # adding non-decision time
    @unpack ndtimeL1, ndtimeL2 = θ.ndtime_θz
    @unpack ndtimeR1, ndtimeR2 = θ.ndtime_θz
    NDdistL = Gamma(ndtimeL1, ndtimeL2)
    NDdistR = Gamma(ndtimeR1, ndtimeR2)

    a_0 = compute_initial_pt(hist_θz, θ.base_θz.B0, data_dict)

    output = pmap((inputs, a_0, rng) -> rand(inputs, θ.base_θz, σ2_s, C, a_0, rng), inputs, a_0, rng)
    choices = map(output->output[1], output)
    RT = map(output->output[2], output)

    RT .= RT .+ ((1. .- choices).*vec(rand.(NDdistL,ntrials)) .+ choices.*vec(rand.(NDdistR,ntrials)))

    # adding lapse effects 
    @unpack lapse = θ.base_θz
    lapse_dist = Exponential(data_dict["mlapse"])
    lapse == 0 ? flipid = rand(ntrials).< data_dict["frac"] : flipid = rand(ntrials).< lapse
    choices[flipid] = rand(sum(flipid)).< 0.5
    RT[flipid] = rand(lapse_dist, sum(flipid))

    return choices, RT

end


"""
    rand(θ, inputs, rng)
Produces L/R choice for one trial, given model parameters and inputs.
# """
function rand(inputs, data_dict, θ::DDMθ, hist_θz::θz_expfilter_ce, σ2_s, C::String, rng::Vector{Int}) 

    # adding non-decision time
    @unpack ndtimeL1, ndtimeL2 = θ.ndtime_θz
    @unpack ndtimeR1, ndtimeR2 = θ.ndtime_θz
    NDdistL = Gamma(ndtimeL1, ndtimeL2)
    NDdistR = Gamma(ndtimeR1, ndtimeR2)

    # adding lapse effects 
    @unpack lapse = θ.base_θz
    lapse_dist = Exponential(data_dict["mlapse"])
    lapse == 0 ? lapse_frac = data_dict["frac"] : lapse_frac = lapse

    choices = Array{Bool}(undef, data_dict["ntrials"])
    RT      = Array{Float64}(undef, data_dict["ntrials"])

    for i = 1:data_dict["ntrials"]
        data_dict["choice"] = choices
        a_0 = compute_initial_pt(hist_θz, θ.base_θz.σ2_s, data_dict, i)
        choices[i], RT[i] = rand(inputs[i], θ.base_θz, σ2_s, C, a_0[i], rng[i])
        if rand() < lapse_frac
            choices[i] = rand() > 0.5
            RT[i] = rand(lapse_dist)
        end
    end

    RT .= RT .+ ((1. .- choices).*vec(rand.(NDdistL,data_dict["ntrials"])) .+ choices.*vec(rand.(NDdistR,data_dict["ntrials"])))

    return choices, RT

end



"""
    rand(θz, inputs)
Generate a sample latent trajecgtory,
given parameters of the latent model θz and clicks for one trial, contained
within inputs.
"""
function rand(inputs::choiceinputs, base_θz::θz_base, σ2_s::TT, C, a_0::TT, rng::Int) where TT <: Real

    Random.seed!(rng)    

    @unpack Bm, B0, Bλ, h_drift_scale = base_θz
    @unpack λ, σ2_i, σ2_a, ϕ, τ_ϕ, bias = base_θz
    @unpack clicks, binned_clicks, centered, dt = inputs
    @unpack nT, nL, nR = binned_clicks
    @unpack L, R = clicks

    La, Ra = adapt_clicks(ϕ, τ_ϕ, L, R, C)
    if (Bλ == 0) & (Bm == 0)
        B = map(x->B0 + Bλ*sqrt(x), dt .* collect(1:nT))
    else
        B = map(x->B0/(1. + exp(Bλ*(x-Bm))), dt .* collect(1:nT))
    end

    RT = 0.

    if σ2_i > 0.
        a = sqrt(σ2_i)*randn() + a_0 + bias
    else
        a = zero(typeof(σ2_i)) + a_0 + bias
    end

    for t = 1:nT

        if centered && t == 1
            a = sample_one_step!(a, t, σ2_a, σ2_s, λ, nL, nR, La, Ra, a_0*h_drift_scale, dt/2)
        else
            a = sample_one_step!(a, t, σ2_a, σ2_s, λ, nL, nR, La, Ra, a_0*h_drift_scale, dt)
        end

        if abs(a) >= B[t]
            a, RT = B[t] * sign(a), t
            break
        end 

        if t == nT
           RT = t
        end 
    end

    return a>0., RT*dt

end


"""
"""
function sample_one_step!(a::TT, t::Int, σ2_a::TT, σ2_s::TT, λ::TT, 
        nL::Vector{Int}, nR::Vector{Int}, 
        La, Ra, h_drift::TT, dt::Float64=5e-4) where {TT <: Any}
    
    any(t .== nL) ? sL = sum(La[t .== nL]) : sL = zero(TT)
    any(t .== nR) ? sR = sum(Ra[t .== nR]) : sR = zero(TT)
    σ2, μ = σ2_s * (sL + sR), -sL + sR + h_drift
    
    # scaling variance
    ξ = sqrt(σ2_a * dt + σ2) * randn()
    
    if abs(λ) < 1e-150 
        a += μ + (ξ)  #
    else
        h = μ/(dt*λ)   
        a = exp(λ*dt)*(a + h) - h + ξ
    end
    
    return a

end



"""
    synthetic_clicks(ntrials, rng)
Computes randomly timed left and right clicks for ntrials.
rng sets the random seed so that clicks can be consistently produced.
Output is bundled into an array of 'click' types.
"""
function synthetic_clicks(ntrials::Int, rng::Int;
    tmin::Float64=5.0, tmax::Float64=5.0, clickrate::Int=40)

    Random.seed!(rng)

    T = tmin .+ (tmax-tmin).*rand(ntrials)
    T = ceil.(T, digits=2)
    clicktot = clickrate.*Int.(T)

    rate_vals = [15.10, 24.89, 7.29, 32.7, 3.03, 36.96, 1.17, 38.82]
    Rbar = rand(rate_vals, ntrials)
    Lbar = clickrate .- Rbar

    R = cumsum.(rand.(Exponential.(1 ./Rbar), clicktot))
    L = cumsum.(rand.(Exponential.(1 ./Lbar), clicktot))
    R = map((T,R)-> vcat(0,R[R .<= T]), T,R)
    L = map((T,L)-> vcat(0,L[L .<= T]), T,L)

    gamma = round.(log.(Rbar./Lbar), digits =1)

    clicks.(L, R, T, gamma)

end

