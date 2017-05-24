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
# TODO default to regarding continuables as functions?

## Considering Return Types of functions

# https://discourse.julialang.org/t/using-core-inference-return-type/2945/2
# T = typeof(f(a,b))
# This is actually a pretty good way to do it if you
# have canonical values for a and b that you know the function accepts and does not throw an error on
# know the function is type stable (although not necessarily type inferrable)
# the function has no side effects
# The computation is not done (i.e. optimized out) if the function has no side effects, is type stable, does not depend on any global state, and the compiler is able to figure all these facts out. Providing the Base.@pure annotation may be necessary for all this to be true.

# https://github.com/JuliaLang/julia/issues/1090

# @schlichtanders one easy way of getting the return type without getting your hands dirty
# (if you are doing a map or something) is to call map on an empty subset of the array.
# E.g. a = [2.1, 2]; eltype(map(x->x, a[1:0]))


## module start

module Continuables
export
  FRef, crange, ccollect, @c2a, c2a, astask, @c2t, c2t, ascontinuable, @i2c, i2c, stoppable, stop, @stoppable,
  cconst, cmap, cfilter, creduce, creduce!, mzip, tzip, cproduct, cchain, ccycle,
  ctake, ctakewhile, cdrop, cdropwhile, cflatten, cpartition, cgroupbyreduce,
  cgroupby, cdistinct, cnth, ccount, crepeatedly, citerate, @Ref, FRef, MRef, ARef, cenumerate, ccombinations,
  csubsets, check_empty, memoize, nth, second, cslices, csuppress, csuppress_inner, csuppress_outer

## Core functions --------------------------------------------------

# we can use Julia's default Ref type for single variable references
# however Ref unfortunately results into immutable errors when used with Array...
# so we want to have a general easy version to reference something.
# To avoid visual noise, we introduce a version of Ref which is always mutable
type MRef{T}
  x::T
end
# alternatively, specifying the concrete parametric Type also ensures immutability in the current implementation

# some more aliases are provided
# (because of the concrete type, they work with both MRef and Ref as references)
typealias FRef Ref{Function}
typealias ARef Ref{Any}

function replace_exprargs!(expr::Expr, old, new)
  for (i, subexpr) in enumerate(expr.args)
    if subexpr == old
      expr.args[i] = new
    end
  end
end

function replace_subexpr!(expr::Expr, old, new)
  replace_exprargs!(expr, old, new)
  for subexpr in expr.args
    replace_subexpr!(subexpr, old, new)
  end
end

function refify!(expr::Expr, Refs::Vector{Symbol}=Vector{Symbol}())
  for (i, a) in enumerate(expr.args)
    if (isa(a, Expr) && a.head == :(=) && isa(a.args[1], Symbol)
        && isa(a.args[2], Expr) && a.args[2].head == :call && length(a.args[2].args) > 0
        && (a.args[2].args[1] ∈ [:Ref, :FRef, :ARef, :MRef]  # simple call
            || (isa(a.args[2].args[1], Expr)
                && a.args[2].args[1].head == :curly  # call with parametric type
                && a.args[2].args[1].args[1] in [:Ref, :MRef])))
      push!(Refs, a.args[1])

    else
      substituted = false

      for r in Refs
        if a == r
          expr.args[i] = :($r.x)
          substituted = true
          break
        end
      end

      if !substituted
        refify!(a, Refs)
      end
    end
  end
end

refify!(s, ::Vector{Symbol}) = ()  # if there is no expression, we cannot refify anything

macro Ref(expr)
  refify!(expr)
  esc(expr)
end


typealias StoredIterable Union{Tuple, AbstractArray}

crange(first, step, last) = cont -> begin
  for i in first:step:last
    cont(i)
  end
end

crange(last) = crange(1, 1, last)
crange(first, last) = crange(first, 1, last)

crange(cont::Function, last) = crange(last)(cont)
crange(cont::Function, first, last) = crange(first, last)(cont)
crange(cont::Function, first, step, last) = crange(first, step, last)(cont)


