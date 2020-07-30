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
  cont, @cont, Continuable,
  @Ref, stoppable, stop,
  singleton, repeated, iterated,
  aschannel, ascontinuable, i2c, @i2c,
  reduce, reduce!, zip, product, chain, flatten, cycle, foreach, map, all, any, sum, prod,
  take, takewhile, drop, dropwhile, partition, groupbyreduce, groupby,
  nth

using Compat
using ExprParsers
using DataTypesBasic
using OrderedCollections

include("utils.jl")
include("itertools.jl")

## Continuable Core -------------------------------------------------------------------------

"""
`cont` is reserved function parameter name
"""
cont(args...; kwargs...) = error("`cont` is reserved to be used within `Continuables.@cont`")


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
struct Continuable{Func}
  f::Func
end
(c::Continuable)(cont) = c.f(cont)

include("./syntax.jl")  # parts of syntax.jl require the Continuable definition, hence here

Base.IteratorSize(::Continuable) = Base.SizeUnknown()
@Ref function Base.length(continuable::Continuable)
  i = Ref(0)
  continuable() do _
    i += 1
  end
  i
end

Base.IteratorEltype(::Continuable{Any}) = Base.EltypeUnknown()
Base.eltype(::Continuable) = Any

# Continuable cannot implement Base.iterate efficiently


## conversions ----------------------------------------------

function aschannel(continuable::Continuable, size=0; elemtype=Any, taskref=nothing, spawn=false)
  Channel{elemtype}(size, taskref=taskref, spawn=spawn) do channel
    continuable() do x
      put!(channel, x)
    end
  end
end

ascontinuable(iterable) = @cont foreach(cont, iterable)
const i2c = ascontinuable
macro i2c(expr)
  esc(:(ascontinuable($expr)))
end


## factories -----------------------------------------------

singleton(value) = @cont cont(value)

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

@cont @Ref function iterated(f, x)
  a = Ref(x)
  while true
    a = f(a)
    cont(a)
  end
end


## core helpers ----------------------------------------------------------

function Base.collect(c::Continuable)
  everything = Vector(undef, 0)
  reduce!(push!, c, init = everything)
end

@Ref function Base.collect(c::Continuable, n)
  a = Vector(undef, n)
  # unfortunately the nested call of enumerate results in slower code, hence we have a manual index here
  # this is so drastically that for small n this preallocate version with enumerate would be slower than the non-preallocate version
  i = Ref(1)
  c() do x
    a[i] = x
    i += 1
  end
  a
end

@cont @Ref function Base.enumerate(continuable::Continuable)
  i = Ref(1)
  continuable() do x
    cont((i, x))
    i += 1
  end
end

Base.foreach(func, continuable::Continuable) = continuable(func)
Base.map(func, continuable::Continuable) = @cont continuable(x -> cont(func(x)))

@cont function Base.filter(bool, continuable::Continuable)
  continuable() do x
    if bool(x)
      cont(x)
    end
  end
end

Base.reduce(op, continuable::Continuable; init = nothing) = reduce_continuable(op, continuable, init)

struct EmptyStart end
@Ref function reduce_continuable(op, continuable, init::Nothing)
  acc = Ref{Any}(EmptyStart())
  lifted_op(acc::EmptyStart, x) = x
  lifted_op(acc, x) = op(acc, x)
  continuable() do x
    acc = lifted_op(acc, x)
  end
  acc
end
@Ref function reduce_continuable(op, continuable, init)
  acc = Ref(init)
  continuable() do x
    acc = op(acc, x)
  end
  acc
end

"""
  mutating version of reduce!

if no `init` is given
    `op!` is assumed to mutate a hidden state (equivalent to mere continuation)
else
    `init` is the explicit state and will be passed to `op!` as first argument (the accumulator)
"""
function reduce!(op!, continuable::Continuable; init = nothing)
  if isnothing(init)
    continuable(op!)
  else
    reduce!(op!, continuable, init)
  end
end
function reduce!(op!, continuable::Continuable, acc)
  continuable() do x
    op!(acc, x)
  end
  acc
end

Base.sum(c::Continuable) = reduce(+, c)
Base.prod(c::Continuable) = reduce(*, c)

@Ref function Base.all(continuable::Continuable; lazy=true)
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
Base.all(f, continuable::Continuable; kwargs...) = all(map(f, continuable); kwargs...)


@Ref function Base.any(continuable::Continuable; lazy=true)
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
Base.any(f, continuable::Continuable; kwargs...) = any(map(f, continuable); kwargs...)

## zip ----------------------------
# zip is the only method which seems to be unimplementable with continuations
# hence we have to go to tasks or arrays

"""
  zipping continuables via intermediate array representation

CAUTION: loads everything into memory
"""
azip(cs...) = @cont begin
  # not possible with continuations... bring it to memory and apply normal zip
  array_cs = collect.(cs)
  for t in zip(array_cs...)
    cont(t)
  end
