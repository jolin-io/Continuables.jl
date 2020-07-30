"""
A Continuable is a function which takes a single argument function a -> b

We could have made most of the core functionality work for general functions a... -> b
however the semantics become too complicated very soon.

For instance for product. How should the product look like? say we have two continuables and
name the continuation's arguments a... and  b... respectively.
How to call the follow up continuation then?
cont(a..., b...) or cont(a, b)?
Probably something like if isa(a and b, SingletonTuple) then cont(a...,b...)
else cont(a,b). However this seems to complicate things unnecessarily complex.

Another point is for example the interaction with iterables which always deliver tuples.

See also this github issue https://github.com/JuliaLang/julia/issues/6614 for tuple deconstructing which
would give a similar familarity.


Many documentation strings are taken and adapted from
https://github.com/JuliaCollections/Iterators.jl/blob/master/src/Iterators.jl.
"""
# TODO copy documentation strings
module Continuables
export
  cont, @cont, AbstractContinuable, Continuable, innerfunctype,
  @Ref, stoppable, stop,
  emptycontinuable, singleton, repeated, iterated,
  aschannel, ascontinuable, i2c, @i2c,
  reduce, reduce!, zip, product, chain, flatten, cycle, foreach, map, all, any, sum, prod,
  take, takewhile, drop, dropwhile, partition, groupbyreduce, groupby,
  nth

using Compat
using ExprParsers
using DataTypesBasic
using OrderedCollections
import Base.Iterators: cycle, flatten, take, drop, partition, product

include("utils.jl")
include("itertools.jl")

## Continuable Core -------------------------------------------------------------------------

"""
`cont` is reserved function parameter name
"""
cont(args...; kwargs...) = error("`cont` is reserved to be used within `Continuables.@cont`")

"""
    AbstractContinuable

Abstract type which all continuable helper functions use for dispatch.

The interface for a continuable just consists of
```
Base.foreach(cont, continuable::YourContinuable)
```

For julia 1.0 you further need to provide
```
(continuable::YourContinuable)(cont) = foreach(cont, continuable)
```
which is provided automatically for more recent julia versions.
"""
abstract type AbstractContinuable end

"""
    foreach(func, continuable)

Runs the continuable with `func` as the continuation. This is the core interface of a continuable.

It is especially handy when using `do` syntax.
"""
function Base.foreach(cont, ::AbstractContinuable)
  error("You need to specialize `Base.foreach` for your custom Continuable type.")
end


"""
  Continuable(func)

Assumes func to have a single argument, the continuation function (usually named `cont`).

Example
-------

```
Continuable(function (cont)
  for i in 1:10
    cont(i)
  end
end)
```
"""
struct Continuable{Func} <: AbstractContinuable
  f::Func
  # making sure typevar `Func` has always the correct meaning so that we can dispatch on it
  # otherwise one could construct `Continuable{Any}(func)` which would break dispatching on the typevariable.
  Continuable(f) = new{typeof(f)}(f)
end
Base.foreach(cont, c::Continuable) = c.f(cont)
(c::Continuable)(cont) = foreach(cont, c)

"""
    innerfunctype(continuable)

Returns the generic type of `continuable.f`.
This can be used to specialize functions on specific Continuables, like `Base.IteratorSize` and else.

# Examples

```julia
mycont(x) = @cont cont(x)
Base.length(::Continuable{<:innerfunctype(mycont(:examplesignature))}) = :justatest
length(mycont(1)) == :justatest
length(mycont("a")) == :justatest
# other continuables are not affected
anothercont(x) = @cont cont(x)
length(anothercont(42)) == 1
```
"""
function innerfunctype(continuable::Continuable)
  typeof(continuable.f).name.wrapper
end



include("./syntax.jl")  # parts of syntax.jl require the Continuable definition, hence here



## conversions ----------------------------------------------

