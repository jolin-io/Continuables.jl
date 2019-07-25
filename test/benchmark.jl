# using Base.Iterators
using Continuables
import BenchmarkTools.@benchmark

## map -------------------------------------------------------------

@benchmark sum(cmap(x->x^2, crange(10000)))
#=
julia> @benchmark sum(cmap(x->x^2, crange(10000)))
BenchmarkTools.Trial:
  memory estimate:  48 bytes
  allocs estimate:  3
  --------------
  minimum time:     6.005 μs (0.00% GC)
  median time:      6.084 μs (0.00% GC)
  mean time:        6.192 μs (0.00% GC)
  maximum time:     56.810 μs (0.00% GC)
  --------------
  samples:          10000
  evals/sample:     5
=#

@benchmark sum(imap(x->x^2, 1:10000))
#=
julia> @benchmark sum(imap(x->x^2, 1:10000))
BenchmarkTools.Trial:
  memory estimate:  8.51 MiB
  allocs estimate:  257402
  --------------
  minimum time:     147.703 ms (0.00% GC)
  median time:      159.400 ms (0.00% GC)
  mean time:        163.545 ms (0.35% GC)
  maximum time:     220.241 ms (0.65% GC)
  --------------
  samples:          31
  evals/sample:     1
=#

## product -------------------------------------------------------------

@benchmark reduce(
  (acc, t) -> acc .+ t,
  (0,0,0),
  product(@i2c 1:100, @i2c 1:100, @i2c 1:100))
#=
julia> @benchmark reduce(
         (acc, t) -> broadcast(+, acc, t),  # tuple1 .+ tuple2 does not work in julia 5 unfortunately
         (0,0,0),
         cproduct(crange(100), crange(100), crange(100))
       )
BenchmarkTools.Trial:
  memory estimate:  183.39 MiB
  allocs estimate:  9008483
  --------------
  minimum time:     256.211 ms (4.59% GC)
  median time:      274.462 ms (4.34% GC)
  mean time:        284.734 ms (4.39% GC)
  maximum time:     360.535 ms (5.71% GC)
  --------------
  samples:          18
  evals/sample:     1
=#

@benchmark reduce(
  (acc, t) -> broadcast(+, acc, t),
  (0,0,0),
  product(1:100, 1:100, 1:100))
)
#=
julia> @benchmark reduce(
         (acc, t) -> broadcast(+, acc, t),
         (0,0,0),
         product(1:100, 1:100, 1:100))
BenchmarkTools.Trial:
  memory estimate:  534.03 MiB
  allocs estimate:  13998377
  --------------
  minimum time:     1.258 s (3.05% GC)
  median time:      1.328 s (2.98% GC)
  mean time:        1.319 s (3.03% GC)
  maximum time:     1.361 s (2.94% GC)
  --------------
  samples:          4
  evals/sample:     1
=#