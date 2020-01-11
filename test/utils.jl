
# zip of uneven iterators is still not supported in julia... super weird
# see https://discourse.julialang.org/t/collecting-zip/20739
# and https://github.com/JuliaLang/julia/issues/17928
function Base.collect(itr::Base.Iterators.Zip)
  itrsize = Base.IteratorSize(itr)
  itrsize isa Base.HasShape && (itrsize = Base.HasLength())
  Base._collect(1:1, itr, Base.IteratorEltype(itr), itrsize)
end


"""
only continue if true, else return false immediately
"""
macro iftrue(expr)
  quote
    $(esc(expr)) || return false
  end
end


same_expr(e1, e2) = e1 == e2
function same_expr(e1::Expr, e2::Expr)
  # don't differentiate between ``f(a) = a`` and ``function f(a); a; end``
  e1.head == :function && (e1.head = :(=))
  e2.head == :function && (e2.head = :(=))
  @iftrue e1.head == e2.head

  args1 = filter(x -> !isa(x, LineNumberNode), e1.args)
  args2 = filter(x -> !isa(x, LineNumberNode), e2.args)
  @iftrue length(args1) == length(args2)
  # recurse
  all(zip(args1, args2)) do (a, b)
    same_expr(a, b)
  end
end

@test same_expr(:a, :a)
@test same_expr(:(a = 4), :(a = 4))
@test same_expr(quote
  f(a) = a
end, quote
  function f(a)
    a
  end
end)
@test !same_expr(:a, :b)
@test !same_expr(:(a = 4), :(a = 5))
@test !same_expr(quote
  f(a) = a
end, quote
  f(b) = b
end)
