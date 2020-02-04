# Continuables

TLDR: Python / C# ``yield`` with performance matching plain Julia iterators  (i.e. unbelievably fast)

Continuables are generator-like higher-order functions which take a continuation as an extra argument. The key macro provided by the package is `@cont` which will give access to the special function ``cont`` within its scope and wraps the computation in a special Type ``Continuables.Continuable``.
It is best to think of ``cont`` in the sense of ``yield`` from Python's Generators. It generates values and takes feedback from the outer process as return value.

If you come from Python, use Continuables wherever you would use generators. If you are Julia-native, Continuables can be used instead of Julia's Channels in many place with drastic performance-improvements (really drastic: in the little benchmark example below it is 20 million times faster!).

This package implements all standard functions like e.g. ``collect``, `reduce`, `any` and others. As well as functionalities known from `Base.Iterators` and [``IterTools.jl``](https://github.com/JuliaCollections/IterTools.jl) like `take`, `dropwhile`, `groupby`, `partition`, `nth` and others.


Outline
<!-- TOC START min:1 max:3 link:true asterisk:true update:true -->
* [Continuables](#continuables)
* [Example of a Continuable](#example-of-a-continuable)
* [The ``@Ref`` macro](#the-ref-macro)
* [Benchmark](#benchmark)
* [Related packages](#related-packages)
<!-- TOC END -->





# Example of a Continuable

Consider the following trivial wrappers around a range iterator 1:n.

```julia
using Continuables
# new Continuable ---------------------------------------------
corange(n::Integer) = @cont begin
  for i in 1:n
    cont(i)
  end
end
```

Many standard functions work seamlessly for Continuables.

```julia
using Continuables
collect(corange(10)) == collect(1:10)

co2 = map(corange(5)) do x
  2x
end
collect(co2) == [2,4,6,8,10]

foreach(println, corange(3))  # 1, 2, 3

foreach(chain(corange(2), corange(4))) do x
  print("$x, ")
end # 1, 2, 1, 2, 3, 4,  

reduce(*, corange(4)) == 24

all(x -> x < 5, corange(3))
any(x -> x == 2, corange(3))

map(corange(10)) do x
  corange(x)
end |> flatten |> co -> take(co, 5) |> collect == Any[1,1,2,1,2]

collect(product(corange(2), corange(3))) == Any[
  (1, 1),
  (1, 2),
  (1, 3),
  (2, 1),
  (2, 2),
  (2, 3),
]
collect(partition(corange(11), 4)) == [
  Any[1,2,3,4],
  Any[5,6,7,8],
  Any[9,10,11],
]
using OrderedCollections
groupbyreduce(isodd, corange(5), +) == OrderedDict{Any, Any}(
  true => 9,
  false => 6,
)

nth(3, ascontinuable(4:10)) == 6
nth(4, i2c(4:10)) == 7
nth(5, @i2c 4:10) == 8

# further defined are ``takewhile``, ``drop``, ``dropwhile``, ``repeated`` and ``iterate``, as well as `groupby`.
```

Note that Continuables do not support `iterate`, i.e. you cannot directly for-loop over a Continuable. There is just no direct way to implement `iterate` on top of Continuables. Give it a try. Instead, you have to convert it into an Array first using `collect`, or to a Channel using `aschannel`.

The same holds true for `zip`, however we provide a convenience implementation where you can choose which interpretation you want to have
```julia
# uses Channels and hence offers lazy execution, however might be slower
zip(i2c(1:4), i2c(3:6), lazy=true)  # Default

# uses Array, might be faster, but loads everything into memory  
zip(i2c(1:4), i2c(3:6), lazy=false)
```

Last but not least, you can call a Continuable directly. It is just a higher order function expecting a ``cont`` function to run its computation.

```julia
continuable = corange(3)
foreach(print, continuable)  # 123
# is the very same as
continuable(print)  # 123
```

# The ``@Ref`` macro

As you already saw, for continuables we cannot use for-loops. Instead we use higher-order functions like `map`, `foreach`, `reduce` or `groupbyreduce` to work with Continuables.  
Fortunately, julia supports beautiful ``do`` syntax for higher-order functions. In fact, ``do`` becomes the equivalent of ``for`` for continuables.

However, importantly, a ``do``-block constructs an anonymous function and consequently what happens within the do-block has its own variable namespace! This is essential if you want to define your own Continuables. You cannot easily change an outer variable from within a do-block like you may have done it within a for-loop. The solution is to simply use julia's ``Ref`` object to get mutations instead of simple variable assignments. For example instead of `var_changing_every_loop = 0`, and an update `var_changing_every_loop += 1` you use `var_changing_every_loop = Ref(yourvalue)` and `var_changing_every_loop.x += 1`.

(If you would use something mutable instead like an Vector instead of the non-mutable Int here, you of course can directly work in place. I.e. say ``a = []``, then ``push!(a, i)`` will do the right thing also in a do-block).

For convenience, Continuables comes with a second macro `@Ref` which checks your code for `variable = Ref(value)` parts and replaces all plain assignments `var = newvalue` with `var.x = newvalue`. This makes for beautiful code. Let's implement reduce with it:

```julia
using Continuables
@Ref function myreduce(continuable, merge, init)
  accumulator = Ref(init)
  continuable() do x
    accumulator = merge(accumulator, x)
  end
  accumulator
end
myreduce(i2c(0:5), +, 0) == 15
```

Let's check that `@Ref` indeed only replaced `accumulator` with `accumulator.x`. Run `@macroexpand` on the whole definition, i.e. `@macroexpand @Ref function myreduce(....`, which returns
```julia
:(function myreduce(continuable, merge, init)
      accumulator = Ref(init)
      continuable() do x
          accumulator.x = merge(accumulator.x, x)
      end
      accumulator.x
  end)
```
When combining `@cont` with `@Ref` do `@cont @Ref ...`, i.e. let `@cont` be the outer and `@Ref` be the inner macro.

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


# Related packages

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

I.e. you see it is an impressive factor of ``2.8e5`` slower on median compared to the plain range or the Continuables version. It is still a factor 100 faster than the current Channels version, but the Channel one is exceptionally slow (probably because of thread-safety). And in terms of memory allocation, ``@resumable`` is even the worst of all for this very simple computation.