ccollect(continuable) = creduce!(push!, [], continuable)
import Base.collect
collect(continuable::Function) = ccollect(continuable)

@Ref function ccollect(continuable, n, T=Any)
  a = Vector{T}(n)
  # unfortunately the nested call of enumerate results in slower code, hence we have a manual index here
  # this is so drastically that for small n this preallocate version with enumerate would be slower than the non-preallocate version
  i = Ref(1)
  continuable() do x
    a[i] = x
    i += 1
  end
  a
end

astask(continuable) = @task continuable(produce)

ascontinuable(iterable) = cont -> begin
  for i in iterable
    cont(i)
  end
end


c2a = ccollect
c2t = astask
i2c = ascontinuable
traverse = ascontinuable

macro c2a(expr)
  :(ccollect($expr))
end

macro c2t(expr)
  :(astask($expr))
end

macro i2c(expr)
  :(ascontinuable($expr))
end


type StopException <: Exception
  ret::Any  # for now we have to make ret changeable (i.e. type Any) because we change it on runtime
end
stop = StopException(nothing)
# when calling a StopException, make this raise the Exception itself
function (exc::StopException)(ret)
  exc.ret = ret
  throw(exc)
end
function (exc::StopException)()
  throw(exc)
end


stoppable(continuable) = cond_cont -> begin
  thisverystop = StopException(nothing)
  cont = cond_cont(thisverystop)
  try
    continuable(cont)
  catch exc
    if exc !== thisverystop
      rethrow(exc)
    end
    return exc.ret
  end
end
stoppable(cond_cont, continuable) = stoppable(continuable)(cond_cont)

macro stoppable(expr)
  @assert expr.head == :call
  # assure this is a call of a function with first argument being anonymous function
  # this does not work with named functions, however then also syntactically the belonging between stoppable and stop() is no longer obvious
  @assert expr.args[2].head == :->

  cond_cont = Expr(:->, :stop, expr.args[2])  # we simply have to overwrite the reference to Stop so that the do continuation will see this Stop instead of the default stop

  if length(expr.args) == 2
    # if the argument is called with a single argument only, we assume this is the continuation and hence expr.args[1] is the continuable itself
    continuable = expr.args[1]
  else
     # we assume that without continuation, the original method returns a continuable
     # skip continuation arg for original continuable
    continuable = Expr(:call, expr.args[1], expr.args[3:end]...)
  end
  esc(Expr(:call, :stoppable, cond_cont, continuable))
end


check_empty(continuable) = cont -> @Ref begin
  empty = Ref(true)
  continuable() do x
    cont(x)
    if empty
      empty = false
    end
  end
  empty
end

check_empty(cont, continuable) = check_empty(continuable)(cont)


cconst(value) = cont -> cont(value)

## core functional helpers ----------------------------------------------------------
cenumerate(continuable) = cont -> @Ref begin
  i = Ref(1)
  continuable() do x
    cont((i, x))
    i += 1
  end
end
cenumerate(cont, continuable) = cenumerate(continuable)(cont)

# generic cmap? only with zip and this is not efficient unfortunately
"""
    cmap(f, continuable)

Continuable over values of a function applied to successive values from one continuable.
Because of zip not being straightforwardly compatible with continuables, cmap works only for a single continuable.

```jldoctest
julia> cmap(x -> x*x, crange(7, 10)) do i
            @show i
       end
i = 49
i = 64
i = 81
i = 100
```
"""
cmap(func, continuable) = cont -> begin
  continuable(x -> cont(func(x)))
end
cmap(cont, func, continuable) = cmap(func, continuable)(cont)

import Base.map
map(func, continuable::Function) = cmap(func, continuable)

cfilter(bool, continuable) = cont -> begin
  continuable() do x
    if bool(x)
      cont(x)
    end
  end
end
cfilter(cont, bool, continuable) = cfilter(bool, continuable)(cont)

import Base.filter
filter(func, continuable::Function) = cfilter(func, continuable)

