using Documenter
using Stipple

makedocs(
    sitename = "Stipple.jl",
    format = Documenter.HTML(),
    modules = [Stipple],
    pages = [
        "Home" => "index.md",
        "Tutorial" => "tutorial/basics.md"
        ],
    checkdocs = :exports
)

# Documenter can also automatically deploy documentation to gh-pages.
# See "Hosting Documentation" and deploydocs() in the Documenter manual
# for more information.


deploydocs(
    repo = "https://github.com/GenieFramework/Stipple.jl",
)
