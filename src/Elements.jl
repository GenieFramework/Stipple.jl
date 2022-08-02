"""
    Stipple.Elements

The `Elements` module provides utility methods for interfacing between Julia and Vue.js.
"""
module Elements

import Genie
using Stipple

import Genie.Renderer.Html: HTMLString, normal_element

export root, elem, vm, @iif, @elsiif, @els, @recur, @text, @bind, @data, @on, @showif
export stylesheet

#===#

"""
    function root(app::M)::String where {M<:ReactiveModel}

Generates a valid JavaScript object name to be used as the name of the Vue app -- and its respective HTML container.
"""
function root(app::M)::String where {M<:ReactiveModel}
  Genie.Generator.validname(typeof(app) |> string)
end

function root(app::Type{M})::String where {M<:ReactiveModel}
  Genie.Generator.validname(app |> string)
end

"""
    function elem(app::M)::String where {M<:ReactiveModel}

Generates a JS id `#` reference to the DOM element containing the Vue app template.
"""
function elem(app::M)::String where {M<:ReactiveModel}
  "#$(root(app))"
end

const vm = root

#===#

"""
    function vue_integration(model::M; vue_app_name::String, endpoint::String, debounce::Int)::String where {M<:ReactiveModel}

Generates the JS/Vue.js code which handles the 2-way data sync between Julia and JavaScript/Vue.js.
It is called internally by `Stipple.init` which allows for the configuration of all the parameters.
"""
function vue_integration(m::Type{M};
                          vue_app_name::String = "StippleApp",
                          core_theme::Bool = true,
                          debounce::Int = Stipple.JS_DEBOUNCE_TIME,
                          transport::Module = Genie.WebChannels)::String where {M<:ReactiveModel}

  model = Base.invokelatest(m)

  vue_app = replace(json(model |> Stipple.render), "\"{" => " {")
  vue_app = replace(vue_app, "}\"" => "} ")
  vue_app = replace(vue_app, "\"$(getchannel(model))\"" => Stipple.channel_js_name)

  output =
  string(
    "

  function initStipple(rootSelector){
    Stipple.init($( core_theme ? "{theme: 'stipple-blue'}" : "" ));
    window.$vue_app_name = new Vue($( replace(vue_app, "'$(Stipple.UNDEFINED_PLACEHOLDER)'"=>Stipple.UNDEFINED_VALUE) ));
  } // end of initStipple

    "

    ,

    "

  function initWatchers(){
    "

    ,
    join(
      [Stipple.watch(string("window.", vue_app_name), field, Stipple.channel_js_name, debounce, model) for field in fieldnames(m)
        if Stipple.has_frontend_watcher(field, model)]
    )
    ,

    "
  } // end of initWatchers

    "

    ,

    """

  window.parse_payload = function(payload){
    if (payload.key) {
      window.$(vue_app_name).revive_payload(payload)
      window.$(vue_app_name).updateField(payload.key, payload.value);
    }
  }

  function app_ready() {
      $vue_app_name.isready = true;

      $(transport == Genie.WebChannels &&
      "
      try {
        if (Genie.Settings.webchannels_keepalive_frequency > 0) {
          setInterval(keepalive, Genie.Settings.webchannels_keepalive_frequency);
        }
      } catch (e) {
        if (Genie.Settings.env === 'dev') {
          console.error('Error setting WebSocket keepalive interval: ' + e);
        }
      }
      ")

      if (Genie.Settings.env === 'dev') {
        console.info('App starting');
      }
  };

  if ( window.autorun === undefined || window.autorun === true ) {
    initStipple('#$vue_app_name');
    initWatchers();

    Genie.WebChannels.subscriptionHandlers.push(function(event) {
      app_ready();
    });
  }
  """
  )

  output = repr(output)
  output[2:prevind(output, lastindex(output))]
end

#===#

"""
    @iif(expr)

Generates `v-if` Vue.js code using `expr` as the condition.
<https://vuejs.org/v2/api/#v-if>

### Example

```julia
julia> span("Bad stuff's about to happen", class="warning", @iif(:warning))
"<span class=\"warning\" v-if='warning'>Bad stuff's about to happen</span>"
```
"""
macro iif(expr)
  :( "v-if='$($(esc(expr)))'" )
end

"""
    @elsiif(expr)

Generates `v-else-if` Vue.js code using `expr` as the condition.
<https://vuejs.org/v2/api/#v-else-if>

### Example

```julia
julia> span("An error has occurred", class="error", @elsiif(:error))
"<span class=\"error\" v-else-if='error'>An error has occurred</span>"
```
"""
macro elsiif(expr)
  :( "v-else-if='$($(esc(expr)))'" )
end