"""
    aschannel(continuable) -> Channel

Convert the continuable into a channel. Performance is identical compared to when you would have build a Channel
directly.
"""
function aschannel(continuable::AbstractContinuable, size=0; elemtype=Any, taskref=nothing, spawn=false)
  Channel{elemtype}(size, taskref=taskref, spawn=spawn) do channel
    continuable() do x
      put!(channel, x)
    end
  end
end

"""
    ascontinuable(iterable)

Converts an iterable to a Continuable. There should not be any performance loss.
"""
ascontinuable(iterable) = @cont foreach(cont, iterable)
"""
    i2c(iterable)

Alias for [ascontinuable](@ref). "i2c" is meant as abbreviation for "iterable to continuable".
Also comes in macro form as [`@i2c`](@ref).
"""
const i2c = ascontinuable
"""
    @i2c iterable

Alias for [ascontinuable](@ref). "i2c" is meant as abbreviation for "iterable to continuable".
Also comes in function form as [`i2c`](@ref).
"""
macro i2c(expr)
  esc(:(ascontinuable($expr)))
end


## factories -----------------------------------------------

"""
    emptycontinuable

The continuable with no elements.
"""
const emptycontinuable = @cont ()  # mind the space!!

"""
    singleton(value)

Construct a Continuable containing only the one given value.
"""
singleton(value) = @cont cont(value)

"""
    repeated(() -> 2[, n])
    repeated([n]) do
      # ...
      "returnvalue"
    end

Constructs a Continuable which repeatedly yields the returnvalue from calling the given function again and again.
Until infinity or if `n` is given, exactly `n` times.
"""
@cont function repeated(f)
  while true
    cont(f())
  end
end

@cont function repeated(f, n::Integer)
  for _ in 1:n
    cont(f())
  end
end

"""
    iterated((x) -> x*x, startvalue)
    iterated(startvalue) do x
      # ...
      x*x
    end

Constructs an infinite Continuable which
"""
@cont @Ref function iterated(f, x)
  a = Ref(x)
  cont(a)
  while true
    a = f(a)
    cont(a)
  end
end


## core helpers ----------------------------------------------------------

# Continuable cannot implement Base.iterate efficiently

try
  # only in more recent julia, we can specialize call syntax for AbstractTypes
  (c::AbstractContinuable)(cont) = foreach(cont, c)
catch
end

Base.IteratorSize(::AbstractContinuable) = Base.SizeUnknown()
@Ref function Base.length(continuable::AbstractContinuable)
  i = Ref(0)
  continuable() do _
    i += 1
  end
  i
end

Base.IteratorEltype(::AbstractContinuable) = Base.EltypeUnknown()
Base.eltype(::AbstractContinuable) = Any


"""
    collect(continuable[, n]) -> Vector

Constructs Vector out of the given Continuable. If also given the length `n` explicitly,
a Vector of respective is preallocated. IMPORTANTLY `n` needs to be the true length of the continuable.
Smaller `n` will result in error.
"""
function Base.collect(c::AbstractContinuable)
  everything = Vector(undef, 0)
  reduce!(push!, c, init = everything)
end

@Ref function Base.collect(c::AbstractContinuable, n)
  a = Vector(undef, n)
  # unfortunately the nested call of enumerate results in slower code, hence we have a manual index here
  # this is so drastically that for small `n` a preallocate version with enumerate would be slower than the non-preallocate version
  i = Ref(1)
  c() do x
    a[i] = x
    i += 1
  end
  a
end

"""
    enumerate(continuable)

Constructs new Continuable with elements `(i, x)` for each `x` in the continuable, where `i` starts at `1` and
increments by `1` for each element.
"""
@cont @Ref function Base.enumerate(continuable::AbstractContinuable)
  i = Ref(1)
  continuable() do x
    cont((i, x))
    i += 1
  end
end

"""
    map(func, continuable)

Constructs new Continuable where the given `func` was applied to each element.
"""
Base.map(func, continuable::AbstractContinuable) = @cont continuable(x -> cont(func(x)))

