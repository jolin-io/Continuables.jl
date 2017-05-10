# TODO

make this a valid julia package - see https://docs.julialang.org/en/stable/manual/packages/#creating-a-new-package

# Continuables.jl
Continuables are generator-like higher-order functions which take a continuation as an extra argument. It is best to think of the continuation function in the sense of ``produce`` from Julia's Tasks.

Continuables can be used instead of Tasks in many place with drastic performance-improvements. For the very trivial reimplementation of a range we get for instance the following benchmarks.

```julia
julia> import BenchmarkTools.@benchmark
julia> test_continuable(n) = cont -> begin
julia>   for i in 1:n
julia>     cont(i)
julia>   end
julia> end
julia> @benchmark ccollect(test_continuable(1000))
BenchmarkTools.Trial:
  memory estimate:  24.11 KiB
  allocs estimate:  500
  --------------
  minimum time:     12.247 μs (0.00% GC)
  median time:      14.222 μs (0.00% GC)
  mean time:        19.344 μs (9.32% GC)
  maximum time:     1.741 ms (97.55% GC)
  --------------
  samples:          10000
  evals/sample:     1
```

```julia
julia> function test_task(n)
julia>   for i in 1:n
julia>     produce(n)
julia>   end
julia> end
julia> @benchmark collect(@task test_task(1000))
BenchmarkTools.Trial:
  memory estimate:  50.56 KiB
  allocs estimate:  2014
  --------------
  minimum time:     774.716 μs (0.00% GC)
  median time:      923.654 μs (0.00% GC)
  mean time:        975.826 μs (0.29% GC)
  maximum time:     3.368 ms (46.71% GC)
  --------------
  samples:          5093
  evals/sample:     1
```

```julia
julia> @benchmark collect(1:10)
BenchmarkTools.Trial:
  memory estimate:  7.97 KiB
  allocs estimate:  2
  --------------
  minimum time:     586.606 ns (0.00% GC)
  median time:      2.426 μs (0.00% GC)
  mean time:        2.744 μs (23.52% GC)
  maximum time:     44.646 μs (96.10% GC)
  --------------
  samples:          10000
  evals/sample:     99
```

Mind that 1ms = 1000μs. So the continuable is a factor of $60$ faster than the Task alternative, and only a factor $5$ slower than the direct iterator. The memory usage is also improved and this despite one of the purposes of Task is memory efficiency.
