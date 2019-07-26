
# @Ref
# ====

# we use Julia's default Ref type for single variable references

function refify!(expr::Expr, Refs::Vector{Symbol}=Vector{Symbol}())
  expr.head == :. && return  # short cycle if we have a dot access expression, as we don't want to change in there

  # important to use Base.enumerate as plain enumerate would bring Base.enumerate into namespace, however we want to create an own const link
  for (i, a) in Base.enumerate(expr.args)
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




# @cont
# =====


function extract_symbol(a)
  if isa(a, Symbol)
    a
  elseif isa(a.args[1], Symbol) # something like Type annotation a::Any or Defaultvalue b = 3
    a.args[1]
  else # Type annotation with Defaultvalue
    a.args[1].args[1]
  end
end

is_functionexpr(_) = false
function is_functionexpr(expr::Expr)
  ((expr.head == :function 
      && expr.args[1] isa Expr
      && expr.args[1].head in (:tuple, :call))   
  || (expr.head == :(=) 
    && expr.args[1] isa Expr
    && expr.args[1].head == :call))
end

mutable struct ParsedFunctionExpr
  name::Union{Symbol, Nothing}  # we don't put this into a struct parameter because we want to easily mutate a parsedfunctionexpr to become anonymous
  args::Vector{Union{Symbol, Expr}}
  body::Expr

  function ParsedFunctionExpr(expr::Expr)
    @assert expr.head in (:function, :(=))
    call::Expr = expr.args[1]
    @assert length(expr.args) == 2
    body = expr.args[2]
    isanonymous = call.head == :tuple
    name, args = if isanonymous
      nothing, call.args
    else
      call.args[1], call.args[2:end]
    end
    new(name, args, body)
  end
end
function Base.convert(::Type{Expr}, pfe::ParsedFunctionExpr)
  if isnothing(pfe.name)
    quote
      function ($(pfe.args...),)
        $(pfe.body)
      end
    end
  else
    quote
      function $(pfe.name)($(pfe.args...),)
        $(pfe.body)
      end
    end
  end
end

macro assert_noerror(expr, msg)
  esc(quote
    try
      $expr
    catch
      error(msg)
    end
  end)
end

macro cont(expr)
  expr = macroexpand(__module__, expr)  # get rid of maybe confusing macros
  esc(cont_expr(expr))
end
macro cont(elemtype, expr)
  expr = macroexpand(__module__, expr)  # get rid of maybe confusing macros
  esc(cont_expr(expr, elemtype = elemtype))
end
macro cont(elemtype, length, expr)
  expr = macroexpand(__module__, expr)  # get rid of maybe confusing macros
  if length isa Expr && length.head == :tuple  # support for tuple sizes as second argument
    esc(cont_expr(expr, elemtype = elemtype, size = length))
  else  
    esc(cont_expr(expr, elemtype = elemtype, length = length))
  end
end
macro cont(elemtype, length, size, expr)
  expr = macroexpand(__module__, expr)  # get rid of maybe confusing macros
  esc(cont_expr(expr, elemtype = elemtype, length = length, size = size))
end

function cont_expr(expr::Expr; elemtype=Any, length=nothing, size=nothing)
  if is_functionexpr(expr)
    cont_funcexpr(expr; elemtype = elemtype, length = length, size = size)
  else
    quote
      Continuables.Continuable(cont -> $expr)
    end
  end
end


function cont_funcexpr(expr::Expr; elemtype=Any, length=nothing, size=nothing)
  func = ParsedFunctionExpr(expr)
  @assert all(func.args) do s
    extract_symbol(s) != :cont
  end "No function parameter can be called ``cont`` for @cont to apply."
  
  # return Continuable instead
  func.body = :(Continuables.Continuable{$elemtype}(cont -> $(func.body); length=$length, size=$size))

  # make Expr
  convert(Expr, func)
end