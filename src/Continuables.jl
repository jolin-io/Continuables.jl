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
  singleton,
  astask, ascontinuable, @i2c, stoppable, stop, 
  reduce!, azip, tzip, product, chain, flatten, cycle, 
  take, takewhile, drop, dropwhile, partition, groupbyreduce, groupby,
  nth, @Ref, @cont

"""
``cont`` is reserved function parameter name
"""
cont(args...; kwargs...) = error("``cont`` is a reserved function parameter name")

# we decided to have an extra type to reuse existing function knowhow by properly dispatching
"""
  Continuable(func)

Assumes func to have a single argument, the continuation function (usually named `cont`).
"""
struct Continuable{Elem, Func, Length <: Union{Nothing, Integer, Base.IsInfinite}, Size <: Union{Nothing, Tuple{Vararg{Integer}}}}  # TODO add Length information like in the Iterable interface as typeparameters
  f::Func
  length::Length
  size::Size
  function Continuable{Elem}(func::Func; length=nothing, size=nothing) where {Elem, Func}
    new{Elem, Func, typeof(length), typeof(size)}(f, length, size)
  end
end
Continuable(f; kwargs...) = Continuable{Any}(f; kwargs...)
(c::Continuable)(cont) = c.f(cont)

include("./syntax.jl")  # some require the Continuable definition, hence here

const length = Base.length
length(c::Continuable{Elem, Length, Size}) where {Elem, Length <: Nothing, Size <: Tuple} = prod(c.size)
length(c::Continuable{Elem, Length}) where {Elem, Length <: Integer} = c.length
@Ref function length(continuable::Continuable)
  i = Ref(0)
  continuable() do _
    i += 1
  end
  i
end

Base.eltype(::Continuable{Elem}) where Elem = Elem

# Continuable cannot implement Base.iterate
# TODO does it make sense to implement Iterator Interface then?
Base.IteratorSize(::Continuable{Elem, Length, Size, Func}) where {Elem, Length <: Nothing, Size <: Nothing, Func} = Base.SizeUnknown()
Base.IteratorSize(::Continuable{Elem, Length, Size, Func}) where {Elem, Length <: Integer, Size <: Nothing, Func} = Base.HasLength()
Base.IteratorSize(::Continuable{Elem, Length, Size, Func}) where {Elem, Length <: Base.IsInfinite, Size <: Nothing, Func} = Base.IsInfinite()
Base.IteratorSize(::Continuable{Elem, Length, Size, Func}) where {Elem, Length, Size <: Tuple, Func} = Base.HasShape{length(Size.parameters)}()
Base.IteratorSize(::Continuable{Elem, Length, Size, Func}) where {Elem, Length, Size <: Tuple, Func} = Base.HasShape{length(Size.parameters)}()
Base.IteratorEltype(::Continuable{Any}) = Base.EltypeUnknown()


## Core Transformations ----------------------------------------

## Core functions --------------------------------------------------

const collect = Base.collect
function collect(c::Continuable{Elem, <:Integer, Nothing}) where Elem
  collect(c, length(c))
end
function collect(c::Continuable{Elem, <:Any, <:Tuple}) where Elem
  array = collect(c, length(c))
  reshape(array, size(c))
end
function collect(c::Continuable{Elem}) where Elem
  everything = Vector{Elem}()
  reduce!(push!, c, init = everything)
end

@Ref function collect(c::Continuable{Elem}, n) where Elem
  a = Vector{Elem}(n)
  # unfortunately the nested call of enumerate results in slower code, hence we have a manual index here
  # this is so drastically that for small n this preallocate version with enumerate would be slower than the non-preallocate version
  i = Ref(1)
  c() do x
    a[i] = x
    i += 1
  end
  a
end

# TODO udpate
astask(continuable) = @task continuable(produce)

ascontinuable(iterable) = @cont foreach(cont, iterable)
macro i2c(expr)
  esc(:(ascontinuable($expr)))
end

singleton(value) = @cont cont(value)

# We realise early stopping via exceptions

struct StopException{T} <: Exception
  ret::T