"""
    filter(predicate, continuable)

Constructs new Continuable where only elements `x` with `predicate(x) == true` are kept.
"""
@cont function Base.filter(bool, continuable::AbstractContinuable)
  continuable() do x
    if bool(x)
      cont(x)
    end
  end
end

"""
    reduce(operator, continuable; [init])

Like Base.reduce this will apply `operator` iteratively to combine all elements into one accumulated result.
"""
Base.reduce(op, continuable::AbstractContinuable; init = nothing) = foldl_continuable(op, continuable, init)

"""
    reduce(operator, continuable; [init])

Like Base.foldl this will apply `operator` iteratively to combine all elements into one accumulated result.
The order is guaranteed to be left to right.
"""
Base.foldl(op, continuable::AbstractContinuable; init = nothing) = foldl_continuable(op, continuable, init)

struct EmptyStart end
@Ref function foldl_continuable(op, continuable, init::Nothing)
  acc = Ref{Any}(EmptyStart())
  lifted_op(acc::EmptyStart, x) = x
  lifted_op(acc, x) = op(acc, x)
  continuable() do x
    acc = lifted_op(acc, x)
  end
  acc
end
@Ref function foldl_continuable(op, continuable, init)
  acc = Ref(init)
  continuable() do x
    acc = op(acc, x)
  end
  acc
end


"""
    reduce!(op!, continuable; [init])

Mutating version of Base.reduce

If no `init` is given
    `op!` is assumed to mutate a hidden state (equivalent to mere continuation)
else
    `init` is the explicit state and will be passed to `op!` as first argument (the accumulator)
"""
function reduce!(op!, continuable::AbstractContinuable; init = nothing)
  if isnothing(init)
    continuable(op!)
  else
    reduce!(op!, continuable, init)
  end
end
function reduce!(op!, continuable::AbstractContinuable, acc)
  continuable() do x
    op!(acc, x)
  end
  acc
end

"""
    sum(continuable)

sums up all elements
"""
Base.sum(c::AbstractContinuable) = reduce(+, c)

"""
    sum(continuable)

multiplies up all elements
"""
Base.prod(c::AbstractContinuable) = reduce(*, c)

"""
    all([func, ]continuable; [lazy])

Checks whether all elements in the continuable are true.
If a function `func` is given, it is first applied to the elements before comparing for truth.

If `lazy=true` (default) the Continuable will only be evaluated until the first `false` value.
Elseif `lazy=false` all elements of the Continuable will be combined.
"""
@Ref function Base.all(continuable::AbstractContinuable; lazy=true)
  if lazy
    stoppable(continuable, true) do b
      if !b
        stop(false)
      end
    end
  else # non-lazy
    b = Ref(true)
    continuable() do x
      b &= x
    end
    b
  end
end
Base.all(f, continuable::AbstractContinuable; kwargs...) = all(map(f, continuable); kwargs...)


"""
    any([func, ]continuable; [lazy])

Checks whether at least one element in the continuable is true.
If a function `func` is given, it is first applied to the elements before comparing for truth.

If `lazy=true` (default) the Continuable will only be evaluated until the first `true` value.
Elseif `lazy=false` all elements of the Continuable will be combined.
"""
@Ref function Base.any(continuable::AbstractContinuable; lazy=true)
  if lazy
    stoppable(continuable, false) do b
      if b
        stop(true)
      end
    end

  else # non-lazy
    b = Ref(false)
    continuable() do x
      b |= x
    end
    b
  end
end
Base.any(f, continuable::AbstractContinuable; kwargs...) = any(map(f, continuable); kwargs...)

## zip ----------------------------
# zip is the only method which seems to be unimplementable with continuations
# hence we have to go to tasks or arrays

"""
    azip(continuables...)

Zipping continuables via intermediate array representation

CAUTION: loads everything into memory
"""
azip(cs::AbstractContinuable...) = @cont begin
  # not possible with continuations... bring it to memory and apply normal zip
  array_cs = collect.(cs)
  for t in zip(array_cs...)
    cont(t)
  end
