using Logfire
using Documenter

DocMeta.setdocmeta!(Logfire, :DocTestSetup, :(using Logfire); recursive = true)

makedocs(;
    modules = [Logfire],
    authors = "J S @svilupp and contributors",
    sitename = "Logfire.jl",
    format = Documenter.HTML(;
        canonical = "https://svilupp.github.io/Logfire.jl",
        edit_link = "main",
        assets = String[]
    ),
    pages = [
        "Home" => "index.md",
        "Query API" => "query-api.md",
        "Alternative Backends" => "alternative-backends.md",
        "OTEL GenAI Semantic Conventions" => "otel-genai.md"
    ]
)

deploydocs(;
    repo = "github.com/svilupp/Logfire.jl",
    devbranch = "main"
)