end

"""
  zipping continuables via Channel
"""
chzip(cs...) = @cont begin
  # or use aschannel and iterate
  channel_cs = aschannel.(cs)
  for t in zip(channel_cs...)
    cont(t)
  end
end

function Base.zip(cs::Continuable...; lazy=true)
  if lazy
    chzip(cs...)
  else
    azip(cs...)
  end
end


const cycle = Base.Iterators.cycle
cycle(continuable::Continuable) = @cont while true
  continuable(cont)
end

cycle(continuable::Continuable, n::Integer) = @cont for _ in 1:n
  continuable(cont)
end

## combine continuables --------------------------------------------

# IMPORTANT we cannot overload Base.Iterators.product because the empty case cannot be distinguished between both (long live typesystems like haskell's)
# but let's default to it
product(args...; kwargs...) = Base.Iterators.product(args...; kwargs...)
product() = @cont ()  # mind the space!!

product(c1::Continuable) = c1

# note this function in fact returns a continuable, however it is written as highlevel as that no explicit "f(...) = cont -> begin ... end" is needed
product(c1::Continuable, c2::Continuable) = @cont begin
  c1() do x
    c2() do y
      cont((x,y))
    end
  end
end

# this method is underscored because we assume the first continuation to deliver tuples and not values
_product(c1::Continuable, c2::Continuable) = @cont begin
  c1() do t
    c2() do x
      cont(tuple(t..., x))
    end
  end
end

@Ref function product(c1::Continuable, c2::Continuable, cs::Vararg{<:Continuable})
  acc = Ref(product(c1, c2))  # make first into singleton tuple to start recursion
  for continuable in cs
    acc = _product(acc, continuable)
  end
  acc
end


const flatten = Base.Iterators.flatten
"""
for iterables of continuable use Continuables.chain(...)
"""
@cont function flatten(continuable::Continuable)
  continuable() do subcontinuable
    subcontinuable(cont)
  end
end

chain(cs::Vararg) = flatten(cs)
chain(cs::Vararg{<:Continuable}) = @cont begin
  for continuable in cs
    continuable(cont)
  end
end


# --------------------------

# generic cmap? only with zip and this is not efficient unfortunately
const take = Base.Iterators.take
@cont @Ref function take(continuable::Continuable, n::Integer)
  i = Ref(0)
  stoppable(continuable) do x
    i += 1
    if i > n
      stop()
    end
    cont(x)
  end
end
take(n::Integer, continuable::Continuable) = take(continuable, n)

takewhile(bool, iterable) = TakeWhile(bool,  iterable)
@cont function takewhile(bool, continuable::Continuable)
  stoppable(continuable) do x
    if !bool(x)
      stop()
    end
    cont(x)
  end
end

const drop = Base.Iterators.drop
@cont @Ref function drop(continuable::Continuable, n::Integer)
  i = Ref(0)
  continuable() do x
    i += 1
    if i > n
      cont(x)
    end
  end
end

dropwhile(bool, iterable) = DropWhile(bool, iterable)
@cont @Ref function dropwhile(bool, continuable::Continuable)
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

function drop_from_first_unassigned(vec::Vector)
  n = length(vec)
  for i in 1:n
    if !isassigned(vec, i)
      return vec[1:(i-1)]
    end
  end
  return vec
end


const partition = Base.Iterators.partition
@cont @Ref function partition(continuable::Continuable, n::Integer)
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
    cont(drop_from_first_unassigned(part))
  end
end

@cont @Ref function partition(continuable::Continuable, n::Integer, step::Integer)
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


# the interface is different from Itertools.jl
# we directly return an OrderedDictionary instead of a iterable of values only

"""
  group elements of `continuable` by `by`, aggregating immediately with `op2`/`op1`

Parameters
----------
by: function of element to return the key for the grouping/dict
continuable: will get grouped
op2: f(accumulator, element) = new_accumulator
op1: f(element) = initial_accumulator
"""
function groupbyreduce(by, continuable::Continuable, op2, op1=identity)
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
groupby(f, continuable::Continuable) = groupbyreduce(f, continuable, push!, x -> [x])

# adding iterable versions for the general case (tests showed that these are actually compiling to the iterable version in terms of code and speed, awesome!)
groupbyreduce(by, iterable, op2, op1=identity) = groupbyreduce(by, ascontinuable(iterable), op2, op1)
groupby(f, iterable) = groupby(f, ascontinuable(iterable))


## subsets & peekiter -------------------------------------------------------

# subsets seem to be implemented for arrays in the first place (and not iterables in general)
# hence better use IterTools.subsets directly

# peekiter is the only method of Iterators.jl missing. However it in fact makes no sense for continuables
# as they are functions and don't get consumed

## extract values from continuables  ----------------------------------------

@Ref function nth(continuable::Continuable, n::Integer)
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
nth(n::Integer, continuable::Continuable) = nth(continuable, n)

end  # module
