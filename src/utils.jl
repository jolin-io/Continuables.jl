# We realise early stopping via exceptions

struct StopException{T} <: Exception
  ret::T
end
Stop = StopException(nothing)
stop() = throw(Stop)
stop(ret) = throw(StopException(ret))

"""
  contextmanager handling custom breakpoints with `stop()`

This is usually only used within creating a new continuable from a previous one

# Examples
```julia
@cont stop_at4(continuable) = stoppable(continuable) do x
  x == 4 && stop()
  cont(x)
end
```
"""
function stoppable(func, continuable, default_return = nothing)
  try
    continuable(func)
    default_return  # default returnvalue to be able to handle `stop(returnvalue)` savely
  catch exc
    if !isa(exc, StopException)
      rethrow(exc)
    end
    exc.ret
  end
end




"""
    Continuables.@ifsomething expr
If `expr` evaluates to `nothing`, equivalent to `return nothing`, otherwise the macro
evaluates to the value of `expr`. Not exported, useful for implementing iterators.

# Example

```jldoctest
julia> using Continuables
julia> Continuables.@ifsomething iterate(1:2)
(1, 1)
julia> let elt, state = Continuables.@ifsomething iterate(1:2, 2); println("not reached"); end
```
"""
macro ifsomething(ex)
    quote
        result = $(esc(ex))
        result === nothing && return nothing
        result
    end
end
