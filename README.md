# Continuables

Continuables are generator-like higher-order functions which take a continuation as an extra argument. It is best to think of the continuation function in the sense of ``produce`` from Julia's Tasks. Continuables can be used instead of Tasks in many place with drastic performance-improvements.

This package implements all standard helpers like ``Iterators.jl`` implemented them for iterators. See further below for examples how these helpers work in the context of continuables. You can also look at the description of [Iterators.jl](https://github.com/JuliaCollections/Iterators.jl).

# Example of a Continuable

Consider the following to trivial wrappers around a range iterator 1:n.
The first one is the continuable version, the second the Task version.

```julia
# Continuable ---------------------------------------------
crange(n::Integer) = cont -> begin
  for i in 1:n
    cont(i)
  end
end
# We define an extra version with cont as the first argument.
# This enables even more usecases of the handy do syntax.
crange(cont, n::Integer) = crange(n)(cont)

# Task -----------------------------------------------------
function trange(n::Integer)
  for i in 1:n
    produce(i)
  end
end
```

How can we work with those? While the task works like a normal iterator and hence can be used in a standard ``for``-loop, continuables are higher-order functions. Fortunately, julia supports beautiful ``do`` syntax for higher-order functions. In fact, ``do`` becomes the equivalent of ``for`` for continuables.
Furthermore note that a ``do``-block constructs an anonymous function and consequently what happens within the do-block has its own variable namespace. This is why we use julia's ``Ref`` object to get mutations instead of simple variable assignments. See the function ``sum_continuable_withoutref`` for a version without ``Ref``.
(If you would use something mutatible instead like an Vector instead of the non-mutatible Int here, you of course can directly work in place. I.e. say ``a = []``, then ``push!(a, i)`` will do the right thing also in a do-block).
```julia
# Summing continuable --------------------------------------
import Continuables.@Ref
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

# Convenience Syntax

A convenience macro `@cont` was added, which automatically adds the second method definition. With this we could have defined `crange` as
```julia
@cont function crange2(cont, n::Integer)
  for i in 1:n
    cont(i)
  end
end
# or equally as
@cont crange3(n::Integer) = cont -> begin
  for i in 1:n
    cont(i)
  end
end
```
As within a continuation you might want to use Refs, this macro automatically includes the `@Ref` macro.


# Benchmark

This now benchmarks as follows (from fastest=pureIterator to slowest=Task). We start with the base-line, i.e. summing up the pure range iterator:
```julia
julia> import BenchmarkTools.@benchmark
julia> @benchmark sum_iterable(1:1000)
BenchmarkTools.Trial:
  memory estimate:  0 bytes
  allocs estimate:  0
  --------------
  minimum time:     3.160 ns (0.00% GC)
  median time:      3.556 ns (0.00% GC)
  mean time:        3.938 ns (0.00% GC)
  maximum time:     30.025 ns (0.00% GC)
  --------------
  samples:          10000
  evals/sample:     1000
```
We can do almost as good with the continuable version of range. However, as you can see below, if you do not use References everywhere (like Ref or arrays or dictionaries) then performance decreases.
```julia
julia> @benchmark sum_continuable(crange(1000))
BenchmarkTools.Trial:
  memory estimate:  32 bytes
  allocs estimate:  2
  --------------
  minimum time:     14.222 ns (0.00% GC)
  median time:      15.408 ns (0.00% GC)
  mean time:        20.364 ns (5.53% GC)
  maximum time:     1.274 μs (94.58% GC)
  --------------
  samples:          10000
  evals/sample:     1000

julia> @benchmark sum_continuable_withoutref(crange(1000))
BenchmarkTools.Trial:
  memory estimate:  22.81 KiB
  allocs estimate:  1460
  --------------
  minimum time:     41.876 μs (0.00% GC)
  median time:      44.642 μs (0.00% GC)
  mean time:        49.485 μs (1.27% GC)
  maximum time:     969.878 μs (94.50% GC)
  --------------
  samples:          10000
  evals/sample:     1
```
Last but not least the task version of range.
```julia
julia> @benchmark sum_iterable(@task trange(1000))
BenchmarkTools.Trial:
  memory estimate:  33.13 KiB
  allocs estimate:  1949
  --------------
  minimum time:     757.333 μs (0.00% GC)
  median time:      836.346 μs (0.00% GC)
  mean time:        849.117 μs (0.11% GC)
  maximum time:     1.636 ms (48.24% GC)
  --------------
  samples:          5860
  evals/sample:     1
```

Mind that 1μs = 1000ns. So on median we have

| range                           | median   | % of trange |
|---------------------------------|----------|-------------|
| 1:1000                          | 3.556ns  | 0.0004%     |
| crange(1000) summed with Ref    | 15.408ns | 0.0018%     |
| crange(1000) summed without Ref | 44642ns  | 5.3%        |
| trange(1000)                    | 836346ns | 100%        |

Similarly the memory usage improves drastically.


# Product, GroupByReduce, Zip, ...

TODO mimic https://github.com/JuliaCollections/Iterators.jl
