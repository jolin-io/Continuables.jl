# Continuables

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://jolin-io.github.io/Continuables.jl/stable)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://jolin-io.github.io/Continuables.jl/dev)
[![Build Status](https://github.com/jolin-io/Continuables.jl/workflows/CI/badge.svg)](https://github.com/jolin-io/Continuables.jl/actions)
[![Coverage](https://codecov.io/gh/jolin-io/Continuables.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/jolin-io/Continuables.jl)


TLDR: Python / C# `yield` with performance matching plain Julia iterators  (i.e. unbelievably fast)

Continuables are generator-like higher-order functions which take a continuation as an extra argument. The key macro provided by the package is `@cont` which will give access to the special function `cont` within its scope and wraps the computation in a special Type `Continuables.Continuable`.
It is best to think of `cont` in the sense of `yield` from Python's Generators. It generates values and takes feedback from the outer process as return value.

If you come from Python, use Continuables wherever you would use generators. If you are Julia-native, Continuables can be used instead of Julia's Channels in many place with drastic performance-improvements (really drastic: in the little benchmark example below it is 20 million times faster!).

This package implements all standard functions like e.g. `collect`, `reduce`, `any` and others. As well as functionalities known from `Base.Iterators` and [`IterTools.jl`](https://github.com/JuliaCollections/IterTools.jl) like `take`, `dropwhile`, `groupby`, `partition`, `nth` and others.

For convenience, all methods also work for plain iterables.

## Installation

Install like
```julia
using Pkg
pkg"add Continuables"
```

Use it like
```julia
using Continuables
```

For further information take a look at the [documentation](https://jolin-io.github.io/Continuables.jl/dev).

## Example: flexible alternative to `walkdir`

Sometimes you recursively want to read files, skipping certain directories and doing other individual adaptations. Using `Continuables` you get full flexibility with very well readable code and good performance:

```julia
list_all_juliafiles(path=abspath(".")) = @cont begin
    if isfile(path)
        endswith(path, ".jl") && cont(path)
    elseif isdir(path)
        basename(path) in (".git",) && return
        for file in readdir(path)
            foreach(cont, list_all_juliafiles(joinpath(path, file)))
        end
    end
end

collect(list_all_juliafiles())
```
