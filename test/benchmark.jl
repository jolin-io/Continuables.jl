using Iterators
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

@benchmark sum(cmap(sum, cproduct(crange(100), crange(100), crange(100))))
#=
julia> @benchmark sum(cmap(sum, cproduct(crange(100), crange(100), crange(100))))
BenchmarkTools.Trial:
  memory estimate:  316.09 KiB
  allocs estimate:  10112
  --------------
  minimum time:     1.976 ms (0.00% GC)
  median time:      1.985 ms (0.00% GC)
  mean time:        2.139 ms (0.58% GC)
  maximum time:     7.797 ms (0.00% GC)
  --------------
  samples:          2333
  evals/sample:     1
=#

@benchmark sum(imap(sum, product(1:100, 1:100, 1:100)))
#=
julia> @benchmark sum(imap(sum, product(1:100, 1:100, 1:100)))
BenchmarkTools.Trial:
  memory estimate:  1.18 GiB
  allocs estimate:  23999984
  --------------
  minimum time:     16.443 s (0.56% GC)
  median time:      16.443 s (0.56% GC)
  mean time:        16.443 s (0.56% GC)
  maximum time:     16.443 s (0.56% GC)
  --------------
  samples:          1
  evals/sample:     1
=#

## subsets -------------------------------------------------------------

@benchmark reduce(
  (acc, t) -> broadcast(+, acc, t),
  [0;0;0],
  csubsets(crange(100), 3)
)

@benchmark reduce(
  (acc, t) -> broadcast(+, acc, t),
  [0;0;0],
  subsets(1:100, 3)
)

@benchmark sum(cmap(sum, csubsets(crange(100), 3)))
#=
julia> @benchmark sum(cmap(sum, csubsets(crange(100), 3)))
BenchmarkTools.Trial:
  memory estimate:  1.09 MiB
  allocs estimate:  40242
  --------------
  minimum time:     84.082 ms (0.00% GC)
  median time:      84.996 ms (0.00% GC)
  mean time:        85.335 ms (0.05% GC)
  maximum time:     88.609 ms (0.00% GC)
  --------------
  samples:          59
  evals/sample:     1
=#

@benchmark sum(imap(sum, subsets(1:100, 3)))
#=
julia> @benchmark sum(imap(sum, subsets(1:100, 3)))
BenchmarkTools.Trial:
  memory estimate:  130.77 MiB
  allocs estimate:  3072287
  --------------
  minimum time:     2.544 s (0.42% GC)
  median time:      2.546 s (0.39% GC)
  mean time:        2.546 s (0.39% GC)
  maximum time:     2.549 s (0.36% GC)
  --------------
  samples:          2
  evals/sample:     1
=#
