## Tests
using Continuables

ccollect(crange(2,4,10))

ccollect(cmap(x->x^2, crange(2,4,10)))

test = cmap(crange(10)) do x
  x^2
end
ccollect(test)

ccollect(ctake(ccycle(crange(3)), 11))

cnth(crange(0, 10), 8)
(0:10)[8]


ccount(crange(3, 20))

ccollect(product(crange(10), crange(3)))

ccollect(cpartition(crange(15), 4))

ccollect(cpartition(crange(20), 3, 5))







naturalnumbers(start=1, step=1) = cont -> begin
  i = start
  while true
    cont(i)
    i += step
  end
end
naturalnumbers(cont::Function, start=1, step=1) = naturalnumbers(start, step)(cont)



for i in range(10)
  println(i)
end

function f()
  a = 22

  g(i) = begin
    println(a)
    a += i
  end
  ctake(g, naturalnumbers(), 10)


  ctake(naturalnumbers(), 10) do i
    println(a)
    a += i
  end
end

f()




@macroexpand @Ref begin
  a = Ref(1)
  b = 4
  c = Ref(4)
  for i in 1:c
    a += 1
  end
  a + b + c
end


import BenchmarkTools.@benchmark


crange(n::Int) = cont -> begin
  for i in 1:n
    cont(i)
  end
end

crange(cont, n::Int) = crange(n)(cont)

function trange(n::Int)
  c = Channel{Int}(1)
  task = @async for i ∈ 1:n
    put!(c, i)
  end
  bind(c, task)
end



@Ref function sum_continuable(continuable)
  a = Ref(0)
  continuable() do i
    a += i
  end
  a
end

function sum_continuable_withoutref(continuable)
  a = 0
  continuable() do i
    a += i
  end
  a
end

function sum_iterable(it)
  a = 0
  for i in it
    a += i
  end
  a
end

function collect_continuable(continuable)
  a = []
  continuable() do i
    push!(a, i)
  end
  a
end

function collect_iterable(it)
  a = []
  for i in it
    push!(a, i)
  end
  a
end

@benchmark sum_continuable(crange(1000))
@benchmark sum_continuable_withoutref(crange(1000))
@benchmark sum_iterable(@task trange(1000))
@benchmark sum_iterable(1:1000)

@benchmark collect_continuable(crange(1000))
@benchmark collect_iterable(1:1000)
@benchmark collect_iterable(trange(1000))