@Ref function creduce{T}(op, v0::T, continuable)
  # we have to use always mutable Ref here, Ref(array) is unfortunately not mutable,
  # but Ref{Array}(array) surprisingly is (and also MRef{array})
  acc = Ref{T}(v0)
  continuable() do x
    acc = op(acc, x)
  end
  acc
end

function creduce!(op!, acc, continuable)
  continuable() do x
    op!(acc, x)
  end
  acc
end

import Base.sum
sum(continuable::Function) = creduce(+, 0, continuable)

import Base.reduce
reduce(op, v0, continuable::Function) = creduce(op, v0, continuable)


"""
    distinct(xs)

Go through values skipping over those already encountered.

```jldoctest
julia> cdistinct(@i2c [1,1,2,1,2,4,1,2,3,4]) do i
           @show i
       end
i = 1
i = 2
i = 4
i = 3
```
"""
cdistinct(continuable) = cont -> begin
  s = Set()
  continuable() do x
    if x ∉ s
      cont(x)
      push!(s, x)
    end
  end
end

cdistinct(cont, continuable) = cdistinct(continuable)(cont)


## zip ----------------------------
# zip is the only method which seems to be unimplementable with continuations
# hence we have to go to tasks or arrays

mzip(cs...) = cont -> begin
  # not possible with continuations... bring it to memory and apply normal zip
  mem_cs = ccollect.(cs)
  for t in zip(mem_cs...)
    cont(t)
  end
end

mzip(cont::Function, cs::StoredIterable) = mzip(cs...)(cont)

tzip(cs...) = cont -> begin
  # or use astask and iterate
  task_cs = astask.(cs)
  for t in zip(task_cs...)
    cont(t)
  end
end
tzip(cont::Function, cs::StoredIterable) = tzip(cs...)(cont)


## combine continuables --------------------------------------------


"""
    product(cs...)

Go through all combinations in the Cartesian product of the inputs.

Because of ambiguity you cannot use do notation straightforwardly, but only with either wrapping the arguments into an array
or tuple, or by calling the cproduct result again like done below in the example


```jldoctest
julia> cproduct(crange(3), crange(4,5))() do p
           @show p
       end
p = (1,4)
p = (1,5)
p = (2,4)
p = (2,5)
p = (3,4)
p = (3,5)
```
"""
cproduct() = cont -> ()

cproduct(c1) = cont -> begin
  c1() do x
    cont(x)
  end
end

# note this function in fact returns a continuable, however it is written as highlevel as that no explicit "f(...) = cont -> begin ... end" is needed
cproduct(c1, c2) = cont -> begin
  c1() do x
    c2() do y
      cont((x,y))
    end
  end
end

# this method is underscored because we assume the first continuation to deliver tuples and not values
_product(c1, c2) = cont -> begin
  c1() do t
    c2() do x
      cont(tuple(t..., x))
    end
  end
end

@Ref function cproduct(c1, c2, cs...)
  acc = FRef(cproduct(c1, c2))  # make first into singleton tuple to start recursion
  for continuable in cs
    acc = _product(acc, continuable)
  end
  acc
end

cproduct(cont::Function, cs::StoredIterable) = cproduct(cs...)(cont)


"""
    cchain(cs...)

Combine any number of continuables into one large continuable.
`chain(continuable)` will regard `continuable` as calling on sub-continuables and flattens the hierarchy respectively.

Because of ambiguity you cannot use do notation straightforwardly, but only with either wrapping the arguments into an array
or tuple, or by calling the cchain result again like done below in the example

```jldoctest
julia> cchain(crange(3), i2c(['a', 'b', 'c']))() do i
           @show i
       end
i = 1
i = 2
i = 3
i = 'a'
i = 'b'
i = 'c'
```
"""
cchain(nested_continuable) = cont -> begin
  nested_continuable() do continuable
    continuable(cont)
  end
end
cchain(cs...) = cont -> begin
  for continuable in cs
    continuable(cont)
  end
end
cchain(cont::Function, cs::StoredIterable) = cchain(cs...)(cont)



