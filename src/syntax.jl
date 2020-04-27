using ExprParsers
using SimpleMatch

# @Ref
# ====

# TODO also replace ``::Ref`` annotations. Currently only ``r = Ref(2)`` assignments are replaced.

const _parser = EP.AnyOf(EP.NestedDot(), EP.Function())

# entrypoint - start with empty list of substitutions
refify!(expr::Expr) = refify!(expr, Vector{Symbol}())

# map Expr to Parsers
refify!(any, ::Vector{Symbol}) = ()  # if there is no expression (or Vector, see below), we cannot refify anything
refify!(expr::Expr, Refs::Vector{Symbol}) = refify!(expr, Refs, @TryCatch ParseError parse_expr(_parser, expr))


# if specific parser was detected, then dispatch directly on Parsed result
refify!(expr::Expr, Refs::Vector{Symbol}, parsed::Success{P}) where P = refify!(expr, Refs, parsed.value)

# Specific Parsers
function refify!(expr::Expr, Refs::Vector{Symbol}, nesteddot_parsed::EP.NestedDot_Parsed)
  # refify only most left dot expression ``nesteddot_parsed.base``, i.e. the object which is originally accessed
  @match(nesteddot_parsed.base) do f
    # if `nesteddot_parsed.base` is a Symbol, we cannot do in-place replacement with refify! but can only changed the parsed result
    f(_) = nothing
    f(s::Symbol) = nesteddot_parsed.base = refify_symbol(s, Refs)
    f(e::Expr) = refify!(e, Refs)
  end

  # as not everything could be replaced inplace, we still have to inplace-replace the whole parsed expression
  newexpr = to_expr(nesteddot_parsed)
  expr.head = newexpr.head
  expr.args = newexpr.args
end

function refify!(expr::Expr, Refs::Vector{Symbol}, function_parsed::EP.Function_Parsed)
  # when going into a function, we need to ignore the function parameter names from Refs as they are new variables, not related to the Refs
  args = [parse_expr(EP.Arg(), arg) for arg in function_parsed.args]
  kwargs = [parse_expr(EP.Arg(), kwarg) for kwarg in function_parsed.kwargs]

  # recurse into any default arguments
  for arg in [args; kwargs]
    @match(arg.default) do f
      f(_) = nothing
      # in case of Symbol we can only change the parsed result in place, but not the original expression
      f(s::Symbol) = arg.default = refify_symbol(s, Refs)
      f(e::Expr) = refify!(e, Refs)
    end
  end

  # recurse into body with function arguments not being refified
  args_names = [arg.name for arg in args if arg.name != nothing]
  kwargs_names = [kwarg.name for kwarg in kwargs if kwarg.name != nothing]
  # CAUTION: we need to use Base.filter so that we can still overwrite filter in the module
  Refs::Vector{Symbol} = Base.filter(ref -> ref ∉ args_names && ref ∉ kwargs_names, Refs)
  refify!(function_parsed.body, Refs)

  # some parts might not have been replaced-inplace in the original expression
  # hence we have to replace the whole expression
  function_parsed.args = args
  function_parsed.kwargs = kwargs
  newexpr = to_expr(function_parsed)
  expr.head = newexpr.head
  expr.args = newexpr.args
end


# if no parser was successful, recurse into expr.args

# core logic, capture each new Ref, substitute each old one
# this has to be done on expr.args level, as Refs on the same level need to be available for replacement
# Additionally, this has to be done on expr.args level because Symbols can only be replaced inplace on the surrounding Vector
function refify!(expr::Expr, Refs::Vector{Symbol}, ::Failure{<:Any})
  # important to use Base.enumerate as plain enumerate would bring Base.enumerate into namespace, however we want to create an own const link
  for (i, a) in Base.enumerate(expr.args)
    Ref_assignment_parser = EP.Assignment(
      left = EP.anysymbol,
      right = EP.Call(
        name = :Ref,
      ),
    )
    parsed = @TryCatch ParseError parse_expr(Ref_assignment_parser, a)
    if issuccess(parsed)
      # create new Refs to properly handle subexpressions with Refs (so that no sideeffects occur)
      Refs = Symbol[Refs; parsed.value.left]
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

function refify_symbol(sym::Symbol, Refs::Vector{Symbol})
  for r in Refs
    if sym == r
      return :($sym.x)
    end
  end
  # default to identity
  sym
end

macro Ref(expr)
  refify!(expr)
  esc(expr)
end




# @cont
# =====


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
  if issuccess(@TryCatch ParseError parse_expr(EP.Function(), expr))
    cont_funcexpr(expr; elemtype = elemtype, length = length, size = size)
  else
    quote
      Continuables.Continuable(cont -> $expr)
    end
  end
end

function _extract_symbol(a)
  if isa(a, Symbol)
    a
  elseif isa(a.args[1], Symbol) # something like Type annotation a::Any or Defaultvalue b = 3
    a.args[1]
  else # Type annotation with Defaultvalue
    a.args[1].args[1]
  end
end

function cont_funcexpr(expr::Expr; elemtype=Any, length=nothing, size=nothing)
  func_parsed = parse_expr(EP.Function(), expr)
  @assert Base.all(func_parsed.args) do s
    _extract_symbol(s) != :cont
  end "No function parameter can be called ``cont`` for @cont to apply."

  # return Continuable instead
  func_parsed.body = :(Continuables.Continuable{$elemtype}(cont -> $(func_parsed.body); length=$length, size=$size))

  # make Expr
  to_expr(func_parsed)
end
