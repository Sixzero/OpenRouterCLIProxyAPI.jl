using OpenRouterCLIProxyAPI
using Documenter

DocMeta.setdocmeta!(OpenRouterCLIProxyAPI, :DocTestSetup, :(using OpenRouterCLIProxyAPI); recursive=true)

makedocs(;
    modules=[OpenRouterCLIProxyAPI],
    authors="SixZero <havliktomi@hotmail.com> and contributors",
    sitename="OpenRouterCLIProxyAPI.jl",
    format=Documenter.HTML(;
        canonical="https://sixzero.github.io/OpenRouterCLIProxyAPI.jl",
        edit_link="master",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/sixzero/OpenRouterCLIProxyAPI.jl",
    devbranch="master",
)