"""
    ccycle(continuable)
    ccycle(continuable, n)

Cycle through `iter` `n` times (or infintitely)

```jldoctest
julia> ccycle(1:3, 2) do i
           @show i
       end
i = 1
i = 2
i = 3
i = 1
i = 2
i = 3
```
"""
ccycle(continuable::Function) = cont -> begin
  while true
    continuable(cont)
  end
end
ccycle(cont::Function, continuable::Function) = ccylce(continuable)(cont)

ccycle(continuable::Function, n::Integer) = cont -> begin
  for _ in 1:n
    continuable(cont)
  end
end
ccycle(cont::Function, continuable::Function, n::Integer) = ccylce(continuable, n)(cont)


# --------------------------

"""
    ctake(continuable, n::Int)

Like `take()`, a new continuable that goes through at most the first `n` calls of `continuable`.

```jldoctest
julia> a = crange(1,2,11)
julia> collect(ctake(a, 3))
3-element Array{Any,1}:
 1
 3
 5
```
"""
ctake(continuable::Function, n::Integer) = cont -> @Ref begin
  i = Ref(0)
  @stoppable continuable() do x
    i += 1
    if i > n
      stop()
    end
    cont(x)
  end
end
ctake(cont::Function, continuable::Function, n::Integer) = ctake(continuable, n)(cont)

# note the two stoppable versions are exactly equivalent, we use both version to illustrate @stoppable
ctakewhile(continuable::Function, bool::Function) = cont -> begin
  stoppable(continuable) do stop
    x -> begin
      if !bool(x)
        stop()
      end
      cont(x)
    end
  end
end
ctakewhile(cont, continuable, bool) = ctakewhile(continuable, bool)(cont)


cdrop(continuable::Function, n::Integer) = cont -> @Ref begin
  i = Ref(0)
  continuable() do x
    i += 1
    if i >= n
      cont(x)
    end
  end
end
cdrop(cont, continuable, n::Integer) = cdrop(continuable, n)(cont)

cdropwhile(continuable::Function, bool::Function) = cont -> @Ref begin
  dropping = Ref(true)
  continuable() do x
    if dropping
      dropping &= bool(x)
    # TODO adding else with cont(x); return would increase the amounts of asking droppibg by factor of 2. Test this!
    end
    if !dropping
      cont(x)
    end
  end
end
cdropwhile(cont, continuable, bool::Function) = cdropwhile(continuable, bool)(cont)


cflatten(iterable) = cont -> begin
  for continuable in iterable
    continuable(cont)
  end
end

cflatten(continuable::Function) = cont -> begin
  continuable() do subcontinuable
    subcontinuable(cont)
  end
end

cflatten(cont, iterable) = cflatten(iterable)(cont)

"""
    partition(cs, n, [step])

Group values into `n`-tuples.

```jldoctest
julia> cpartition(crange(9), 3) do i
           @show i
       end
i = [1,2,3]
i = [4,5,6]
i = [7,8,9]
```

If the `step` parameter is set, each tuple is separated by `step` values.

```jldoctest
julia> cpartition(crange(9), 3, 2) do i
           @show i
       end
i = [1,2,3]
i = [3,4,5]
i = [5,6,7]
i = [7,8,9]

julia> cpartition(crange(9), 3, 3) do i
           @show i
       end
i = [1,2,3]
i = [4,5,6]
i = [7,8,9]

julia> cpartition(crange(9), 2, 3) do i
           @show i
       end
i = [1,2]
i = [4,5]
i = [7,8]
```
"""
cpartition(continuable, n::Integer, T::Type=Void) = cont -> @Ref begin
  # TODO one could add the option to extract T from the first element of the continuable
  if T === Void
    T = typeof(first(continuable))
  end
  i = Ref(1)
  part = MRef(Vector{T}(n))  # Ref(array) is immutable, would have to use Ref{Vector{T}}, but this is much worse readible
  continuable() do x
    part[i] = x
    i += 1
    if i > n
      cont(part)
      part = Vector{T}(n)
      i = 1
    end
  end
  # final bit # TODO is this wanted? Iterators does not implement it, hence lets get rid of it
  # if i > 1
  #   cont(part)
  # end
