<div align="center">
  <a href="https://genieframework.com/">
    <img
      src="docs/content/img/stipple-logo+text.svg"
      alt="Genie Logo"
      height="64"
    />
  </a>
  <br />
  <p>
    <h3>
      <b>
        Stipple.jl
      </b>
    </h3>
  </p>
  <p>
    <ul> Reactive Data Apps in Pure Julia
    </ul>
  </p>

  [![current status](https://img.shields.io/badge/julia%20support-v1.6%20and%20up-dark%20green)](https://github.com/GenieFramework/Stipple.jl/blob/9530ccd4313d7a4e3da2351eb621152047bc5cbd/Project.toml#L32) [![Website](https://img.shields.io/website?url=https%3A%2F%2Fgenieframework.com&logo=genie)](https://www.genieframework.com/#stipple-section) [![Tests](https://img.shields.io/badge/build-passing-green)](https://github.com/GenieFramework/Genie.jl/actions) [![Stipple Downloads](https://shields.io/endpoint?url=https://pkgs.genieframework.com/api/v1/badge/Stipple)](https://pkgs.genieframework.com?packages=Genie) [![Tweet](https://img.shields.io/twitter/url?url=https%3A%2F%2Fgithub.com%2FGenieFramework%2FGenie.jl)](https://twitter.com/AppStipple)

  
  <p>Stipple is a reactive UI library for building interactive data applications in pure Julia.
It uses <a href="https://github.com/GenieFramework/Genie.jl">Genie.jl</a> (on the server side) and Vue.js (on the client). Stipple uses a high performance MVVM architecture, which automatically synchronizes the state two-way
(server -> client and client -> server) sending only JSON data over the wire. The Stipple package provides the fundamental communication layer, extending <i><b>Genie's</b></i> HTML API with a reactive component.</p>
</div>


---

The Stipple ecosystem also includes:

* [StippleUI.jl](https://github.com/GenieFramework/StippleUI.jl) - the UI library for `Stipple.jl`, providing access to 30+ reactive UI elements (including forms, lists, tables, as well as layout).
* [StippleCharts.jl](https://github.com/GenieFramework/StippleCharts.jl) - the  charts library for `Stipple.jl`, providing access to a growing collection of reactive charts.
* [StipplePlotly.jl](https://github.com/GenieFramework/StipplePlotly.jl) - alternative plotting library for `Stipple.jl` which uses Plotly. 
* [StipplePlotlyExport.jl](https://github.com/GenieFramework/StipplePlotlyExport.jl) - add-on for `StipplePlotly.jl` to allow server side generation and exporting of plots. 
* [StippleLatex.jl](https://github.com/GenieFramework/StippleLatex.jl) - support for (reactive) Latex content. 

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
using Stipple

@reactive mutable struct Name <: ReactiveModel
  name::R{String} = "World!"
end

function ui(model)
  page( model, class="container", [
      h1([
        "Hello "
        span("", @text(:name))
      ])

      p([
        "What is your name? "
        input("", placeholder="Type your name", @bind(:name))
      ])
    ]
  )
end

route("/") do
  model = Name |> init
  html(ui(model), context = @__MODULE__)
end

up() # or `up(open_browser = true)` to automatically open a browser window/tab when launching the app
```

This will start a web app on port 8000 and we'll be able to access it in the browser at http://localhost:8000

Once the page is loaded, we'll be able to interact with the data and see how it's synced.

We can update the name value from Julia, and see it reflected on the page, at the REPL:

```julia
julia> model.name[] = "Adrian" # updating the property in Julia will update the values on the front
```

On the webpage, we can change the name in the input field and confirm that it has been updated in Julia:

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
using Genie.Renderer.Html, Stipple, StippleUI

@reactive mutable struct Model <: ReactiveModel
  process::R{Bool} = false
  output::R{String} = ""
  input::R{String} = ""
end

function handlers(model)
  on(model.process) do _
    if (model.process[])
      model.output[] = model.input[] |> reverse
      model.process[] = false
    end
  end

  model
end

function ui(model)
  page(model, class="container", [
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
  )
end

route("/") do
  model = Model |> init |> handlers
  html(ui(model), context = @__MODULE__)
end

isrunning(:webserver) || up()
```

## Choosing the transport layer: WebSockets or HTTP

By default Stipple will attempt to use WebSockets for real time data sync between backend and frontend.
However, in some cases WebSockets support might not be available on the host. In this case, Stipple can be
switched to use regular HTTP for data sync, using frontend polling with AJAX (1s polling interval by default).
Stipple can be configured to use AJAX/HTTP by passing the `transport` param to the `init()` method, ex:

```julia
model = Stipple.init(Name(), transport = Genie.WebThreads)
```

The current available options for `transport` are `Genie.WebChannels` (default, using WebSockets) and
`Genie.WebThreads` (using HTTP/AJAX).

Given that polling generates quite a number of extra requests, it can be desirable to disable automatic
logging of requests. This can be done using `Genie.config.log_requests = false`.

Support for `WebThreads` and request logging disabling has been introduced in Genie v1.14 and Stipple v0.8.

### First example changed to use `WebThreads`

```julia
using Genie.Renderer.Html, Stipple

Genie.config.log_requests = false

@reactive mutable struct Name <: ReactiveModel
  name::R{String} = "World!"
end

function ui(model)
  page(model, class="container",
    [
      h1([
        "Hello "
        span("", @text(:name))
      ])

      p([
        "What is your name? "
        input("", placeholder="Type your name", @bind(:name))
      ])
    ]
  )
end

route("/") do
  model = Stipple.init(Name(), transport = Genie.WebThreads)
  html(ui(model), context = @__MODULE__)
end

isrunning(:webserver) || up()
```

## Demos

### German Credits visualisation dashboard

<img src="https://genieframework.com/githubimg/Screenshot_German_Credits.png" width="800">

The full application is available at:
<https://github.com/GenieFramework/Stipple-Demo-GermanCredits>

### Iris Flowers dataset k-Means clustering dashboard

<img src="https://genieframework.com/githubimg/Screenshot_Iris_Data.png" width="800">

The full application is available at:
<https://github.com/GenieFramework/Stipple-Demo-IrisClustering>
