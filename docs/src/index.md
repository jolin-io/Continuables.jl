# Continuables.jl

TLDR: Python / C# `yield` with performance matching plain Julia iterators  (i.e. unbelievably fast)

Continuables are generator-like higher-order functions which take a continuation as an extra argument. The key macro provided by the package is `@cont` which will give access to the special function `cont` within its scope and wraps the computation in a special Type `Continuables.Continuable`.
It is best to think of `cont` in the sense of `yield` from Python's Generators. It generates values and takes feedback from the outer process as return value.

If you come from Python, use Continuables wherever you would use generators. If you are Julia-native, Continuables can be used instead of Julia's Channels in many place with drastic performance-improvements (really drastic: in the little benchmark example below it is 20 million times faster!).

This package implements all standard functions like e.g. `collect`, `reduce`, `any` and others. As well as functionalities known from `Base.Iterators` and [`IterTools.jl`](https://github.com/JuliaCollections/IterTools.jl) like `take`, `dropwhile`, `groupby`, `partition`, `nth` and others.


## Installation

This package and some dependencies are not yet centrally registered, but available via a custom registry. All you need to install is the following:

```julia
using Pkg
pkg"registry add https://github.com/JuliaRegistries/General"  # central julia registry
pkg"registry add https://github.com/schlichtanders/SchlichtandersJuliaRegistry.jl"  # custom registry
pkg"add Continuables"
```

Use it like
```julia
using Continuables
```


## Manual Outline

```@contents
Pages = ["manual.md"]
```

## [Library Index](@id main-index)

```@contents
Pages = ["library.md"]
```
