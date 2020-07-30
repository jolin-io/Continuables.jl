using Continuables
using Test

@testset "utils" begin
  include("utils.jl")
end


# check that @Ref is working correctly
# ====================================

@testset "Ref" begin
  expr1_simple = @macroexpand @Ref begin
    a = Ref(1)
    f(a) = 2 * a
    a + f(a)
  end
  expr2_simple = quote
    a = Ref(1)
    f(a) = 2 * a
    a.x + f(a.x)
  end
  @test same_expr(expr1_simple, expr2_simple)

  # difficult case to parse:
  expr1_complex = @macroexpand @Ref begin
    a = Ref(Some(1))
    b = Ref("hi")
    f(a::Int = b; c = b, d = 4) = 2 * a
    a.value + f(a.value)
  end
  expr2_complex = quote
    a = Ref(Some(1))
    b = Ref("hi")
    f(a::Int = b.x; c = b.x, d = 4) = 2 * a
    a.x.value + f(a.x.value)
  end
  @test same_expr(expr1_complex, expr2_complex)
end


# Check Continuables standard Interface
# =====================================
@testset "standard interface" begin
  @test_throws ErrorException cont(1)

  cont1 = @cont cont(1)
  @test collect(cont1) == [1]
  @test collect(singleton(3)) == [3]

  @test collect(@i2c 2:4:10) == collect(2:4:10)
  @test collect(map(x->x^2, @i2c 2:4:10)) == collect(map(x->x^2, 2:4:10))
  @test collect(take(cycle(@i2c 1:3), 11)) == collect(take(cycle(1:3), 11))
  @test collect(take(cycle(@i2c 1:3), 11)) == collect(take(cycle(1:3), 11))
  @test collect(drop(@i2c(1:10), 3)) == collect(drop(1:10, 3))
  @test collect(repeated(() -> 4, 3)) == collect(take(repeated(() -> 4), 3))
  @test nth(@i2c(0:10), 8) == (0:10)[8]

  @test Base.IteratorSize(@i2c 1:4) == Base.SizeUnknown()
  @test length(@i2c 3:20) == 18

  @test collect(product(@i2c(1:10), @i2c(1:3))) == [(i,j) for i in 1:10 for j in 1:3]
  @test collect(product(1:10, 1:3)) == [(i,j) for i in 1:10, j in 1:3]
  # however they both are not easily comparable... because transpose does not work on arrays of tuples right now...

  @test collect(partition(@i2c(1:15), 4)) == collect(partition(1:15, 4))
  @test collect(partition(@i2c(1:20), 3, 5)) == [
    Any[1, 2, 3],
    Any[6, 7, 8],
    Any[11, 12, 13],
    Any[16, 17, 18],
  ]  # there exists no version for iterables as of writing this

  @test collect(zip(@i2c(1:10), @i2c(4:8))) == collect(zip(1:10, 4:8))
  @test collect(zip(@i2c(1:10), @i2c(4:8), lazy = false)) == collect(zip(1:10, 4:8))


  @test any(x -> x == 4, @i2c 1:10) == any(x -> x == 4, 1:10)
  @test any(x -> x == 4, @i2c 1:3) == any(x -> x == 4, 1:3)

  @test all(x -> x <= 4, @i2c 1:10) == all(x -> x <= 4, 1:10)
  @test all(x -> x <= 4, @i2c 1:3) == all(x -> x <= 4, 1:3)


  @test reduce((acc, x) -> acc + x*x, @i2c 1:10) == reduce((acc, x) -> acc + x*x, 1:10)
  @test reduce((acc, x) -> acc + x*x, @i2c 1:10) == reduce((acc, x) -> acc + x*x, 1:10)
  @test reduce!(push!, @i2c(1:10), init = []) == collect(1:10)


  @test collect(chain(@i2c(1:10), @i2c(3:5))) == collect(chain(1:10, 3:5))
  contcont = @cont begin
    for i in 1:10
      cont(@i2c i:10)
    end
  end
  @test collect(flatten(contcont)) == collect(flatten(i:10 for i in 1:10))


  @test collect(takewhile(x -> x <= 4, @i2c 1:10)) == collect(takewhile(x -> x <= 4, 1:10))
  @test collect(dropwhile(x -> x <= 4, @i2c 1:10)) == collect(dropwhile(x -> x <= 4, 1:10))


  @test groupby(x -> x % 4, @i2c 1:10) == groupby(x -> x % 4, 1:10)
  @test groupbyreduce(x -> x % 4, @i2c(1:10), (x, y) -> x + y, x -> x+5) == groupbyreduce(x -> x % 4, 1:10, (x, y) -> x + y, x -> x+5)
end
