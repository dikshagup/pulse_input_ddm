using Test, pulse_input_DDM, LinearAlgebra, Flatten
using Parameters

n = 53

## Choice model
θ = θchoice(θz=θz(σ2_i = 0.5, B = 15., λ = -0.5, σ2_a = 50., σ2_s = 1.5,
    ϕ = 0.8, τ_ϕ = 0.05),
    bias=1., lapse=0.05)

θ, data = synthetic_data(;θ=θ, ntrials=10, rng=1)
model = choiceDDM(θ, data)

@test round(loglikelihood(model, n), digits=2) ≈ -3.76
@time loglikelihood(model, n)
@test round(θ(data), digits=2) ≈ -3.76
@test round(norm(gradient(model, n)), digits=2) ≈ 13.7

options = choiceoptions(fit = vcat(trues(9)),
    lb = vcat([0., 8., -5., 0., 0., 0.01, 0.005], [-30, 0.]),
    ub = vcat([2., 30., 5., 100., 2.5, 1.2, 1.], [30, 1.]),
    x0 = vcat([0.1, 15., -0.1, 20., 0.5, 0.8, 0.008], [0.,0.01]))

model, = optimize(data, options, n; iterations=5, outer_iterations=1);
@test round(norm(Flatten.flatten(model.θ)), digits=2) ≈ 25.05

## Neural model
f, ncells, ntrials = "Sigmoid", [2,3], [100,200]

θ = θneural(θz = θz(σ2_i = 0.5, B = 15., λ = -0.5, σ2_a = 10., σ2_s = 1.2,
    ϕ = 0.6, τ_ϕ =  0.02),
    θy=[[Sigmoid() for n in 1:N] for N in ncells], ncells=ncells,
    nparams=4, f=f)

data = synthetic_data(θ, ntrials)
model = neuralDDM(θ, data)

@test round(loglikelihood(model, n), digits=2) ≈ -21133.68

@test round(loglikelihood(model), digits=2) ≈ -21233.28

x = pulse_input_DDM.flatten(θ)
@unpack ncells, nparams, f = θ
@test round(loglikelihood(x, data, ncells, nparams, f), digits=2) ≈ -21233.28
@test round(loglikelihood(x, data, ncells, nparams, f, n), digits=2) ≈ -21133.68

θ2 = unflatten(x, ncells, nparams, f)
@test round(norm(gradient(model, n)), digits=2) ≈ 350.34
@test round(norm(gradient(model)), digits=2) ≈ 609.35

options = neuraloptions(ncells=ncells)

model, = optimize(data, options; iterations=5, outer_iterations=1)
@test round(norm(pulse_input_DDM.flatten(model.θ)), digits=2) ≈ 40.73

model, = optimize(data, options, n; iterations=5, outer_iterations=1)
@test round(norm(pulse_input_DDM.flatten(model.θ)), digits=2) ≈ 40.97