end
cpartition(cont, continuable, n::Integer, T::Type=Void) = cpartition(continuable, n, T)(cont)


cpartition(continuable, n::Integer, step::Integer, T::Type=Void) = cont -> @Ref begin
  if T === Void
    T = typeof(first(continuable))
  end
  i = Ref(0)
  n_overlap = n - step
  part = MRef(Vector{T}(n))  # Ref(array) is immutable, would have to use Ref{Vector{T}}, but this is much worse readible
  continuable() do x
    i += 1
    if i > 0  # if i is negative we simply skip these
      part[i] = x
    end
    if i == n
      cont(part)
      if n_overlap > 0
        overlap = part[1+step:n]
        part = Vector{T}(n)
        part[1:n_overlap] = overlap
      else
        # we need to recreate new part because of references
        part = Vector{T}(n)
      end
      i = n_overlap
    end
  end
end

cpartition(cont, continuable, n::Integer, step::Integer, T::Type=Void) = cpartition(continuable, n, step, T)(cont)

# the interface is different from Itertools.jl
# we directly return an OrderedDictionary instead of a iterable of values only
import DataStructures.OrderedDict
"""
    cgroupbyreduce(by, continuable, op2, op1=identity)

Combines consecutive values that share the same result of applying `f` into an OrderedDict.
`op1` each first element to the accumulation type, and `op2(acc, x)` combines the newly found value
into the respective accumulator.

```jldoctest
julia> cgroupbyreduce(x -> div(x, 3), crange(10), +)
DataStructures.OrderedDict{Any,Any} with 4 entries:
  0 => 3
  1 => 12
  2 => 21
  3 => 19
```
"""
function cgroupbyreduce(by, continuable, op2, op1=identity)
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

# TODO go further her - groupby is different from Iterators!!
"""
    groupby(f, cs)

Group consecutive values that share the same result of applying `f` into an OrderedDict.

```jldoctest
julia> cgroupby(x -> x[1], @i2c ["face", "foo", "bar", "book", "baz", "zzz"])
DataStructures.OrderedDict{Any,Any} with 3 entries:
  'f' => String["face","foo"]
  'b' => String["bar","book","baz"]
  'z' => String["zzz"]
```
"""
cgroupby(f, continuable) = cgroupbyreduce(f, continuable, push!, x -> [x])


## ccombinations and subset ------------------------------------------------------------------
# Note that the function ccombinations Base corresponds to the function csubsets in Iterators.jl
# we follow Iterators.jl because we think ccombinations can also be meaningfully used for ccombinations between arbitrary continuables
# csubsets is an intuitive subset denoting ccombinations with itself

# note that the tuple implementation is actually faster than the array implementation (did benchmarking)

ccombinations(offset::Integer, c1, c2) = cont -> @Ref begin
  # TODO Discuss: is stoppable good here or does it just makes things slower instead of faster? we decided to leave it out for now as this is really meant as the baseclass which almost always works
  i = Ref(1)
  c1() do x
    nr_previous = i - offset
    if nr_previous > 0  # ctake would also work with negative values, however we can shortcut here to make it faster
      ctake(c2, nr_previous) do y
        cont((x,y))
      end
    end
    i += 1
  end
end

# sum_{i=1}^n i(i-k) = sum_{i=1}^n i^2  - sum_{i=1}^n ik = n(n+1)(2n+1)/6 - k n(n+1)/2 = 1/6 n(n+1) (2n+1 - 3k)    = n^5/5 + n^4/2 + n^3/3 - kn^2/2 - n(15k+1)/30
# it is in fact a recursive thing...
# for dim=2  we have sum_{i=1}^n i-k = n/2 (n+1-k)

using Memoize

# we use memoize as this is only needed for a low number of results, it is like table thus
@memoize function len_ccombinations(n::Integer, offset::Integer=0, dim::Integer=2)
  if dim == 1
    return n
  end

  # otherwise recurse
  acc = 0
  for i in 1:(n - offset)
    acc += len_ccombinations(i, offset, dim-1)
  end
  acc
