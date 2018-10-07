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
  crange, ccollect, @c2a, astask, @c2t, ascontinuable, @i2c, stoppable, stop,
  cconst, cmap, cfilter, creduce, mzip, tzip, cproduct, chain, ccycle,
  ctake, ctakewhile, cdrop, cdropwhile, cflatten, cpartition, cgroupbyreduce,
  cgroupby, cnth, ccount, crepeatedly, citerate, Ref, @Ref, @cont, cenumerate

## Core functions --------------------------------------------------

# we use Julia's default Ref type for single variable references

function refify!(expr::Expr, Refs::Vector{Symbol}=Vector{Symbol}())
  @show expr
  expr.head == :. && return  # short cycle if we have a dot access expression, as we don't want to change in there

  for (i, a) in enumerate(expr.args)
    if (isa(a, Expr) && a.head == :(=) && isa(a.args[1], Symbol)
        && isa(a.args[2], Expr) && a.args[2].args[1] == :Ref && a.args[2].head == :call)
      push!(Refs, a.args[1])

    else
      substituted = false

      @show a
      @show Refs

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

function extract_symbol(a)
  if isa(a, Symbol)
    a
  elseif isa(a.args[1], Symbol) # something like Type annotation a::Any or Defaultvalue b = 3
    a.args[1]
  else # Type annotation with Defaultvalue
    a.args[1].args[1]
  end
end

macro cont(expr::Expr)
  expr = macroexpand(__module__, expr)  # for sub macros like @Ref and to simplify what this macro has to do
  @assert expr.head ∈ (:(=), :function)  "@cont works only with functions"
  signature = expr.args[1]
  @assert isa(signature, Expr) && signature.head == :call "we need called function syntax"

  functioncall = Expr(:call, signature.args[1], extract_symbol.(signature.args[2:end])...)
  newfunc = if functioncall.args[2] == :cont
    newsignature = Expr(signature.head, signature.args[1], signature.args[3:end]...)
    Expr(:(=), newsignature, :(cont -> $functioncall))
  else
    newsignature = Expr(:call, signature.args[1], :cont, signature.args[2:end]...)
    Expr(:(=), newsignature, :($functioncall(cont)))
  end

  # we need to mark one expression as the target for documentation, otherwise every doc string will throw an error
  esc(quote
    @Base.__doc__ $expr
    $newfunc
  end)
end

const StoredIterable = Union{Tuple, AbstractArray}

@cont function crange(cont, first, step, last)
  for i in first:step:last
    cont(i)
  end
end
crange(last) = crange(1, 1, last)
crange(cont::Function, last) = crange(cont, 1, 1, last)
crange(first, last) = crange(first, 1, last)
crange(cont::Function, first, last) = crange(cont, first, 1, last)

ccollect(continuable) = creduce!(push!, [], continuable)
import Base.collect
collect(continuable::Function) = ccollect(continuable)

@Ref function ccollect(continuable, n)
  a = Vector(n)
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

@cont function ascontinuable(cont, iterable)
  for i in iterable
    cont(i)
  end
end


macro c2a(expr)
  esc(:(ccollect($expr)))
end

macro c2t(expr)
  esc(:(astask($expr)))
end

macro i2c(expr)
  esc(:(ascontinuable($expr)))
end


struct StopException{T} <: Exception
  ret::T
end
Stop = StopException(nothing)
stop() = throw(Stop)
stop(ret) = throw(StopException(ret))

stoppable(continuable) = cont -> begin
  try
    continuable(cont)
  catch exc
    if !isa(exc, StopException)
      rethrow(exc)
    end
    return exc.ret
  end
end
stoppable(cont, continuable) = stoppable(continuable)(cont)


@cont cconst(cont, value) = cont(value)

## core functional helpers ----------------------------------------------------------
@cont @Ref function cenumerate(cont, continuable)
  i = Ref(1)
  continuable() do x
    cont((i, x))
    i += 1
  end
end

@cont function cmap(cont, func, continuable)
  continuable(x -> cont(func(x)))
end

@cont function cfilter(cont, bool, continuable)
  continuable() do x
    if bool(x)
      cont(x)
    end
  end
end

@Ref function creduce(op, v0, continuable)
  acc = Ref(v0)
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
  acc = Ref(cproduct(c1, c2))  # make first into singleton tuple to start recursion
  for continuable in cs
    acc = _product(acc, continuable)
  end
  acc
end

cproduct_do(cont, cs...) = cproduct(cs...)(cont)


chain(cs::Function...) = cont -> begin
  for continuable in cs
    continuable(cont)
  end
end
chain_do(cont, cs...) = chain(cs...)(cont)


@cont function ccycle(cont, continuable)
  while true
    continuable(cont)
  end
end

@cont function ccycle(cont, continuable, n::Integer)
  for _ in 1:n
    continuable(cont)
  end
end


# --------------------------

# generic cmap? only with zip and this is not efficient unfortunately
@cont @Ref function ctake(cont, continuable, n::Integer)
  i = Ref(0)
  stoppable(continuable) do x
    i += 1
    if i > n
      stop()
    end
    cont(x)
  end
end

@cont function ctakewhile(cont, continuable, bool)
  stoppable(continuable) do x
    if !bool(x)
      stop()
    end
    cont(x)
  end
end

@cont @Ref function cdrop(cont, continuable, n::Integer)
  i = Ref(0)
  continuable() do x
    i += 1
    if i >= n
      cont(x)
    end
  end
end

@cont @Ref function cdropwhile(cont, continuable, bool)
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

@cont function cflatten(cont, iterable)
  for continuable in iterable
    continuable(cont)
  end
end

@cont function cflatten(cont, continuable::Function)
  continuable() do subcontinuable
    subcontinuable(cont)
  end
end

@cont @Ref function cpartition(cont, continuable, n::Integer)
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

@cont @Ref function cpartition(cont, continuable, n::Integer, step::Integer)
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
cgroupby(f, continuable) = cgroupbyreduce(f, continuable, push!, x -> [x])


# subsets seem to be implemented for arrays in the first place (and not iterables in general)
# hence better use Iterators.subsets directly

# peekiter is the only method if Iterators.jl missing. However it in fact makes no sense for continuables
# as they are functions and don't get consumed

## extract values from continuables  ----------------------------------------


@Ref function cnth(continuable::Function, n)
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

@Ref function ccount(continuable)
  i = Ref(0)
  continuable() do _
    i += 1
  end
  i
end


## create continuables ----------------------------

@cont function crepeatedly(cont, f)
  while true
    cont(f())
  end
end

@cont function crepeatedly(cont, f, n::Integer)
  for _ in 1:n
    cont(f())
  end
end

@cont @Ref function citerate(cont, f, x)
  a = Ref(x)
  while true
    a = f(a)
    cont(a)
  end
end

end  # module
