using Continuables
using Documenter

makedocs(;
    modules=[Continuables],
    authors="Stephan Sahm <stephan.sahm@gmx.de> and contributors",
    repo="https://github.com/schlichtanders/Continuables.jl/blob/{commit}{path}#L{line}",
    sitename="Continuables.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://schlichtanders.github.io/Continuables.jl",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
        "Manual" => "manual.md",
        "Benchmark" => "benchmark.md",
        "Library" => "library.md",
    ],
)

deploydocs(;
    repo="github.com/schlichtanders/Continuables.jl",
)
