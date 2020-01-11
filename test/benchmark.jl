using Continuables
import BenchmarkTools.@benchmark

@cont function crange(n::Int)
  for i in 1:n
    cont(i)
  end
end

function trange(n::Int)
  c = Channel{Int}(1)
  task = @async for i ∈ 1:n
    put!(c, i)
  end
  bind(c, task)
end



@Ref function sum_continuable(continuable)
  a = Ref(0)
  continuable() do i
    a += i
  end
  a
end

function sum_continuable_withoutref(continuable)
  a = 0
  continuable() do i
    a += i
  end
  a
end

function sum_iterable(it)
  a = 0
  for i in it
    a += i
  end
  a
end

function collect_continuable(continuable)
  a = []
  continuable() do i
    push!(a, i)
  end
  a
end

function collect_iterable(it)
  a = []
  for i in it
    push!(a, i)
  end
  a
end

@benchmark sum_continuable(crange(1000))
#=
BenchmarkTools.Trial:
  memory estimate:  0 bytes
  allocs estimate:  0
  --------------
  minimum time:     1.185 ns (0.00% GC)
  median time:      1.580 ns (0.00% GC)
  mean time:        1.756 ns (0.00% GC)
  maximum time:     57.679 ns (0.00% GC)
  --------------
  samples:          10000
  evals/sample:     1000
=#

@benchmark sum_continuable(@i2c 1:1000)
#=
BenchmarkTools.Trial:
  memory estimate:  0 bytes
  allocs estimate:  0
  --------------
  minimum time:     1.185 ns (0.00% GC)
  median time:      1.580 ns (0.00% GC)
  mean time:        1.877 ns (0.00% GC)
  maximum time:     31.210 ns (0.00% GC)
  --------------
  samples:          10000
  evals/sample:     1000
=#

@benchmark sum_continuable_withoutref(crange(1000))
#=
BenchmarkTools.Trial:
  memory estimate:  22.81 KiB
  allocs estimate:  1460
  --------------
  minimum time:     26.074 μs (0.00% GC)
  median time:      27.654 μs (0.00% GC)
  mean time:        39.603 μs (15.68% GC)
  maximum time:     42.758 ms (99.85% GC)
  --------------
  samples:          10000
  evals/sample:     1
=#

@benchmark sum_continuable_withoutref(@i2c 1:1000)
#=
BenchmarkTools.Trial:
  memory estimate:  22.81 KiB
  allocs estimate:  1460
  --------------
  minimum time:     26.074 μs (0.00% GC)
  median time:      27.654 μs (0.00% GC)
  mean time:        39.910 μs (16.12% GC)
  maximum time:     46.847 ms (99.92% GC)
  --------------
  samples:          10000
  evals/sample:     1
=#

@benchmark sum_iterable(trange(1000))
#=
BenchmarkTools.Trial:
  memory estimate:  33.05 KiB
  allocs estimate:  2019
  --------------
  minimum time:     4.968 ms (0.00% GC)
  median time:      5.839 ms (0.00% GC)
  mean time:        6.089 ms (0.34% GC)
  maximum time:     23.466 ms (73.27% GC)
  --------------
  samples:          821
  evals/sample:     1
=#

@benchmark sum_iterable(1:1000)
#=
BenchmarkTools.Trial:
  memory estimate:  0 bytes
  allocs estimate:  0
  --------------
  minimum time:     1.185 ns (0.00% GC)
  median time:      1.580 ns (0.00% GC)
  mean time:        1.742 ns (0.00% GC)
  maximum time:     56.494 ns (0.00% GC)
  --------------
  samples:          10000
  evals/sample:     1000
=#

@benchmark collect_continuable(crange(1000))
#=
BenchmarkTools.Trial:
  memory estimate:  24.03 KiB
  allocs estimate:  499
  --------------
  minimum time:     11.456 μs (0.00% GC)
  median time:      12.247 μs (0.00% GC)
  mean time:        20.871 μs (30.69% GC)
  maximum time:     43.985 ms (99.97% GC)
  --------------
  samples:          10000
  evals/sample:     1
=#

@benchmark collect_continuable(@i2c 1:1000)
#=
BenchmarkTools.Trial:
  memory estimate:  24.03 KiB
  allocs estimate:  499
  --------------
  minimum time:     11.456 μs (0.00% GC)
  median time:      12.247 μs (0.00% GC)
  mean time:        25.120 μs (26.38% GC)
  maximum time:     44.245 ms (99.96% GC)
  --------------
  samples:          10000
  evals/sample:     1
=#

@benchmark collect_iterable(trange(1000))
#=
BenchmarkTools.Trial:
  memory estimate:  57.08 KiB
  allocs estimate:  2518
  --------------
  minimum time:     4.968 ms (0.00% GC)
  median time:      5.715 ms (0.00% GC)
  mean time:        6.082 ms (1.31% GC)
  maximum time:     57.567 ms (89.97% GC)
  --------------
  samples:          822
  evals/sample:     1
=#

@benchmark collect_iterable(1:1000)
#=
BenchmarkTools.Trial:
  memory estimate:  24.03 KiB
  allocs estimate:  499
  --------------
  minimum time:     11.456 μs (0.00% GC)
  median time:      12.642 μs (0.00% GC)
  mean time:        23.706 μs (27.20% GC)
  maximum time:     45.308 ms (99.97% GC)
  --------------
  samples:          10000
  evals/sample:     1
=#