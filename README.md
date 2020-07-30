# Stipple

Stipple is a reactive UI library for building interactive data applications in pure Julia.
It uses [Genie.jl]((https://github.com/GenieFramework/Genie.jl)) (on the server side) and Vue.js (on the client).

Stipple uses a high performance MVVM architecture, which automatically synchronizes the state two-way
(server -> client and client -> server) sending only JSON data over the wire.

The Stipple package provides the fundamental communication layer, extending `Genie`'s HTML API with a reactive component.

The Stipple ecosystem also includes:

* [StippleUI.jl](https://github.com/GenieFramework/StippleUI.jl) - the UI library for `Stipple.jl`, providing access to 30+ reactive UI elements (including forms, lists, tables, as well as layout).
* [StippleCharts.jl](https://github.com/GenieFramework/StippleCharts.jl) - the  charts library for `Stipple.jl`, providing access to a growing collection of reactive charts.

## Installation

Stipple can be added from the GitHub repo, via `Pkg`:
```julia
pkg> add Stipple
```

## Example

Add `Genie` first:
```julia
pkg> add Genie
```

Now we can run the following code at the Julia REPL:

```julia
using Genie, Genie.Router, Genie.Renderer.Html, Stipple

Base.@kwdef mutable struct Name <: ReactiveModel
  name::R{String} = "World!"
end

model = Stipple.init(Name)

function ui()
  page(
    root(model), class="container", [
      h1([
        "Hello "
        span("", @text(:name))
      ])

      p([
        "What is your name? "
        input("", placeholder="Type your name", @bind(:name))
      ])
    ], title="Basic Stipple"
  ) |> html
end

route("/", ui)

up()
```

This will start a web app on port 8000 and we'll be able to access it in the browser at http://localhost:8000

Once the page is loaded, we'll be able to interact with the data and see how it's synced.

We can update the name value from Julia, and see it reflected on the page, at the REPL:
```julia
julia> model.name[] = "Adrian" # updating the property in Julia will update the values on the front
```

Also, on the webpage, we change the name in the input field and confirm that it has been updated in Julia:
```julia
julia> model.name[] # will have the same value as what you have inputted on the web page
```

You can see a quick video demo here:
<https://www.dropbox.com/s/50t5bqd2zk4ehxo/basic_stipple_3.mp4?dl=0>

## Demos

### German Credits visualisation dashboard

<img src="https://genieframework.com/githubimg/Screenshot_German_Credits.png" width=800>

The full application is available at:
<https://github.com/GenieFramework/Stipple-Demo-GermanCredits>

### Iris Flowers dataset k-Means clustering dashboard

<img src="https://genieframework.com/githubimg/Screenshot_Iris_Data.png" width=800>

The full application is available at:
<https://github.com/GenieFramework/Stipple-Demo-IrisClustering>
