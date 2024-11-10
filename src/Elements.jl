"""
    Stipple.Elements

The `Elements` module provides utility methods for interfacing between Julia and Vue.js.
"""
module Elements

import Genie
using Stipple
using MacroTools

import Genie.Renderer.Html: HTMLString, normal_element

export root, elem, vm, @if, @else, @elseif, @for, @text, @bind, @data, @on, @click, @showif, @slot
export stylesheet, kw_to_str
export add_plugins, remove_plugins

const Plugins = Dict{String, Union{JSONText, AbstractDict}}
PLUGINS = LittleDict{Union{Module, Type{<:ReactiveModel}}, Plugins}()


function add_plugins(parent::Union{Module, Type{<:ReactiveModel}}, plugins::Function; legacy::Bool = false)
  add_plugins(parent, plugins(); legacy)
end

function add_plugins(parent::Union{Module, Type{<:ReactiveModel}}, plugins::AbstractDict; legacy::Bool = false)
  if legacy
    d = LittleDict()
    for (plugin, options) in plugins
      push!(d, "window.vueLegacy.plugins['$plugin'].plugin" => options)
    end
    plugins = d
  end
  if haskey(PLUGINS, parent)
    merge!(PLUGINS[parent], plugins)
  else
    PLUGINS[parent] = plugins
  end
  PLUGINS
end

function add_plugins(parent::Union{Module, Type{<:ReactiveModel}}, plugins::Union{String, Vector{String}}; legacy::Bool = false)
  plugins isa String && (plugins = [plugins])
  plugin_dict = if legacy
    d = LittleDict()
    for plugin in plugins
      p = """window.vueLegacy.plugins["$plugin"]"""
      plugin = "$p.plugin"
      options = JSONText("($p.options) ? $p.options : {}")
      push!(d, plugin => options)
    end
    d
  else
    LittleDict(p => Dict() for p in plugins)
  end
  PLUGINS[parent] = plugin_dict
  PLUGINS
end

function remove_plugins(parent::Union{Module, Type{<:ReactiveModel}})
  delete!(PLUGINS, parent)
end

function remove_plugins(parent::Union{Module, Type{<:ReactiveModel}}, plugins::Union{String, Vector{String}})
  haskey(PLUGINS, parent) || return PLUGINS
  for plugin in (plugins isa String ? [plugins] : plugins)
    delete!(PLUGINS[parent], plugin)
  end
  isempty(PLUGINS[parent]) && delete!(PLUGINS, parent)
  PLUGINS
end

add_plugins(parent::Union{Module, Type{<:ReactiveModel}}, plugins::Union{Pair, AbstractVector{Pair}}) = add_plugins(parent, Dict(plugins))
remove_plugins(parent::Union{Module, Type{<:ReactiveModel}}, plugins::AbstractDict) = remove_plugins(parent, collect(keys(plugins)))
remove_plugins(parent::Union{Module, Type{<:ReactiveModel}}, plugins::Function) = remove_plugins(parent, plugins())

add_plugins(plugins) = add_plugins(Stipple, plugins)
remove_plugins(plugins) = remove_plugins(Stipple, plugins)

function plugins(::Type{M}) where M <: ReactiveModel
  pplugins = values(filter(x -> x[1] isa Module, PLUGINS))
  isempty(pplugins) && return ""
  plugins = reduce(merge, pplugins)
  app_plugins = get(PLUGINS, M, nothing)
  app_plugins === nothing || merge!(plugins, app_plugins)
  io = IOBuffer()
  for (plugin, options) in plugins
    print(io, options isa AbstractDict && isempty(options) ? "\n  app.use($plugin);" : "\n  app.use($plugin, $(js_attr(options)));")
  end
  String(take!(io))
end

plugins() = plugins(ReactiveModel)

#===#

"""
    function root(app::M)::String where {M<:ReactiveModel}

Generates a valid JavaScript object name to be used as the name of the Vue app -- and its respective HTML container.
"""
function root(::Type{M})::String where {M<:ReactiveModel}
  Stipple.routename(M)
end

