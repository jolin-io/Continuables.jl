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
# This enables even more usecases of the beautiful do syntax.
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

| range                           | median   | factor y faster than trange |
|---------------------------------|----------|-----------------|
| 1:1000                          | 3.556ns  | 235193          |
| crange(1000) summed with Ref    | 15.408ns | 54280           |
| crange(1000) summed without Ref | 44642ns  | 19              |
| trange(1000)                    | 836346ns | 1               |

Similarly the memory usage improves drastically.

# Extra functionality

- **ascontinuable(iterable)** / **i2c(iterable)** / **@i2c iterable**

  use this to convert an arbitrary iterable to a continuable. The implementation is straightforward
  ```julia
  ascontinuable(iterable) = cont -> begin
    for i in iterable
      cont(i)
    end
  end
  ```

- **astask(continuable)** / **c2t(continuable)** / **@c2t continuable**

  use this to convert a continuable to a Task. The implementation is straightforward and very enlightening:
  ```julia
  astask(continuable) = @task continuable(produce)
  ```

- **collect(continuable)** / **c2a(continuable)** / **@c2a continuable**

  use this to convert a continuable to an Array

- **stoppable**

  wrap a continuable by stoppable macro to support `stop("return value")` to stop the continuation ahead of time
  ```julia
  ret = @stoppable crange(42) do x
    @show x
    if x == 4
      stop("foo")
    elseif x==8
      stop()
    end
  end
  ```
  ```
  x = 1
  x = 2
  x = 3
  x = 4
  "foo"
  ```
- **check_empty(continuable)**

  wrap a continuable by `check_empty` to let the return value show per false/true whether the continuable was empty

  ```julia
  was_empty = check_empty(crange(1,1)) do i
    @show i
  end
  was_empty = check_empty(crange(1,0)) do i
    @show i
  end
  ```
  ```
  i = 1
  false
  true
  ```

- **cenumerate(continuable)**

  adds index to continuable, like enumerate works for iterables.

  ```julia
  cenumerate(crange(5,7)) do t
    i, x = t
    @show i, x
  end
  ```
  ```
  (i,x) = (1,5)
  (i,x) = (2,6)
  (i,x) = (3,7)
  ```
- **cmap**, **cfilter**, **creduce**, **creduce!**

  the standard higher level functions are also supported

- **mzip**, **tzip**

  zip unfortunately does not work with pure continuables, so we have to either bring things to memory with ``mzip`` or transform things to task using ``tzip``. The result is in any case a continuable again, however implemented by the one or the other method.

# Iterators.jl like higher level functions - Product, GroupByReduce, Zip, ...

- **repeatedly**(f, [n])

    Call a function `n` times, or infinitely if `n` is omitted.

    Example:
    ```julia
    crepeatedly(time_ns, 3) do t
        @show t
    end
    ```

    ```
    t = 0x0000592ff83caf87
    t = 0x0000592ff83d8cf4
    t = 0x0000592ff83dd11e
    ```

- **cchain**(cs...)

    Iterate through any number of iterators in sequence.

    Because of ambiguity you cannot use do notation straightforwardly, but only with either wrapping the arguments into an array
    or tuple, or by calling the cchain result again like done below in the example

    Example:
    ```julia
    cchain(crange(3), i2c(['a', 'b', 'c']))() do i
      @show i
    end
    ```

    ```
    i = 1
    i = 2
    i = 3
    i = 'a'
    i = 'b'
    i = 'c'
    ```

    Combine any number of continuables into one large continuable.
    `chain(continuable)` will regard `continuable` as calling on sub-continuables and flattens the hierarchy respectively.


- **cproduct**(cs...)

    Goes over all combinations in the cartesian product of the inputs.

    Example:
    ```julia
    cproduct(crange(3), crange(2))() do p
        @show p
    end
    ```
    yields
    ```
    p = (1,1)
    p = (2,1)
    p = (3,1)
    p = (1,2)
    p = (2,2)
    p = (3,2)
    ```


- **cdistinct**(continuable)

    Iterate through values skipping over those already encountered.

    Example:
    ```julia
    cdistinct(@i2c [1,1,2,1,2,4,1,2,3,4]) do i
        @show i
    end
    ```

    ```
    i = 1
    i = 2
    i = 4
    i = 3
    ```
