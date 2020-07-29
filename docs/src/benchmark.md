# Benchmark

We compare Continuables with standard Julia Channel and iterators for performance an a simple implementation of `sum`.

The equivalent Channel function to the above `corange` function is:
```julia
# standard Channel -----------------------------------------------------
function chrange(r)
  Channel{Int}(1) do ch
    for i ∈ 1:r
      put!(ch, i)
    end
  end
end
```

The sum benchmark functions are defined as follows
```julia
using Continuables

# Summing continuable --------------------------------------

# we use a convenient macro which replaces all uses of r where r was defined as r = Ref(value) with r.x, i.e. the pointer to its referenced value.
# The effect is that the variable assignment becomes a mutation of the Reference's field.
# This macro leads to very clean code while being intuitively transparent.
@Ref function sum_continuable(continuable)
  a = Ref(0)
  continuable() do i
    a += i
  end
  a
end

function sum_continuable_withoutref(continuable)
  # interestingly, this works too, however with a lot of magic happening in the background
  # which is also decreasing performance
  a = 0
  continuable() do i
    a += i
  end
  a
end

# Summing Task ----------------------------------------------
function sum_iterable(it)
  a = 0
  for i in it
    a += i
  end
  a
end
```

You may need to add BenchmarkTools to your julia project by running `] add BenchmarkTools`. All below are tested on the same machine, results may vary for your architecture.

We start with the base-line, i.e. summing up the pure range iterator:
```julia
julia> import BenchmarkTools.@benchmark
julia> @benchmark sum_iterable(1:1000)
BenchmarkTools.Trial:
  memory estimate:  0 bytes
  allocs estimate:  0
  --------------
  minimum time:     1.420 ns (0.00% GC)
  median time:      1.706 ns (0.00% GC)
  mean time:        1.663 ns (0.00% GC)
  maximum time:     16.456 ns (0.00% GC)
  --------------
  samples:          10000
  evals/sample:     1000
```
We reach the same performance with our self-written continuable version of range. However, as you can see below, if you do not use References everywhere (like Ref or arrays or dictionaries) then performance decreases.
```julia
julia> @benchmark sum_continuable(corange(1000))
BenchmarkTools.Trial:
  memory estimate:  0 bytes
  allocs estimate:  0
  --------------
  minimum time:     1.420 ns (0.00% GC)
  median time:      1.708 ns (0.00% GC)
  mean time:        1.671 ns (0.00% GC)
  maximum time:     16.778 ns (0.00% GC)
  --------------
  samples:          10000
  evals/sample:     1000

julia> @benchmark sum_continuable_withoutref(corange(1000))
BenchmarkTools.Trial:
  memory estimate:  22.81 KiB
  allocs estimate:  1460
  --------------
  minimum time:     22.658 μs (0.00% GC)
  median time:      24.315 μs (0.00% GC)
  mean time:        28.105 μs (2.64% GC)
  maximum time:     1.925 ms (97.74% GC)
  --------------
  samples:          10000
  evals/sample:     1
```

Last but not least the Channel version of range.
```julia
julia> @benchmark sum_iterable(chrange(1000))
BenchmarkTools.Trial:
  memory estimate:  32.95 KiB
  allocs estimate:  2026
  --------------
  minimum time:     28.208 ms (0.00% GC)
  median time:      34.169 ms (0.00% GC)
  mean time:        33.836 ms (0.00% GC)
  maximum time:     38.737 ms (0.00% GC)
  --------------
  samples:          148
  evals/sample:     1
```

Mind that 1μs = 1000ns and 1ms = 1000μs. So on median we have

| range                            | median     | x-times of range |
|----------------------------------|------------|------------------|
| 1:1000                           | 1.706ns    | 1                |
| corange(1000) summed with Ref    | 1.708ns    | 1                |
| corange(1000) summed without Ref | 24315ns    | 1.4e4            |
| chrange(1000)                    | 34169000ns | 2e7              |

Also note that the continuable version with Ref has 0 bytes memory footprint!


## Related packages

There is a package called [ResumableFunctions.jl](https://github.com/BenLauwens/ResumableFunctions.jl) with the same motivation but completely different implementation.

```julia
using ResumableFunctions

@resumable function rfrange(n::Int)
  for i in 1:n
    @yield i
  end
end

# apparently the @resumable macro relies of having Base.iterate directly available on the namespace, but Continuables also exports one, so that we have to explicitly declare which we want to use to repair this little @resumable bug
const iterate = Base.iterate
@benchmark sum_iterable(rfrange(1000))
```

The resulting time are as follows on my machine:
```julia
BenchmarkTools.Trial:
  memory estimate:  93.84 KiB
  allocs estimate:  3001
  --------------
  minimum time:     453.640 μs (0.00% GC)
  median time:      475.210 μs (0.00% GC)
  mean time:        505.774 μs (1.18% GC)
  maximum time:     4.360 ms (85.91% GC)
  --------------
  samples:          9869
  evals/sample:     1
```

I.e. you see it is an impressive factor of `2.8e5` slower on median compared to the plain range or the Continuables version. It is still a factor 100 faster than the current Channels version, but the Channel one is exceptionally slow (probably because of thread-safety). And in terms of memory allocation, `@resumable` is even the worst of all for this very simple computation.