end
Stop = StopException(nothing)
stop() = throw(Stop)
stop(ret) = throw(StopException(ret))

stoppable(continuable::Continuable) = @cont begin
  try
    continuable(cont)
  catch exc
    if !isa(exc, StopException)
      rethrow(exc)
    end
    return exc.ret
  end
end


## core functional helpers ----------------------------------------------------------

const enumerate = Base.enumerate

@cont @Ref function enumerate(continuable::Continuable)
  i = Ref(1)
  continuable() do x
    cont((i, x))
    i += 1
  end
end

const map = Base.map
map(func, continuable::Continuable) = @cont continuable(x -> cont(func(x)))

const filter = Base.filter
@cont function filter(bool, continuable::Continuable)
  continuable() do x
    if bool(x)
      cont(x)
    end
  end
end

const reduce = Base.reduce
reduce(op, continuable::Continuable; init = nothing) = reduce_continuable(op, continuable, init)

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

function reduce!(op!, continuable::Continuable, acc)
  continuable() do x
    op!(acc, x)
  end
  acc
end


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

# TODO or Channels?
"""
  zipping continuables via tasks
"""
tzip(cs...) = @cont begin
  # or use astask and iterate
  task_cs = astask.(cs)
  for t in zip(task_cs...)
    cont(t)
  end
end


## combine continuables --------------------------------------------

# we cannot overload Base.Iterators.product because the empty case cannot be distinguished between both (long live typesystems like haskell's)
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

chain(cs::Vararg{<:Continuable}) = @cont begin
  for continuable in cs
    continuable(cont)
  end
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


const cycle = Base.Iterators.cycle
cycle(continuable::Continuable) = @cont while true
  continuable(cont)
end

cycle(continuable::Continuable, n::Integer) = @cont for _ in 1:n
  continuable(cont)
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

# TODO There is no takewhile in Base.Iterators.take ...
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
    if i >= n
      cont(x)
    end
  end
end

# TODO There is no dropwhile in Base.Iterators.take ...
@cont @Ref function dropwhile(bool, continuable::Continuable)
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

const partition = Base.Iterators.partition
@cont @Ref function partition(continuable::Continuable, n::Integer)
  i = Ref(1)
  part = Ref(Vector(n))
  continuable() do x
    part[i] = x
    i += 1
    if i > n
      cont(part)
      part = Vector(n)  # extract return type from cont function, possible? I think not, julia is not haskell... unfortunately
      i = 1
    end
  end
  # final bit # TODO is this wanted? with additional step parameter I think this is mostly unwanted
  if i > 1
    cont(part)
  end
end

@cont @Ref function partition(continuable::Continuable, n::Integer, step::Integer)
  i = Ref(0)
  n_overlap = n - step
  part = Ref(Vector(n))  # TODO get element-type from function return type
  continuable() do x
    i += 1
    if i > 0  # if i is negative we simply skip these
      part[i] = x
    end
    if i == n
      cont(part)
      if n_overlap > 0
        overlap = part[1+step:n]
        part = Vector(n)  # TODO get element-type from function return type
        part[1:n_overlap] = overlap
      else
        # we need to recreate new part because of references
        part = Vector(n)  # TODO get element-type from function return type
      end
      i = n_overlap
    end
  end
end


# the interface is different from Itertools.jl
# we directly return an OrderedDictionary instead of a iterable of values only
import DataStructures.OrderedDict

function groupbyreduce(by, continuable, op2, op1=identity)
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
groupby(f, continuable) = groupbyreduce(f, continuable, push!, x -> [x])

# subsets seem to be implemented for arrays in the first place (and not iterables in general)
# hence better use Iterators.subsets directly

# peekiter is the only method if Iterators.jl missing. However it in fact makes no sense for continuables
# as they are functions and don't get consumed

## extract values from continuables  ----------------------------------------

@Ref function nth(continuable::Function, n)
  i = Ref(0)
  ret = stoppable(continuable) do x
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

## create continuables ----------------------------


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

@cont @Ref function iterate(f, x)
  a = Ref(x)
  while true
    a = f(a)
    cont(a)
  end
end

end  # module
