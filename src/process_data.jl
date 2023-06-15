"""
    load(file)
Given a path to a .mat file containing data (properly formatted), loads data into
an acceptable format to use with pulse_input_DDM.
"""
function load(file::String; sim::Bool=false, centered::Bool=false, dt::Float64=1e-3)

    data = read(matopen(file), "rawdata")

    T = vec(data["T"])
    gamma = vec(data["gamma"])
    L = vec(map(x-> vec(collect(x)), data[collect(keys(data))[occursin.("left", collect(keys(data)))][1]]))
    R = vec(map(x-> vec(collect(x)), data[collect(keys(data))[occursin.("right", collect(keys(data)))][1]]))
    sess = vec(convert(BitArray, data["sessidx"]))
    sessbnd = Array{Int64}(undef, length(T))
    sessbnd[1] = 1
    for i=2:length(T)
        sess[i] ? sessbnd[i] = 1 :  sessbnd[i] = sessbnd[i-1] + 1
    end
    
    click_times = clicks.(L, R, T, gamma)
    binned_clicks = bin_clicks.(click_times, centered=centered, dt=dt)
    inputs = choiceinputs.(click_times, binned_clicks, dt, centered)

    if sim == false
        choices = vec(convert(BitArray, data["pokedR"]))
        data_pack = choicedata.(inputs, choices, sessbnd)
        return data_pack, make_data_dict(data_pack)
    else
        return inputs, make_data_dict(inputs, sessbnd, data["avgT"])
    end

end


"""
    make_data_dict(data::choicedata)
makes a convinient data dictionary for fitting initial points, non-decision time
conversion to lost posterior space etc
used during data fitting
"""
function make_data_dict(data)
    dt = data[1].click_data.dt
    correct = map(data->data.click_data.clicks.gamma>0, data)  # correct 1 right 0 left
    sessbnd = map(data->data.sessbnd,data)
    choice = map(data->data.choice,data)
    hits = correct .== choice

    nT = map(data->data.click_data.binned_clicks.nT, data)

    # lapse trials 
    frac = 1e-3
    lapse_dist = Exponential(mean(nT)*dt)
    lapse_lik = pdf.(lapse_dist,nT.*dt) .*dt

    # teps for converting into log space
    teps = evidence_no_noise(map(data->data.click_data.clicks.gamma, data), dteps = 1e-50)
        
    data_vec = Dict("hits"=> hits, "correct" => correct, 
                    "sessbnd"=> sessbnd, "frac" => frac, "teps" => teps, 
                    "choice"=> choice, "nT" => nT, "lapse_lik" => lapse_lik, 
                    "ntrials" => length(correct), "dt"=> dt)
end

"""
    make_data_dict(data::choiceinputs, sessbnd)
makes a convinient data dictionary for fitting initial points, non-decision time
conversion to lost posterior space etc
used during synthetic data generation
"""
function make_data_dict(inputs, sessbnd, avgT)
    dt = inputs[1].dt
    correct = map(data->data.clicks.gamma>0, inputs)  # correct 1 right 0 left
    nT = map(data->data.binned_clicks.nT, inputs)

    # teps for converting into log space
    teps = evidence_no_noise(map(data->data.clicks.gamma, inputs), dteps = 1e-50)
        
    data_vec = Dict("correct"=> correct, "sessbnd"=> sessbnd, 
                    "frac" => 1e-3, "mlapse" => avgT, 
                    "teps" => teps, "nT" => nT, 
                    "ntrials" => length(correct), "dt"=> dt)
end


"""
    bin_clicks(clicks::Vector{T})
Wrapper to broadcast bin_clicks across a vector of clicks.
"""
bin_clicks(clicks::Vector{T}; dt::Float64=1e-2, centered::Bool=false) where T <: Any =
    bin_clicks.(clicks; dt=dt, centered=centered)


"""
    bin_clicks(clicks)
Bins clicks, based on dt (defaults to 1e-2). 'centered' determines if the bin edges
occur at 0 and dt (and then ever dt after that), or at -dt/2 and dt/2 (and then
every dt after that). If the former, the bins align with the binning of spikes
in the neural model. For choice model, the latter is fine.
"""
function bin_clicks(clicks::clicks; dt::Float64=1e-2, centered::Bool=false)

    @unpack T,L,R = clicks
    nT = ceil(Int, round((T/dt), digits=10))

    if centered
        nL = searchsortedlast.(Ref((0. -dt/2):dt:(nT -dt/2)*dt), L)
        nR = searchsortedlast.(Ref((0. -dt/2):dt:(nT -dt/2)*dt), R)

    else
        nL = searchsortedlast.(Ref(0.:dt:nT*dt), L)
        nR = searchsortedlast.(Ref(0.:dt:nT*dt), R)

    end

    binned_clicks(nT, nL, nR)

end

"""
    reload(file)
    
Given a path and dictionaries, reload the results of a previous optimization saved as a .MAT file and
place them in the "state" key of the dictionaires that optimize_model() expects.
"""
function reload(file)

    read(matopen(file), "ML_params")

end


"""
    save(file, model, options; ll, CI)
Given a file, model produced by optimize and options, save the results of the optimization to a .MAT file
"""
function save(file, model, options, modeltype, ll; CI = 0)

    @unpack lb, ub, fit = options
    @unpack θ = model

    params = get_param_names(θ)

    dict = Dict("ML_params"=> collect(Flatten.flatten(θ)),
        "loglikelihood" => ll,
        "lb"=> lb, "ub"=> ub, "fit"=> fit, "modeltype"=> modeltype,
        "CI" => CI)

    matwrite(file, dict)

    #=
    if !isempty(H)
        #dict["H"] = H
        hfile = matopen(path*"hessian_"*file, "w")
        write(hfile, "H", H)
        close(hfile)
    end
    =#

end


"""
    save(file, model, options; ll, CI)
Given a file, model produced by optimize and options, save the results of the optimization to a .MAT file
"""
function save(file, model, options, modeltype, ll, outsample_logll, trial_ids; CI = 0)

    @unpack lb, ub, fit = options
    @unpack θ = model

    params = get_param_names(θ)

    dict = Dict("ML_params"=> collect(Flatten.flatten(θ)),
        "loglikelihood" => ll, "outsample_ll" => outsample_logll,
        "training_set" => trial_ids,
        "lb"=> lb, "ub"=> ub, "fit"=> fit, "modeltype"=> modeltype,
        "CI" => CI)

    matwrite(file, dict)

    #=
    if !isempty(H)
        #dict["H"] = H
        hfile = matopen(path*"hessian_"*file, "w")
        write(hfile, "H", H)
        close(hfile)
    end
    =#

end