end

"""
    chzip(continuables...)

Zipping continuables via Channel
"""
chzip(cs::AbstractContinuable...) = @cont begin
  # or use aschannel and iterate
  channel_cs = aschannel.(cs)
  for t in zip(channel_cs...)
    cont(t)
  end
end

"""
    zip(continuables...; [lazy])

Constructs new Continuable with elements from the given continuables zipped up.
I.e. will yield for each position in the original continuables a tuple `(x, y, ...)`
where `x`, `y`, ... are the elements from `continuables` at the same position respectively.

If `lazy=true` (default), it will use Channels to do the zipping.
Elseif `lazy=false`, it will use Arrays instead.

!!! warning CAUTION
    `zip` on Continuables is not performant, but will fallback to either Channels (`lazy=true`, default) which are
    very slow, or Arrays (`lazy=false`) which will load everything into Memory.
"""
function Base.zip(cs::AbstractContinuable...; lazy=true)
  if lazy
    chzip(cs...)
  else
    azip(cs...)
  end
end

"""
    cycle(continuable[, n])

Constructs new Continuable which loops through the given continuable.
If `n` is given, it will loop `n` times, otherwise endlessly.
"""
cycle(continuable::AbstractContinuable) = @cont while true
  continuable(cont)
end

cycle(continuable::AbstractContinuable, n::Integer) = @cont for _ in 1:n
  continuable(cont)
end

## combine continuables --------------------------------------------

# IMPORTANT we cannot overload the empty product as it would conflict with iterables

"""
    product(continuables...)

Construct a new Continuable which yields all combinations of the given continuables, analog
to how Iterators.product work for iterables.

Mind that `product()` will still return an empty iterator instead of an empty Continuable.
Use [`emptycontinuable`](@ref) instead if you need an empty Continuable.
"""
product(c1::AbstractContinuable) = c1

# note this function in fact returns a continuable, however it is written as highlevel as that no explicit "f(...) = cont -> begin ... end" is needed
product(c1::AbstractContinuable, c2::AbstractContinuable) = @cont begin
  c1() do x
    c2() do y
      cont((x,y))
    end
  end
end

# this method is underscored because we assume the first continuation to deliver tuples and not values
_product(c1::AbstractContinuable, c2::AbstractContinuable) = @cont begin
  c1() do t
    c2() do x
      cont(tuple(t..., x))
    end
  end
end

@Ref function product(c1::AbstractContinuable, c2::AbstractContinuable, cs::Vararg{<:AbstractContinuable})
  acc = Ref{Any}(product(c1, c2))  # make first into singleton tuple to start recursion
  for continuable in cs
    acc = _product(acc, continuable)
  end
  acc
end


"""
    flatten(continuable_of_continuables)

Constructs new Continuable by concatinating all continuables in the given `continuable_of_continuables`.
Analog to Iterators.flatten.

For iterables of continuable use `Continuables.chain(iterable_of_continuables...)` instead.
"""
@cont function flatten(continuable::AbstractContinuable)
  continuable() do subcontinuable
    subcontinuable(cont)
  end
end

"""
    chain(continuables...)
    chain(iterables...) = flatten(iterables)

When given Continuables it will construct a new continuable by concatinating all given continuables.
When given anything else it will default to use `Iterator.flatten`.
"""
chain(iterables::Vararg) = flatten(iterables)
chain(cs::Vararg{<:AbstractContinuable}) = @cont begin
  for continuable in cs
    continuable(cont)
  end
end


# --------------------------

"""
    take(continuable, n)
    take(n, continuable)

Construct a new Continuable which only yields the first `n` elements.
`n` can be larger as the total length, no problem.
"""
@cont @Ref function take(continuable::AbstractContinuable, n::Integer)
  i = Ref(0)
  stoppable(continuable) do x
    i += 1
    if i > n
      stop()
    end
    cont(x)
  end
