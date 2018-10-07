using IterTools
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
  (acc, t) -> broadcast(+, acc, t),  # tuple1 .+ tuple2 does not work in julia 5 unfortunately
  (0,0,0),
  cproduct(crange(100), crange(100), crange(100))
)
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

## subsets -------------------------------------------------------------

@benchmark reduce(
  (acc, t) -> broadcast(+, acc, t),
  (0,0,0),
  csubsets(crange(1000), 3)
)
#=
julia> @benchmark reduce(
         (acc, t) -> broadcast(+, acc, t),
         (0,0,0),
         csubsets(crange(100), 3)
       )
BenchmarkTools.Trial:
  memory estimate:  30.31 MiB
  allocs estimate:  1480353
  --------------
  minimum time:     91.652 ms (1.60% GC)
  median time:      97.805 ms (1.83% GC)
  mean time:        106.574 ms (2.06% GC)
  maximum time:     157.497 ms (2.37% GC)
  --------------
  samples:          47
  evals/sample:     1
=#


@benchmark reduce(
  (acc, t) -> broadcast(+, acc, t),
  [0;0;0],
  subsets(1:1000, 3)
)
#=
julia> @benchmark reduce(
         (acc, t) -> broadcast(+, acc, t),
         [0;0;0],
         subsets(1:100, 3)
       )
BenchmarkTools.Trial:
  memory estimate:  46.88 MiB
  allocs estimate:  808506
  --------------
  minimum time:     21.589 ms (11.63% GC)
  median time:      26.535 ms (11.27% GC)
  mean time:        28.475 ms (11.36% GC)
  maximum time:     46.955 ms (9.24% GC)
  --------------
  samples:          176
  evals/sample:     1
=#


#=
julia> @benchmark reduce(
         (acc, t) -> broadcast(+, acc, t),
         (0,0,0),
         @pipe crange(100000) |> csubsets(_,3) |> ctake(_,1000)
       )
BenchmarkTools.Trial:
  memory estimate:  234.28 KiB
  allocs estimate:  10115
  --------------
  minimum time:     1.771 ms (0.00% GC)
  median time:      1.791 ms (0.00% GC)
  mean time:        1.994 ms (1.31% GC)
  maximum time:     7.165 ms (54.19% GC)
  --------------
  samples:          2495
  evals/sample:     1

julia> @benchmark reduce(
         (acc, t) -> broadcast(+, acc, t),
         [0;0;0],
         @pipe 1:100000 |> subsets(_, 3) |> take(_, 1000)
       )
BenchmarkTools.Trial:
  memory estimate:  1.08 MiB
  allocs estimate:  6009
  --------------
  minimum time:     167.506 μs (0.00% GC)
  median time:      208.593 μs (0.00% GC)
  mean time:        289.321 μs (18.91% GC)
  maximum time:     3.510 ms (90.11% GC)
  --------------
  samples:          10000
  evals/sample:     1
=#