end

_ccombinations(offset::Integer, c1, c2, dim_c2::Integer) = cont -> @Ref begin
  i = Ref(1)
  c1() do x
    nr_previous_combinations = len_ccombinations(i - offset, offset, dim_c2)
    if nr_previous_combinations > 0
      ctake(c2, nr_previous_combinations) do y
        cont((x, y...))
      end
    end
    i += 1
  end
end


@Ref function ccombinations(offset::Integer, c1, c2, cs...)
  dim = Ref(2)
  acc = FRef(ccombinations(offset, c1, c2))
  for c in cs
    acc = _ccombinations(offset, c, acc, dim)
    dim += 1
  end
  acc
end

ccombinations(cont, offset::Integer, cs...) = ccombinations(offset, cs...)(cont)
ccombinations(cs...) = ccombinations(1, cs...)
ccombinations_with_replacement(cs...) = ccombinations(0, cs...)
ccombinations(cont, cs::StoredIterable) = ccombinations(cs...)(cont)
ccombinations_with_replacement(cont, cs::StoredIterable) = ccombinations_with_replacement(cs...)(cont)


"""
    csubsets(continuable)
    csubsets(continuable, k)

Iterate over every subset of the collection `xs`. You can restrict the subsets to a specific
size `k`.

```jldoctest
julia> csubsets(@i2c [1, 2, 3]) do i
          @show i
       end
i = ()
i = (1,)
i = (2,)
i = (3,)
i = (2,1)
i = (3,1)
i = (3,2)
i = (3,2,1)

julia> csubsets(crange(4), 2) do i
          @show i
       end
i = (2,1)
i = (3,1)
i = (3,2)
i = (4,1)
i = (4,2)
i = (4,3)
```
"""
function csubsets(continuable, k::Integer)
  if k==0
    cont -> cont(())
  elseif k==1
    cmap(tuple, continuable)
  else
    cs = (continuable, continuable)
    for i in 3:k
      cs = tuple(cs..., continuable)
    end
    ccombinations(1, cs...)
  end
end
csubsets(cont, continuable, k::Integer) = csubsets(continuable, k)(cont)

csubsets(continuable) = cont -> begin
# TODO Discuss: the first n=1000 iterations or something could be done without check_empty which will improve performance for long continuables,
# while decreasing performance for small continuables of course because of many empty continuations
  k = 0
  while true
    empty = check_empty(csubsets(continuable, k))(cont)
    if empty
      break
    end
    k += 1
  end
end
csubsets(cont, continuable) = csubsets(continuable)(cont)



# peekiter is the only method if Iterators.jl missing. However it in fact makes no sense for continuables
# as they are functions and don't get consumed



## extract values from continuables  ----------------------------------------

"""
    cnth(continuable, n)

Return the `n`th element of `continuable`. This is mostly useful for non-indexable collections.

```jldoctest
julia> cnth(crange(5,10), 3)
7
```
"""
@Ref function cnth(continuable, n::Integer)
  i = Ref(0)
  ret = @stoppable continuable() do x
    i += 1
    if i==n
      # CAUTION: we cannot use return here as usual because this is a subfunction. Return works here more like continue
      stop(x)
    end
  end
  if ret === nothing
    error("continuation shorter than n")
  end
  ret
end

cfirst(continuable) = cnth(continuable, 1)
csecond(continuable) = cnth(continuable, 2)

import Iterators.nth
nth(continuable::Function, n::Integer) = cnth(continuable, n)
import Base.first
first(continuable::Function) = cfirst(continuable)
second(continuable::Function) = csecond(continuable)

@Ref function ccount(continuable)
  i = Ref(0)
  continuable() do _
    i += 1
  end
  i
end


## create continuables ----------------------------
"""
    crepeatedly(f, n)

Call function `f` `n` times, or infinitely if `n` is omitted.

```julia
julia> t() = (sleep(0.1); Dates.millisecond(now()))
t (generic function with 1 method)

julia> collect(crepeatedly(t, 5))
5-element Array{Any,1}:
 993
  97
 200
 303
 408
```
"""
crepeatedly(f::Function) = cont -> begin
  while true
    cont(f())
  end