end
take(n::Integer, continuable::AbstractContinuable) = take(continuable, n)

"""
    takewhile(predicate, continuable)
    takewhile(predicate, iterable)

If given a Continuable, it constructs a new Continuable yielding elements until `predicate(element)` returns `false`.

Also implements a respective functionality for iterables for convenience.
"""
takewhile(bool, iterable) = TakeWhile(bool,  iterable)
@cont function takewhile(bool, continuable::AbstractContinuable)
  stoppable(continuable) do x
    if !bool(x)
      stop()
    end
    cont(x)
  end
end


"""
    drop(continuable, n)
    drop(n, continuable)

Construct a new Continuable which yields all elements but the first `n`.
`n` can be larger as the total length, no problem.
"""
@cont @Ref function drop(continuable::AbstractContinuable, n::Integer)
  i = Ref(0)
  continuable() do x
    i += 1
    if i > n
      cont(x)
    end
  end
end
drop(n::Integer, continuable::AbstractContinuable) = drop(continuable, n)

"""
    dropwhile(predicate, continuable)
    dropwhile(predicate, iterable)

If given a Continuable, it constructs a new Continuable yielding elements until `predicate(element)` returns `true`.

Also implements a respective functionality for iterables for convenience.
"""
dropwhile(bool, iterable) = DropWhile(bool, iterable)
@cont @Ref function dropwhile(bool, continuable::AbstractContinuable)
  dropping = Ref(true)
  continuable() do x
    if dropping
      dropping &= bool(x)
      # without nested "if" statement we would have to use two separate if statements at the top (instead of using if else)
      !dropping && cont(x)
    else
      cont(x)
    end
  end
end


"""
    partition(continuable, n[, step])

Constructs new Continuable which yields whole subsections of the given continuable, gathered as Vectors.
`n` is the length of a subsection. The very last subsection might be of length `n` or smaller respectively, collecting
the remaining elements.

If `step` is given, the second subsection is exactly `step`-number of elements apart from the previous subsection,
and hence overlapping if `n > step`.
Further, importantly, if `step` is given, there is no rest, but each subsection will be guaranteed to have the same
length. This semantics is copied from [IterTools.jl](https://juliacollections.github.io/IterTools.jl/latest/#partition(xs,-n,-[step])-1)

# Examples
```jldoctest
julia> partition(i2c(1:10), 3) |> collect
4-element Array{Any,1}:
 Any[1, 2, 3]
 Any[4, 5, 6]
 Any[7, 8, 9]
 Any[10]
julia> partition(i2c(1:10), 5, 2) |> collect
3-element Array{Any,1}:
 Any[1, 2, 3, 4, 5]
 Any[3, 4, 5, 6, 7]
 Any[5, 6, 7, 8, 9]
julia> partition(i2c(1:10), 3, 3) |> collect
 4-element Array{Any,1}:
  Any[1, 2, 3]
  Any[4, 5, 6]
  Any[7, 8, 9]
```
"""
@cont @Ref function partition(continuable::AbstractContinuable, n::Integer)
  i = Ref(1)
  part = Ref(Vector(undef, n))
  continuable() do x
    part[i] = x
    i += 1
    if i > n
      cont(part)
      part = Vector(undef, n)
      i = 1
    end
  end
  # final bit # TODO is this wanted? with additional step parameter I think this is mostly unwanted
  if i > 1
    # following the implementation for iterable, we cut the length to the defined part
    cont(_takewhile_isassigned(part))
  end
end

@cont @Ref function partition(continuable::AbstractContinuable, n::Integer, step::Integer)
  i = Ref(0)
  n_overlap = n - step
  part = Ref(Vector(undef, n))
  continuable() do x
    i += 1
    if i > 0  # if i is negative we simply skip these
      part[i] = x
    end
    if i == n
      cont(part)
      if n_overlap > 0
        overlap = part[1+step:n]
        part = Vector(undef, n)
        part[1:n_overlap] = overlap
      else
        # we need to recreate new part because of references
        part = Vector(undef, n)
      end
      i = n_overlap
    end
  end