root(::M) where M<:ReactiveModel = root(M)

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
function vue_integration(::Type{M};
                          vue_app_name::String = "StippleApp",
                          core_theme::Bool = true,
                          debounce::Int = Stipple.JS_DEBOUNCE_TIME,
                          transport::Module = Genie.WebChannels)::String where {M<:ReactiveModel}
  model = Base.invokelatest(M)
  app = "window[appName]"
  vue_app = json(model |> Stipple.render)
  vue_app = replace(vue_app, "\"$(getchannel(model))\"" => Stipple.channel_js_name)

  # determine global components (registered under ReactiveModel)
  comps = Stipple.components(M)
  if !isempty(comps)
    comps = """
      components = {$comps}
      Object.entries(components).forEach(([key, value]) => {
        app.component(key, value)
      });
    """
  end

  globalcomps = Stipple.components(ReactiveModel)
  if !isempty(globalcomps)
    globalcomps = """
      components = {$globalcomps}
      Object.entries(components).forEach(([key, value]) => {
        app.component(key, value)
      });
    """
  end

  output =
  string(
    "

  function initStipple$vue_app_name(appName, rootSelector){
    // components = Stipple.init($( core_theme ? "{theme: '$theme'}" : "" ));
    const app = Vue.createApp($( replace(vue_app, "'$(Stipple.UNDEFINED_PLACEHOLDER)'"=>Stipple.UNDEFINED_VALUE) ))
    /* Object.entries(components).forEach(([key, value]) => {
      app.component(key, value)
    }); */
    Stipple.init( app, $( core_theme ? "{theme: '$theme'}" : "" ));
    $globalcomps
    $comps
    // gather legacy global options
    app.prototype = {}
    $(plugins(M))
    // apply legacy global options
    Object.entries(app.prototype).forEach(([key, value]) => {
      app.config.globalProperties[key] = value
    });
    $app = window.GENIEMODEL = app.mount(rootSelector);
    window.channelIndex = window.channelIndex || 0;
    $app.WebChannel = Genie.AllWebChannels[channelIndex];
    $app.WebChannel.parent = $app;
    $app.channel_ = $app.WebChannel.channel;

    channelIndex++;
  } // end of initStipple

    "

    ,

    "

  function initWatchers$vue_app_name(app){
    "

    ,
    join(
      [Stipple.watch("app", field, Stipple.channel_js_name, debounce, model) for field in fieldnames(Stipple.get_concrete_type(M))
        if Stipple.has_frontend_watcher(field, model)]
    )
    ,

    "
  } // end of initWatchers

    "

    ,

    """

  window.parse_payload = function(WebChannel, payload){
    if (payload.key) {
      WebChannel.parent.updateField(payload.key, payload.value);
    }
  }

  function app_ready(app) {
      app.isready = true;
      Genie.Revivers.addReviver(app.revive_jsfunction);
      $(transport == Genie.WebChannels &&
      "
      try {
        if (Genie.Settings.webchannels_keepalive_frequency > 0) {
          clearInterval(app.WebChannel.keepalive_interval);
          app.WebChannel.keepalive_interval = setInterval(() => keepalive(app.WebChannel), Genie.Settings.webchannels_keepalive_frequency);
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

  function create$vue_app_name() {
    window.counter$vue_app_name = window.counter$vue_app_name || 1
    const appName = '$vue_app_name' + ((counter$vue_app_name == 1) ? '' : '_' + window.counter$vue_app_name)
    rootSelector = '#$vue_app_name' + ((counter$vue_app_name == 1) ? '' : '-' + window.counter$vue_app_name)
    counter$vue_app_name++

    if ( window.autorun === undefined || window.autorun === true ) {
      initStipple$vue_app_name(appName, rootSelector);
      initWatchers$vue_app_name($app);

      $app.WebChannel.subscriptionHandlers.push(function(event) {
        app_ready($app);
      });
    }
  }

  // create$vue_app_name()
  // is called via scipt with addEventListener to support multiple apps
  """
  )

  output = repr(output)
  output[2:prevind(output, lastindex(output))]
end

#===#

