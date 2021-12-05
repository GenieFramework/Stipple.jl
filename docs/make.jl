using Documenter

push!(LOAD_PATH,  "../../src")

using Stipple, Stipple.Elements, Stipple.Layout, Stipple.Typography

makedocs(
    sitename = "SearchLight - Concise, secure, cross-platform query builder and ORM for Julia",
    format = Documenter.HTML(prettyurls = false),
    pages = [
        "Home" => "index.md",
        "Stipple API" => [
          "Elements" => "api/elements.md",
          "Layout" => "api/layout.md",
          "NamedTuples" => "api/namedtuples.md",
          "Stipple" => "api/stipple.md",
          "Typography" => "api/typography.md",
        ]
    ],
)

deploydocs(
  repo = "github.com/GenieFramework/Stipple.jl.git",
)