- **cnth**(continuable, n)

    Return the n'th element of `continuable`. Mostly useful for non indexable collections.

    Example:
    ```julia
    nth(crange(5,10), 3)
    ```

    ```
    7
    ```

- **cpartition**(xs, n, [step])

    Group values into `n`-tuples.

    Example:
    ```julia
    cpartition(1:9, 3) do i
        @show i
    end
    ```

    ```
    i = [1,2,3]
    i = [4,5,6]
    i = [7,8,9]
    ```

    If the `step` parameter is set, each tuple is separated by `step` values.

    Example:
    ```julia
    cpartition(1:9, 3, 2) do i
        @show i
    end
    ```

    ```
    i = [1,2,3]
    i = [3,4,5]
    i = [5,6,7]
    i = [7,8,9]
    ```

- **cgroupby**(f, continuable)

    Group consecutive values that share the same result of applying `f`.

    Example:
    ```julia
    cgroupby(x -> x[1], @i2c ["face", "foo", "bar", "book", "baz", "zzz"])
    ```

    ```
    DataStructures.OrderedDict{Any,Any} with 3 entries:
      'f' => String["face","foo"]
      'b' => String["bar","book","baz"]
      'z' => String["zzz"]
    ```
- **cgroupbyreduce**(f, continuable, op2, op1=identity)

    Combines consecutive values that share the same result of applying `f` into an OrderedDict.
    `op1` each first element to the accumulation type, and `op2(acc, x)` combines the newly found value
    into the respective accumulator.

    Example:
    ```julia
    cgroupbyreduce(x -> div(x, 3), crange(10), +)
    ```
    ```
    DataStructures.OrderedDict{Any,Any} with 4 entries:
      0 => 3
      1 => 12
      2 => 21
      3 => 19
    ```

- **cmap**(f, continuable)

    Go over values of a function applied to successive values from one or
    more iterators.

    Example:
    ```julia
    cmap(x -> x*x, crange(3)) do i
         @show i
    end
    ```

    ```
    i = 1
    i = 4
    i = 9
    ```

- **csubsets**(continuable)

    Go over every subset of `continuable`.

    Example:
    ```julia
    csubsets(crange(3)) do i
     @show i
    end
    ```

    ```
    i = ()
    i = (1,)
    i = (2,)
    i = (3,)
    i = (2,1)
    i = (3,1)
    i = (3,2)
    i = (3,2,1)
    ```

- **csubsets**(continuable, k)

    Go over every subset of size `k` from `continuable`.

    Example:
    ```julia
    csubsets(crange(3), 2) do i
     @show i
    end
    ```

    ```
    i = (2,1)
    i = (3,1)
    i = (3,2)
    ```

- **ccycle**(continuable, n)

    Cycles through an `continuable` `n` times

    Example:
    ```julia
    ccycle(crange(3), 2) do i
        @show i
    end
    ```

    ```
    i = 1
    i = 2
    i = 3
    i = 1
    i = 2
    i = 3
    ```

- **citerate**(f, x)

    Iterate over successive applications of `f`, as in `f(x), f(f(x)), f(f(f(x))), ...`.

    Example:
    ```julia
    ctake(citerate(x -> 2x, 1), 5) do i
        @show i
    end
    ```

    ```
    i = 1
    i = 2
    i = 4
    i = 8
    i = 16
    ```


# More Benchmarking

In `test/benchmark.jl` you find some other benchmark comparisons with ``Iterators.jl``.
Note that all continuable implementations don't allocate anything. They should lead to code with minimal amount of memory. Still the code is often orders of magnitude faster.

- **map**

  The continuable implementation of map, i.e. ``cmap``, is a factor `26200` faster than ``imap``. The improvement in memory consumption is even bigger, a factor of ``177292``.

- **product**

  The continuable implementation of product is a factor of `5` faster than the iterable implementation. In our example we use a factor of `3` less memory.

- **subsets**

  For subsets the iterable implementation is really really good. We have only a slight memory improvement (factor 1.5 in a simple test), while being factor of 3.7 slower in computation time.
