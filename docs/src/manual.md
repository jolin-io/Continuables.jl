# Manual

TLDR: Python / C# `yield` with performance matching plain Julia iterators  (i.e. unbelievably fast)

Continuables are generator-like higher-order functions which take a continuation as an extra argument. The key macro provided by the package is `@cont` which will give access to the special function `cont` within its scope and wraps the computation in a special Type `Continuables.Continuable`.
It is best to think of `cont` in the sense of `yield` from Python's Generators. It generates values and takes feedback from the outer process as return value.

If you come from Python, use Continuables wherever you would use generators. If you are Julia-native, Continuables can be used instead of Julia's Channels in many place with drastic performance-improvements (really drastic: in the little benchmark example below it is 20 million times faster!).

This package implements all standard functions like e.g. `collect`, `reduce`, `any` and others. As well as functionalities known from `Base.Iterators` and [`IterTools.jl`](https://github.com/JuliaCollections/IterTools.jl) like `take`, `dropwhile`, `groupby`, `partition`, `nth` and others.



## Example of a Continuable

Let's define our fist continuable by wrapping a simple range iterator `1:n`.

```julia
using Continuables
# new Continuable ---------------------------------------------
corange(n::Integer) = @cont begin
  for i in 1:n
    cont(i)
  end
end
```

That's it. Very straight forward and intuitive.

Many standard functions work seamlessly for Continuables.

```julia
using Continuables
collect(corange(10)) == collect(1:10)

co2 = map(corange(5)) do x
  2x
end
collect(co2) == [2,4,6,8,10]

foreach(println, corange(3))  # 1, 2, 3

foreach(chain(corange(2), corange(4))) do x
  print("$x, ")
end # 1, 2, 1, 2, 3, 4,  

reduce(*, corange(4)) == 24

all(x -> x < 5, corange(3))
any(x -> x == 2, corange(3))

map(corange(10)) do x
  corange(x)
end |> flatten |> co -> take(co, 5) |> collect == Any[1,1,2,1,2]

collect(product(corange(2), corange(3))) == Any[
  (1, 1),
  (1, 2),
  (1, 3),
  (2, 1),
  (2, 2),
  (2, 3),
]
collect(partition(corange(11), 4)) == [
  Any[1,2,3,4],
  Any[5,6,7,8],
  Any[9,10,11],
]
using OrderedCollections
groupbyreduce(isodd, corange(5), +) == OrderedDict{Any, Any}(
  true => 9,
  false => 6,
)

nth(3, ascontinuable(4:10)) == 6
nth(4, i2c(4:10)) == 7
nth(5, @i2c 4:10) == 8

# further defined are `takewhile`, `drop`, `dropwhile`, `repeated` and `iterate`, as well as `groupby`.
```

Importantly, Continuables do not support `Base.iterate`, i.e. you cannot directly for-loop over a Continuable. There is just no direct way to implement `iterate` on top of Continuables. Give it a try. Instead, you have to convert it into an Array first using `collect`, or to a Channel using `aschannel`.

The same holds true for `zip`, however we provide a convenience implementation where you can choose which interpretation you want to have
```julia
# uses Channels and hence offers lazy execution, however might be slower
zip(i2c(1:4), i2c(3:6), lazy=true)  # Default

# uses Array, might be faster, but loads everything into memory  
zip(i2c(1:4), i2c(3:6), lazy=false)
```

Last but not least, you can call a Continuable directly. It is just a higher order function expecting a `cont` function to run its computation.

```julia
continuable = corange(3)
foreach(print, continuable)  # 123
# is the very same as
continuable(print)  # 123
```

## The `@Ref` macro

As you already saw, for continuables we cannot use for-loops. Instead we use higher-order functions like `map`, `foreach`, `reduce` or `groupbyreduce` to work with Continuables.  
Fortunately, julia supports beautiful `do` syntax for higher-order functions. In fact, `do` becomes the equivalent of `for` for continuables.

However, importantly, a `do`-block constructs an anonymous function and consequently what happens within the do-block has its own variable namespace! This is essential if you want to define your own Continuables. You cannot easily change an outer variable from within a do-block like you may have done it within a for-loop. The solution is to simply use julia's `Ref` object to get mutations instead of simple variable assignments. For example instead of `var_changing_every_loop = 0`, and an update `var_changing_every_loop += 1` you use `var_changing_every_loop = Ref(yourvalue)` and `var_changing_every_loop.x += 1`.

(If you would use something mutable instead like an Vector instead of the non-mutable Int here, you of course can directly work in place. I.e. say `a = []`, then `push!(a, i)` will do the right thing also in a do-block).

For convenience, Continuables comes with a second macro `@Ref` which checks your code for `variable = Ref(value)` parts and replaces all plain assignments `var = newvalue` with `var.x = newvalue`. This makes for beautiful code. Let's implement reduce with it:

```julia
using Continuables
@Ref function myreduce(continuable, merge, init)
  accumulator = Ref(init)
  continuable() do x
    accumulator = merge(accumulator, x)
  end
  accumulator
end
myreduce(i2c(0:5), +, 0) == 15
```

Let's check that `@Ref` indeed only replaced `accumulator` with `accumulator.x`. Run `@macroexpand` on the whole definition, i.e. `@macroexpand @Ref function myreduce(....`, which returns
```julia
:(function myreduce(continuable, merge, init)
      accumulator = Ref(init)
      continuable() do x
          accumulator.x = merge(accumulator.x, x)
      end
      accumulator.x
  end)
```
When combining `@cont` with `@Ref` do `@cont @Ref ...`, i.e. let `@cont` be the outer and `@Ref` be the inner macro.
