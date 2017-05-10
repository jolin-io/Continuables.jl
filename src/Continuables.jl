module Continuables
export
  crange, ccollect, @c2a, astask, @c2t, ascontinuable, @i2c, stoppable, stop,
  cconst, cmap, cfilter, creduce, mzip, tzip, cproduct, chain, ccycle,
  ctake, ctakewhile, cdrop, cdropwhile, cflatten, cpartition, cgroupbyreduce,
  cgroupby, cnth, ccount, crepeatedly, citerate, Ref, @Ref

## Core functions --------------------------------------------------

# we use Julia's default Ref type for single variable references

function refify!(expr::Expr, Refs::Vector{Symbol}=Vector{Symbol}())
  for (i, a) in enumerate(expr.args)
    if (isa(a, Expr) && a.head == :(=) && isa(a.args[1], Symbol)
        && isa(a.args[2], Expr) && a.args[2].args[1] == :Ref && a.args[2].head == :call)
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
collect(continuable::Function)) = ccollect(continuable)

macro c2a(expr)
  :(ccollect($expr))
end

astask(continuable) = @task continuable(produce)
macro c2t(expr)
  :(astask($expr))
end

ascontinuable(iterable) = cont -> begin
  for i in iterable
    cont(i)
  end
end
macro i2c(expr)
  :(ascontinuable($expr))
end


type StopException{T} <: Exception
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


cconst(value) = cont -> cont(value)

## core functional helpers ----------------------------------------------------------
cenumerate(continuable) = cont -> @Ref begin
  i = Ref(1)
  continuable() do x
    cont((i, x))
    i += 1
  end
end

cmap(func, continuable) = cont -> begin
  continuable(x -> cont(func(x)))
end

cmap(cont, func, continuable) = cmap(func, continuable)(cont)

cfilter(bool, continuable) = cont -> begin
  continuable() do x
    if bool(x)
      cont(x)
    end
  end
end

cfilter(cont, bool, continuable) = cfilter(bool, continuable)(cont)

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

cproduct(cont::Function, cs::StoredIterable) = cproduct(cs...)(cont)


chain(cs::Function...) = cont -> begin
  for continuable in cs
    continuable(cont)
  end
end
chain(cont::Function, cs::StoredIterable) = chain(cs...)(cont)


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

# generic cmap? only with zip and this is not efficient unfortunately
ctake(continuable::Function, n::Integer) = cont -> @Ref begin
  i = Ref(0)
  stoppable(continuable) do x
    i += 1
    if i > n
      stop()
    end
    cont(x)
  end
end
ctake(cont::Function, continuable::Function, n::Integer) = ctake(continuable, n)(cont)

ctakewhile(continuable::Function, bool::Function) = cont -> begin
  stoppable(continuable) do x
    if !bool(x)
      stop()
    end
    cont(x)
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


cflatten(continuable::Function) = cont -> begin
  continuable() do subcontinuable
    subcontinuable(cont)
  end
end
cflatten(cont, continuable::Function) = cflatten(continuable)(cont)


cpartition(continuable, n::Integer) = cont -> @Ref begin
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
cpartition(cont, continuable, n::Integer) = cpartition(continuable, n)(cont)


cpartition(continuable, n::Integer, step::Integer) = cont -> @Ref begin
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

cpartition(cont, continuable, n::Integer, step::Integer) = cpartition(continuable, n, step)(cont)

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

@Ref citerate(f::Function, x) = cont -> begin
  a = Ref(x)
  while true
    a = f(a)
    cont(a)
  end
end
citerate(cont::Function, f::Function, x) = citerate(f, x)(cont)

end  # module