"""
    @els(expr)

Generates `v-else` Vue.js code using `expr` as the condition.
<https://vuejs.org/v2/api/#v-else>

### Example

```julia
julia> span("Might want to keep an eye on this", class="notice", @els(:notice))
"<span class=\"notice\" v-else='notice'>Might want to keep an eye on this</span>"
```
"""
macro els(expr)
  :( "v-else='$($(esc(expr)))'" )
end

"""
Generates `v-for` directive to render a list of items based on an array.
<https://vuejs.org/v2/guide/list.html#Mapping-an-Array-to-Elements-with-v-for>

### Example

```julia
julia> p(" {{todo}} ", class="warning", @recur(:"todo in todos"))
"<p v-for='todo in todos'>\n {{todo}} \n</p>\n"
```

"""
macro recur(expr)
  :( "v-for='$($(esc(expr)))'" )
end

"""
    @text(expr)

Creates a `v-text` or a `text-content.prop` Vue biding to the element's `textContent` property.
<https://vuejs.org/v2/api/#v-text>

### Example

```julia
julia> span("", @text("abc | def"))
"<span :text-content.prop='abc | def'></span>"

julia> span("", @text("abc"))
"<span v-text='abc'></span>"
```
"""
macro text(expr)
  quote
    directive = occursin(" | ", string($(esc(expr)))) ? ":text-content.prop" : "v-text"
    "$(directive)='$($(esc(expr)))'"
  end
end

"""
    @bind(expr, [type])

Binds a model parameter to a Vue component, generating a `v-model` property, optionally defining the parameter type.
<https://vuejs.org/v2/api/#v-model>

### Example

```julia
julia> input("", placeholder="Type your name", @bind(:name))
"<input placeholder=\"Type your name\"  v-model='name' />"

julia> input("", placeholder="Type your name", @bind(:name, :identity))
"<input placeholder=\"Type your name\"  v-model.identity='name' />"
```
"""
macro bind(expr)
  :( "v-model='$($(esc(expr)))'" )
end

macro bind(expr, type)
  :( "v-model.$($(esc(type)))='$($(esc(expr)))'" )
end

"""
    @data(expr)

Creates a Vue.js data binding for the elements that expect it.

### Example

```julia
julia> plot(@data(:piechart), options! = "plot_options")
"<template><apexchart :options=\"plot_options\" :series=\"piechart\"></apexchart></template>"
```
"""
macro data(expr)
  quote
    x = $(esc(expr))
    if typeof(x) <: Union{AbstractString,Symbol}
      Symbol(x)
    else
      strx = strip("$x")
      startswith(strx, "Any[") && (strx = strx[4:end])

      JSONText(string(":", strx))
    end
  end
end

"""
    on(action, expr)

Defines a js routine that is called by the given `action` of the Vue component, e.g. `:click`, `:input`

### Example

```julia
julia> input("", @bind(:input), @on("keyup.enter", "process = true"))
"<input  v-model='input' v-on:keyup.enter='process = true' />"
```

If `expr` is a symbol, there must exist `Stipple.notify` override, i.e. an event
handler function for a corresponding event with the name `expr`.

### Example

```julia
julia> Stipple.notify(model, ::Val{:my_click}) = println("clicked")

julia> @on("click", :my_click)
"v-on:click='handle_event(\$event, 'my_click')'"
```
"""
macro on(args, expr)
  quote
    e = string($(esc(args)))
    x = $(esc(expr))
    if typeof(x) <: Symbol
        "v-on:$e='handle_event(\$event, \"$x\")'"
    else
        "v-on:$(string($(esc(args))))='$(replace(x,"'" => raw"\'"))'"
    end
  end
end


"""
    @showif(expr, [type])

v-show will always be rendered and remain in the DOM; v-show only toggles the display CSS property of the element.
<https://vuejs.org/v2/guide/conditional.html#v-show>

Difference between @showif and @iif when to use either

v-if has higher toggle costs while v-show has higher initial render costs

### Example

```julia
julia> h1("Hello!", @showif(:ok))
"<h1 v-show="ok">Hello!</h1>"
```
"""
macro showif(expr)
  :( "v-show='$($(esc(expr)))'" )
end

#===#

"""
    function stylesheet(href::String; args...) :: String

Generates the corresponding HTML `link` tag to reference the CSS stylesheet at `href`.

### Example

```julia
julia> stylesheet("https://fonts.googleapis.com/css?family=Material+Icons")
"<link href=\"https://fonts.googleapis.com/css?family=Material+Icons\" rel=\"stylesheet\" />"
```
"""
function stylesheet(href::String; args...) :: ParsedHTMLString
  Genie.Renderer.Html.link(href=href, rel="stylesheet", args...)
end

end
