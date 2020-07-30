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


@testset "specializing functions for Continuable" begin
  mycont(x) = @cont cont(x)
  Base.length(::Continuable{<:innerfunctype(mycont(:examplesignature))}) = :justatest
  @test length(mycont(1)) == :justatest
  @test length(mycont("a")) == :justatest
  # other continuables are not affected
  anothercont(x) = @cont cont(x)
  @test length(anothercont(42)) == 1
end

@testset "constructing Continuables" begin

  cont1 = @cont cont(1)
  @test collect(cont1) == [1]
  @test collect(singleton(3)) == [3]

  @test collect(take(repeated(() -> 4), 3)) == [4, 4, 4]
  @test collect(repeated(() -> 4, 3)) == [4, 4, 4]

  @test collect(take(3, iterated(x -> x*x, 2))) == [2, 4, 16]
end

@testset "DropWhile TakeWhile iterables" begin
  @test length(dropwhile(x -> x<4, 1:10)) == 7
  @test Base.IteratorSize(typeof(dropwhile(x -> x<4, 1:10))) == Base.SizeUnknown()

  @test eltype(dropwhile(x -> x<4, 1:10)) == Int
  @test Base.IteratorEltype(typeof(dropwhile(x -> x<4, 1:10))) == Base.HasEltype()

  @test length(takewhile(x -> x<4, 1:10)) == 3
  @test Base.IteratorSize(typeof(takewhile(x -> x<4, 1:10))) == Base.SizeUnknown()

  @test eltype(takewhile(x -> x<4, 1:10)) == Int
  @test Base.IteratorEltype(typeof(takewhile(x -> x<4, 1:10))) == Base.HasEltype()
end

# Check Continuables standard Interface
# =====================================


@testset "standard interface" begin
  @test_throws ErrorException cont(1)

  @test collect(@i2c 2:4:10) == collect(2:4:10)
  @test collect(i2c(2:4:10), length(2:4:10)) == collect(2:4:10)

  @test collect(enumerate(@i2c 2:4:10)) == collect(enumerate(2:4:10))
  @test collect(filter(x -> x < 7, @i2c 2:4:10)) == collect(filter(x -> x < 7, 2:4:10))

  @test collect(map(x->x^2, @i2c 2:4:10)) == collect(map(x->x^2, 2:4:10))
  @test collect(take(cycle(@i2c 1:3), 11)) == collect(take(cycle(1:3), 11))
  @test collect(take(cycle(@i2c 1:3), 11)) == collect(take(cycle(1:3), 11))
  @test collect(cycle(i2c(1:3), 3)) == [1,2,3, 1,2,3, 1,2,3]

  @test collect(drop(i2c(1:10), 3)) == collect(drop(1:10, 3))

  @test nth(i2c(0:10), 8) == (0:10)[8]
  @test_throws ErrorException nth(12, i2c(0:10))

  @test Base.IteratorSize(@i2c 1:4) == Base.SizeUnknown()
  @test length(@i2c 3:20) == 18

  @test Base.IteratorEltype(emptycontinuable) == Base.EltypeUnknown()
  @test Base.eltype(@i2c 1:4) == Any


  test_continuable_product = @i2c 1:10
  @test product(test_continuable_product) === test_continuable_product  # should be a no-op
  @test collect(product(i2c(1:10), i2c(1:3))) == [(i,j) for i in 1:10 for j in 1:3]
  @test collect(product(i2c(1:10), i2c(1:3), i2c(2:4))) == [(i,j,k) for i in 1:10 for j in 1:3 for k in 2:4]

  # however they both are not easily comparable... because transpose does not work on arrays of tuples right now...

  @test collect(partition(i2c(1:15), 4)) == collect(partition(1:15, 4))
  @test collect(partition(i2c(1:20), 3, 5)) == [
    Any[1, 2, 3],
    Any[6, 7, 8],
    Any[11, 12, 13],
    Any[16, 17, 18],
  ]
  @test collect(partition(i2c(1:10), 5, 2)) == Any[
    Any[1, 2, 3, 4, 5],
    Any[3, 4, 5, 6, 7],
    Any[5, 6, 7, 8, 9],
  ]

  @test collect(zip(i2c(1:10), i2c(4:13))) == collect(zip(1:10, 4:13))
  @test collect(zip(i2c(1:10), i2c(4:13), lazy = false)) == collect(zip(1:10, 4:13))


  @test any(x -> x == 4, @i2c 1:10) == any(x -> x == 4, 1:10)
  @test any(x -> x == 4, i2c(1:10), lazy=false) == any(x -> x == 4, 1:10)
  @test any(x -> x == 4, i2c(1:3)) == any(x -> x == 4, 1:3)
  @test any(x -> x == 4, i2c(1:3), lazy=false) == any(x -> x == 4, 1:3)

  @test all(x -> x <= 4, i2c(1:10)) == all(x -> x <= 4, 1:10)
  @test all(x -> x <= 4, i2c(1:10), lazy=false) == all(x -> x <= 4, 1:10)
  @test all(x -> x <= 4, i2c(1:3)) == all(x -> x <= 4, 1:3)
  @test all(x -> x <= 4, i2c(1:3), lazy=false) == all(x -> x <= 4, 1:3)


  @test reduce((acc, x) -> acc + x*x, @i2c 1:10) == reduce((acc, x) -> acc + x*x, 1:10)
  @test foldl((acc, x) -> acc + x*x, @i2c 1:10) == foldl((acc, x) -> acc + x*x, 1:10)
  @test reduce((acc, x) -> acc + x*x, i2c(1:10), init = 100) == reduce((acc, x) -> acc + x*x, 1:10, init = 100)
  @test reduce!(push!, i2c(1:10), init = []) == collect(1:10)

  @test sum(@i2c 1:10) == sum(1:10)
  @test prod(@i2c 1:10) == prod(1:10)


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