function quote_replace(s::String)
  if occursin('"', s)
    # escape unescaped quotes
    replace(occursin(''', s) ? replace(s, r"(?<!\\)'" => "\\'") : s, '"' => ''')
  else
    s
  end
end

function esc_expr(expr)
    :(Stipple.Elements.quote_replace("$($(esc(expr)))"))
end

function kw_to_str(; kwargs...)
  join(["$k = \"$v\"" for (k,v) in kwargs], ' ')
end

"""
    @if(expr)

Generates `v-if` Vue.js code using `expr` as the condition.
<https://vuejs.org/v2/api/#v-if>

### Example

```julia
julia> span("Bad stuff's about to happen", class="warning", @if(:warning))
"<span class=\"warning\" v-if='warning'>Bad stuff's about to happen</span>"
```
"""
macro iif(expr)
  Expr(:kw, Symbol("v-if"), esc_expr(expr))
end
const var"@if" = var"@iif"

  """
    @elseif(expr)

Generates `v-else-if` Vue.js code using `expr` as the condition.
<https://vuejs.org/v2/api/#v-else-if>

### Example

```julia
julia> span("An error has occurred", class="error", @elseif(:error))
"<span class=\"error\" v-else-if='error'>An error has occurred</span>"
```
"""
macro elsiif(expr)
  Expr(:kw, Symbol("v-else-if"), esc_expr(expr))
end
const var"@elseif" = var"@elsiif"

"""
    @else(expr)

Generates `v-else` Vue.js code using `expr` as the condition.
<https://vuejs.org/v2/api/#v-else>

### Example

```julia
julia> span("Might want to keep an eye on this", class="notice", @else(:notice))
"<span class=\"notice\" v-else='notice'>Might want to keep an eye on this</span>"
```
"""
macro els(expr)
  Expr(:kw, Symbol("v-else"), esc_expr(expr))
end
const var"@else" = var"@els"

"""
Generates `v-for` directive to render a list of items based on an array.
<https://vuejs.org/v2/guide/list.html#Mapping-an-Array-to-Elements-with-v-for>

`@for` supports both js expressions as String or a Julia expression with Vectors or Dicts

## Example

### Javascript
```julia
julia> p(" {{todo}} ", class="warning", @for("todo in todos"))
\"\"\"
<p v-for='todo in todos'>
    {{todo}}
</p>
\"\"\"
```
### Julia expression
```julia
julia> dict = Dict(:a => "b", :c => 4);
julia> ul(li("k: {{ k }}, v: {{ v }}, i: {{ i }}", @for((v, k, i) in dict)))
\"\"\"
<ul>
    <li v-for="(v, k, i) in {'a':'b','c':4}">
        k: {{ k }}, v: {{ v }}, i: {{ i }}
    </li>
</ul>
\"\"\"
```
Note the inverted order of value, key and index compared to Stipple destructuring.
It is also possible to loop over `(v, k)` or `v`; index will always be zero-based

"""
macro recur(expr)
  expr isa Expr && expr.head == :call && expr.args[1] == :in && (expr.args[2] = string(expr.args[2]))
  expr = (MacroTools.@capture(expr, y_ in z_)) ? :("$($y) in $($z isa Union{AbstractDict, AbstractVector} ? Stipple.js_attr($z) : $z)") : :("$($expr)")

  Expr(:kw, Symbol("v-for"), esc_expr(expr))
end
const var"@for" = var"@recur"

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
  s = @eval __module__ string($(expr))
  directive = occursin(" | ", s) ? Symbol(":text-content.prop") : R"v-text"
  Expr(:kw, directive, s)
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
  Expr(:kw, Symbol("v-model"), esc_expr(expr))
end

macro bind(expr, type)
  vmodel = Symbol("v-model.", @eval(__module__, $type))
  Expr(:kw, vmodel, esc_expr(expr))
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
```
or if event information is needed
```julia
Stipple.notify(model, ::Val{:my_click}, event_info) = println(event_info)
```
Note that in the handler `model` refers to the receiving model and event is a Dict of event information.
The handler is linked in the ui-element
```julia
btn("Event test", @on("click", :my_click))
```
Sometimes preprocessing of the events is necessary, e.g. to add or skip information
```julia
@on(:uploaded, :uploaded, "for (f in event.files) { event.files[f].fname = event.files[f].name }")
```
"""
macro on(arg, expr, preprocess = nothing)
  preprocess isa QuoteNode && preprocess == :(:addclient) && (preprocess = "event._addclient = true")
  kw = Symbol("v-on:", arg isa String ? arg : arg isa QuoteNode ? arg.value : arg.head == :vect ? join(lstrip.(string.(arg.args), ':'), '.') :
    throw("Value '$arg' for `arg` not supported. `arg` should be of type Symbol, String, or Vector{Union{String, Symbol}}"))

  isevent = expr isa QuoteNode && expr.value isa Symbol
  v = if isevent
      if preprocess === nothing
          :("(event) => { handle_event(event, '$($(esc(expr)))') }")
      else
          :(replace("""(event) => {
              const preprocess = (event) => { """ * replace($preprocess, '"' => "\\\"") * """; return event }
              handle_event(preprocess(event), '$($(esc(expr)))')
          }""", '\n' => ';'))
      end
  else
      esc_expr(expr)
  end
  Expr(:kw, kw, v)
end


"""
    `@click(expr, modifiers = [])`

Defines a js routine that is called by a click of the quasar component.
If a symbol argument is supplied, `@click` sets this value to true.

`@click("savefile = true")` or `@click("myjs_func();")` or `@click(:button)`

Modifers can be appended as String, Symbol or array of String/Symbol:
```
@click(:foo, :stop)
# "v-on:click.stop='foo = true'"

@click("foo = bar", [:stop, "prevent"])
# "v-on:click.stop.prevent='foo = bar'"
```
"""
macro click(expr, modifiers = [])
  mods = @eval __module__ $modifiers
  m = mods isa Symbol || ! isempty(mods) ? mods isa Vector ? '.' * join(String.(mods), '.') : ".$mods" : ""
  # mods = $(esc(modifiers))
  if expr isa QuoteNode && expr.value isa Symbol
    Expr(:kw, Symbol("v-on:click$m"), "$(expr.value) = true")
  else
    Expr(:kw, Symbol("v-on:click$m"), esc_expr(expr))
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
  Expr(:kw, Symbol("v-show"), esc_expr(expr))
end


"""
    hyphenate(expr)

Convert minus operations in expressions into join-operations with '-'

### Example
```julia
julia> :(a-b-c) |> hyphenate
Symbol("a-b-c")
```
"""
function hyphenate(@nospecialize expr)
  if expr isa Expr && expr.head == :call && expr.args[1] == :-
    x = expr.args[2]
    Symbol(x isa Expr ? hyphenate(x) : x isa QuoteNode ? x.value : x, '-', join(expr.args[3:end], '-'))
  else
    expr
  end
end

hyphenate(expr...) = hyphenate.(expr)

"""
    @slot(slotname)

Add a v-slot attribute to a template.

### Example

```julia
julia> template(@slot(:header), [cell("Header")])
"<template v-slot:header><div class=\"st-col col\">Header</div></template>"
```
"""
macro slot(slotname)
  slotname isa Expr && (slotname = hyphenate(slotname))
  slotname isa QuoteNode && (slotname = slotname.value)
  Expr(:kw, Symbol("v-slot:$slotname"), "") |> esc
end

"""
    @slot(slotname, varname)

Add a v-slot attribute with a variable name to a template.

### Example

```julia
julia> template(@slot(:body, :props), ["{{ props.value }}"])
"<template v-slot:body=\"props\">{{ props.value }}</template>"
```
"""
macro slot(slotname, varname)
  slotname isa Expr && (slotname = hyphenate(slotname))
  slotname isa QuoteNode && (slotname = slotname.value)
  Expr(:kw, Symbol("v-slot:$slotname"), varname) |> esc
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
function stylesheet(href::String; kwargs...) :: ParsedHTMLString
  Genie.Renderer.Html.link(href=href, rel="stylesheet"; kwargs...)
end

end
