# to be a drop in replacement we need to support iterables
struct TakeWhile{Func, Iter}
  f::Func
  iter::Iter
end

function Base.iterate(tw::TakeWhile)
  (nextval, nextstate) = @ifsomething Base.iterate(tw.iter)
  tw.f(nextval) ? (nextval, nextstate) : nothing 
end
function Base.iterate(tw::TakeWhile, state)
  (nextval, nextstate) = @ifsomething Base.iterate(tw.iter, state)
  tw.f(nextval) ? (nextval, nextstate) : nothing
end






# to be a drop in replacement we need to support iterables
struct DropWhile{Func, Iter}
  f::Func
  iter::Iter
end
function Base.iterate(dw::DropWhile)
  (nextval, nextstate) = @ifsomething Base.iterate(dw.iter)
  while dw.f(nextval)
    (nextval, nextstate) = @ifsomething Base.iterate(dw.iter, nextstate)
  end
  (nextval, nextstate)
end
Base.iterate(dw::DropWhile, state) = Base.iterate(dw.iter, state)


# IteratorEltype and IteratorSize can be defined for both simultanuously 

const DropWhile_or_TakeWhile{F, Iter} = Union{DropWhile{F, Iter}, TakeWhile{F, Iter}}
const TypeDropWhile_or_TypeTakeWhile{F, Iter} = Union{Type{DropWhile{F, Iter}}, Type{TakeWhile{F, Iter}}}

Base.IteratorEltype(::TypeDropWhile_or_TypeTakeWhile{F, Iter}) where {F, Iter} = Base.IteratorEltype(Iter)
Base.eltype(::TypeDropWhile_or_TypeTakeWhile{F, Iter}) where {F, Iter} = Base.eltype(Iter)

# defaulting to Base.SizeUnknown
function Base.IteratorSize(::TypeDropWhile_or_TypeTakeWhile{Func, Iter}) where {Func, Iter}
  itersize = Base.IteratorSize(Iter)
  if itersize isa Union{Base.HasShape, Base.SizeUnknown, Base.HasLength} where N
    Base.SizeUnknown()
  elseif itersize isa Base.IsInfinite
    itersize
  else
    error("should never happen")
  end
end

function Base.length(tw::DropWhile_or_TakeWhile)
  s::Int = 0
  for x in tw
    s += 1
  end
  s
end

function Base.collect(tw::DropWhile_or_TakeWhile)
  everything = []
  for x in tw
    push!(everything, x)
  end
  everything
end