end

function _takewhile_isassigned(vec::Vector)
  n = length(vec)
  for i in 1:n
    if !isassigned(vec, i)
      return vec[1:(i-1)]
    end
  end
  return vec
end


"""
    groupbyreduce(by, continuable, op2[, op1])
    groupbyreduce(by, iterable, op2[, op1])

Group elements and returns OrderedDict of keys (constructed by `by`) and values (aggregated with `op2`/`op1`)
If given anything else then a continuable, we interpret it as an iterable and provide the same functionality.

# Parameters

by: function of element to return the key for the grouping/dict
continuable: will get grouped
op2: f(accumulator, element) = new_accumulator
op1: f(element) = initial_accumulator

# Examples
```jldoctest
julia> groupbyreduce(x -> x % 4, @i2c(1:10), (x, y) -> x + y)
OrderedCollections.OrderedDict{Any,Any} with 4 entries:
  1 => 15
  2 => 18
  3 => 10
  0 => 12
julia> groupbyreduce(x -> x % 4, @i2c(1:10), (x, y) -> x + y, x -> x+5)
OrderedCollections.OrderedDict{Any,Any} with 4 entries:
  1 => 20
  2 => 23
  3 => 15
  0 => 17
```
"""
function groupbyreduce(by, continuable::AbstractContinuable, op2, op1=identity)
  d = OrderedDict()
  continuable() do x
    key = by(x)
    if key in keys(d)
      d[key] = op2(d[key], x)
    else
      d[key] = op1(x)
    end
  end
  d
end
# adding iterable versions for the general case (tests showed that these are actually compiling to the iterable version in terms of code and speed, awesome!)
groupbyreduce(by, iterable, op2, op1=identity) = groupbyreduce(by, ascontinuable(iterable), op2, op1)


"""
    groupby(f, continuable)
    groupby(f, iterable)

Wrapper around the more general [`groupbyreduce`](@ref) which combines elements to a Vector.
If you happen to aggregate your resulting grouped Vectors, think about using `groupbyreduce` directly, as
this can massively speed up aggregations.

Note that the interface is different from `IterTools.groupby`, as we directly return an OrderedDict
(instead of a iterable of values).

# Examples

```jldoctest
julia> groupby(x -> x % 4, @i2c 1:10)
OrderedCollections.OrderedDict{Any,Any} with 4 entries:
  1 => [1, 5, 9]
  2 => [2, 6, 10]
  3 => [3, 7]
  0 => [4, 8]
```
"""
groupby(f, continuable::AbstractContinuable) = groupbyreduce(f, continuable, push!, x -> [x])
groupby(f, iterable) = groupby(f, ascontinuable(iterable))


## subsets & peekiter -------------------------------------------------------

# subsets seem to be implemented for arrays in the first place (and not iterables in general)
# hence better use IterTools.subsets directly

# peekiter is the only method of Iterators.jl missing. However it in fact makes no sense for continuables
# as they are functions and don't get consumed

## extract values from continuables  ----------------------------------------

"""
    nth(continuable, n)
    nth(n, continuable)

Extracts the `n`th element from the given continuable.

# Examples
```jldoctest
julia> nth(i2c(4:10), 3)
6
julia> nth(1, i2c(4:10))
4
```
"""
@Ref function nth(continuable::AbstractContinuable, n::Integer)
  i = Ref(0)
  ret = stoppable(continuable) do x
    i += 1
    if i==n
      # CAUTION: we cannot use return here as usual because this is a subfunction. Return works here more like continue
      stop(x)
    end
  end
  if ret === nothing
    error("given continuable has length $i < $n")
  end
  ret
end
nth(n::Integer, continuable::AbstractContinuable) = nth(continuable, n)

end  # module
