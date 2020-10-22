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

## Examples

### Downloadable demos repo available at: https://github.com/GenieFramework/StippleDemos

### Example 1

---

Add `Genie` and `Stipple` first:

```julia
pkg> add Stipple
pkg> add Genie
```

Now we can run the following code at the Julia REPL:

```julia
using Genie, Genie.Router, Genie.Renderer.Html, Stipple

Base.@kwdef mutable struct Name <: ReactiveModel
  name::R{String} = "World!"
end

model = Stipple.init(Name())

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
    ]
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

The Stipple presentation from JuliaCon 2020 is available here (8 minutes):
<https://www.dropbox.com/s/6atyctgomsqwjki/stipple_exported.mp4?dl=0>

### Example 2

This snippet illustrates how to build a UI where the button triggers a computation (function call) on the
server side, using the input provided by the user, and outputting the result of the computation back to the user.

```julia
using Genie, Genie.Router, Genie.Renderer.Html, Stipple

Base.@kwdef mutable struct Model <: ReactiveModel
  process::R{Bool} = false
  output::R{String} = ""
  input::R{String} = ""
end

model = Stipple.init(Model())

on(model.process) do _
  if (model.process[])
    model.output[] = model.input[] |> reverse
    model.process[] = false
  end
end

function ui()
  page(
    root(model), class="container", [
      p([
        "Input "
        input("", @bind(:input), @on("keyup.enter", "process = true"))
      ])

      p([
        button("Action!", @click("process = true"))
      ])

      p([
        "Output: "
        span("", @text(:output))
      ])
    ]
  ) |> html
end

route("/", ui)

up()
```

## Demos

### German Credits visualisation dashboard

<img src="https://genieframework.com/githubimg/Screenshot_German_Credits.png" width=800>

The full application is available at:
<https://github.com/GenieFramework/Stipple-Demo-GermanCredits>

### Iris Flowers dataset k-Means clustering dashboard

<img src="https://genieframework.com/githubimg/Screenshot_Iris_Data.png" width=800>

The full application is available at:
<https://github.com/GenieFramework/Stipple-Demo-IrisClustering>