end
crepeatedly(cont::Function, f::Function) = crepeatedly(f)(cont)

crepeatedly(f::Function, n::Integer) = cont -> begin
  for _ in 1:n
    cont(f())
  end
end
crepeatedly(cont::Function, f::Function, n::Integer) = repeatedly(f, n)(cont)

"""
    citerate(f, x)

Continue over successive applications of `f`, as in `f(x)`, `f(f(x))`, `f(f(f(x)))`, ....

Use `ctake()` to obtain the required number of elements.

```jldoctest
julia> ctake(citerate(x -> 2x, 1), 5) do i
           @show i
       end
i = 1
i = 2
i = 4
i = 8
i = 16

julia> ctake(citerate(sqrt, 100), 6) do i
           @show i
       end
i = 100
i = 10.0
i = 3.1622776601683795
i = 1.7782794100389228
i = 1.333521432163324
i = 1.1547819846894583
```
"""
@Ref citerate(f::Function, x) = cont -> begin
  a = Ref(x)
  while true
    cont(a)
    a = f(a)
  end
end
citerate(cont::Function, f::Function, x) = citerate(f, x)(cont)


## Other Continuables specific helpers

memoize(continuable) = @Ref begin
  stored = []
  firsttime = Ref(true)
  cont -> begin
    if firsttime
      continuable() do x
        cont(x)
        push!(stored, x)
      end
      firsttime = false
    else
      for x in stored
        cont(x)
      end
    end
  end
end

memoize(continuable, n::Integer, T=Any) = @Ref begin
  stored = Vector{T}(n)
  firsttime = Ref(true)

  cont -> begin
    if firsttime
      i = Ref(1)
      continuable() do x
        cont(x)
        stored[i] = x
        i += 1
      end
      firsttime = false
    else
      for x in stored
        cont(x)
      end
    end
  end
end


## Extra functionalities

# Code taken from https://github.com/JuliaLang/julia/blob/2001c26a434021b691e39a8720114fb341d5ef4f/base/abstractarray.jl
# defined the other way around to match mapslices
cslices(cont, A::AbstractArray, dims) = cslices(cont, A, [dims...])
function cslices(cont, A::AbstractArray, dims::AbstractVector)
    if isempty(dims)
        return cmap(f,A)
    end

    dimsA = [indices(A)...]
    ndimsA = ndims(A)
    otherdims = setdiff([1:ndimsA;], dims)
    itershape = tuple(dimsA[otherdims]...)

    idx = Vector(ndimsA)  # Any[first(ind) for ind in indices(A)]
    for d in dims
        idx[d] = Colon()
    end

    ndimsO = length(otherdims)
    for I in CartesianRange(itershape)
        for i in 1:ndimsO
            idx[otherdims[i]] = I.I[i]
        end
        cont(A[idx...])
    end
end
cslices(A::AbstractArray, dims) = cont -> cslices(cont, A, dims)


csuppress(cont, exctype::Type=Exception) = x -> begin
  try
    cont(x)
  catch exc
    if !isa(exc, exctype)
      rethrow()
    end
  end
end
csuppress(exctype::Type=Exception) = cont -> csuppress(cont, exctype)


csuppress_inner(continuable, exctype::Type=Exception) = cont -> begin
  continuable() do x
    try
      cont(x)
    catch exc
      if !isa(exc, exctype)
        rethrow()
      end
    end
  end
end
csuppress_inner(cont, continuable, exctype::Type=Exception) = csuppress_inner(continuable, exctype)(cont)

csuppress_outer(continuable, exctype::Type) = cont -> begin
  try
    continuable(cont)
  catch exc
    if !isa(exc, exctype)
      rethrow()
    end
  end
end
csuppress_outer(cont, continuable, exctype::Type=Exception) = csuppress_outer(continuable, exctype)(cont)

end  # module
