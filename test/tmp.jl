

# we use Julia's default Ref type for single variable references

function refify!(expr::Expr, Refs::Vector{Symbol}=Vector{Symbol}())
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


expr = :(a = Ref(1); a = 4)

Continuables.refify!(expr)

expr
refify!(expr)
