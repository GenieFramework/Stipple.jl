module ReactiveTools

using Stipple
using MacroTools
using MacroTools: postwalk
using OrderedCollections
import Genie
import Stipple: deletemode!, parse_expression!, parse_expression, init_storage, striplines, striplines!, postwalk!, add_brackets!, required_evals!, parse_mixin_params

#definition of handlers/events
export @onchange, @onbutton, @event, @notify

# definition of dependencies
export @deps, @clear_deps

# definition of field-specific debounce times
export @debounce, @clear_debounce
export @throttle, @clear_throttle

# deletion
export @clear, @clear_vars, @clear_handlers

# app handling
export @page, @init, @handlers, @app, @appname, @app_mixin, @modelstorage, @handler

# js functions on the front-end (see Vue.js docs)
export @methods, @watch, @computed, @client_data, @add_client_data

export @before_create, @created, @before_mount, @mounted, @before_update, @updated, @activated, @deactivated, @before_destroy, @destroyed, @error_captured

export DEFAULT_LAYOUT, Page

function DEFAULT_LAYOUT(; title::String = "Genie App",
                          meta::D = Dict(),
                          head_content::Union{AbstractString, Vector} = "",
                          core_theme::Bool = true) where {D <:AbstractDict}
  tags = Genie.Renderers.Html.for_each(x -> """<meta name="$(string(x.first))" content="$(string(x.second))">\n""", meta)
  """
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    $tags
    <% Stipple.sesstoken() %>
    <title>$title</title>
    <% if isfile(joinpath(Stipple.Genie.config.server_document_root, "css", "genieapp.css")) %>
    <link rel='stylesheet' href='$(Stipple.Genie.Configuration.basepath())/css/genieapp.css'>
    <% else %>
    <% end %>
    <style>
      ._genie_logo {
        background:url('https://genieframework.com/logos/genie/logo-simple-with-padding.svg') no-repeat;
        background-size:40px;
        padding-top:22px;
        padding-right:10px;
        color:transparent !important;
        font-size:9pt;
      }
      ._genie .row .col-12 { width:50%; margin:auto; }
      [v-cloak] { display: none; }
    </style>
    $(join(head_content, "\n    "))
  </head>
  <body>
    <div class='container'>
      <div class='row'>
        <div class='col-12'>
          <% Stipple.page(model, partial = true, v__cloak = true, [Stipple.Genie.Renderer.Html.@yield], Stipple.@if(:isready); core_theme = $core_theme) %>
        </div>
      </div>
    </div>
    <% if isfile(joinpath(Stipple.Genie.config.server_document_root, "js", "genieapp.js")) %>
    <script src='$(Stipple.Genie.Configuration.basepath())/js/genieapp.js'></script>
    <% else %>
    <% end %>
    <footer class='_genie container'>
      <div class='row'>
        <div class='col-12'>
          <p class='text-muted credit' style='text-align:center;color:#8d99ae;'>Built with
            <a href='https://genieframework.com' target='_blank' class='_genie_logo' ref='nofollow'>Genie</a>
          </p>
        </div>
      </div>
    </footer>
    <% if isfile(joinpath(Stipple.Genie.config.server_document_root, "css", "autogenerated.css")) %>
    <link rel='stylesheet' href='$(Stipple.Genie.Configuration.basepath())/css/autogenerated.css'>
    <% else %>
    <% end %>
  </body>
</html>
"""
end

function model_typename(m::Module)
  isdefined(m, :__typename__) ? m.__typename__[] : Symbol("$(m)_ReactiveModel")
end

macro appname(expr)
  expr isa Symbol || (expr = Symbol(@eval(__module__, $expr)))
  ex = quote end
  if isdefined(__module__, expr)
    push!(ex.args, :(Stipple.ReactiveTools.delete_handlers_fn($__module__)))
    push!(ex.args, :(Stipple.ReactiveTools.delete_events($expr)))
  end
  if isdefined(__module__, :__typename__) && __module__.__typename__ isa Ref{Symbol}
    push!(ex.args, :(__typename__[] = Symbol($(string(expr)))))
  else
    push!(ex.args, :(const __typename__ = Ref{Symbol}(Symbol($(string(expr))))))
    push!(ex.args, :(__typename__[]))
  end
  :($ex) |> esc
end

macro appname()
  # reset appname to default
  appname = "$(__module__)_ReactiveModel"
  :(isdefined($__module__, :__typename__) ? @appname($appname) : $appname) |> esc
end

function Stipple.setmode!(expr::Expr, mode::Int, fieldnames::Symbol...)
  fieldname in [Stipple.INTERNALFIELDS..., :modes__] && return
  expr.args[2] isa Expr && expr.args[2].args[1] == :(Stipple._deepcopy) && (expr.args[2] = expr.args[2].args[2])

  d = if expr.args[2] isa LittleDict
    copy(expr.args[2])
  elseif expr.args[2] isa QuoteNode
    expr.args[2].value
  else # isa Expr generating a LittleDict (hopefully ...)
    expr.args[2].args[1].args[1] == :(Stipple.LittleDict) || expr.args[2].args[1].args[1] == :(LittleDict) || error("Unexpected error while setting access properties of app variables")

    d = LittleDict{Symbol, Int}()
    for p in expr.args[2].args[2:end]
      push!(d, p.args[2].value => p.args[3])
    end
    d
  end
  for fieldname in fieldnames
    mode == PUBLIC ? delete!(d, fieldname) : d[fieldname] = mode
  end
  expr.args[2] = QuoteNode(d)
end

#===#

function delete_handlers_fn(m::Module)
  if isdefined(m, :__GF_AUTO_HANDLERS__)
    Base.delete_method.(methods(m.__GF_AUTO_HANDLERS__))
  end
end

function delete_events(m::Module)
  modelname = model_typename(m)
  M = @eval m $modelname
  delete_events(M)
end

function delete_events(::Type{M}) where M
  # delete event functions
  mm = methods(Base.notify)
  for m in mm
    hasproperty(m.sig, :parameters) || continue
    T =  m.sig.parameters[2]
    if T <: M || T == Type{M} || T == Type{<:M}
      Base.delete_method(m)
    end
  end
  nothing
end

function delete_handlers!(m::Module)
  delete_handlers_fn(m)
  delete_events(m)
  nothing
end

#===#

"""
```julia
@clear
```

Deletes all reactive variables and code in a model.
"""
macro clear()
  delete_handlers!(__module__)
end

"""
```julia
@clear_handlers
```

Deletes all reactive code handlers in a model.
"""
macro clear_handlers()
  delete_handlers!(__module__)
end

import Stipple.@type
macro type()
  modelname = model_typename(__module__)
  esc(:($modelname))
end

import Stipple.@clear_cache
macro clear_cache()
  :(Stipple.clear_cache(Stipple.@type)) |> esc
end

import Stipple.@clear_route
macro clear_route()
  :(Stipple.clear_route(Stipple.@type)) |> esc
end

function _prepare(fieldname)
  if fieldname isa Symbol
    fieldname = QuoteNode(fieldname)
  else
    if fieldname isa Expr && fieldname.head == :tuple
      for (i, x) in enumerate(fieldname.args)
        x isa Symbol && (fieldname.args[i] = QuoteNode(x))
      end
    end
  end
  fieldname
end

"""
    @debounce fieldname ms

    @debounce App fieldname ms

Set field-specific debounce time in ms.
### Parameters

- `APP`: a subtype of ReactiveModel, e.g. `MyApp`
- `fieldname`: fieldname òr fieldnames as written in the declaration, e.g. `x`, `(x, y, z)`
- `ms`: debounce time in ms

### Example
#### Implicit apps
```
@app begin
  @out quick = 12
  @out slow = 12
  @in s = "Hello"
end

# no debouncing for fast messaging
@debounce quick 0

# long debouncing for long-running tasks
@debounce (slow1, slow2) 1000
```
#### Explicit apps

```
@app MyApp begin
  @out quick = 12
  @out slow = 12
  @in s = "Hello"
end

# no debouncing for fast messaging
@debounce MyApp quick 0

# long debouncing for long-running tasks
@debounce MyApp slow 1000
```
"""
macro debounce(M, fieldname, ms)
  fieldname = _prepare(fieldname)
  :(Stipple.debounce($M, $fieldname, $ms)) |> esc
end

macro debounce(fieldname, ms)
  fieldname = _prepare(fieldname)
  :(Stipple.debounce(Stipple.@type(),$fieldname, $ms)) |> esc
end

"""
    @clear_debounce

    @clear_debounce fieldname

    @clear_debounce App

    @clear_debounce App fieldname

Clear field-specific debounce time, for setting see `@debounce`.
After calling `@clear debounce` the field will be debounced by the value given in the
`@init` macro.


### Example
#### Implicit apps
```
@app begin
  @out quick = 12
  @out slow = 12
  @in s = "Hello"
end

# no debouncing for fast messaging
@debounce quick 0
@debounce slow 1000

# reset to standard value of the app
@clear_debounce quick

# clear all field-specific debounce times
@clear_debounce
```
#### Explicit apps

```
@app MyApp begin
  @out quick = 12
  @out slow = 12
  @in s = "Hello"
end

# no debouncing for fast messaging
@debounce MyApp quick 0

@clear_debounce MyApp quick

# clear all field-specific debounce times
@clear_debounce MyApp
```
"""
macro clear_debounce(M, fieldname)
  fieldname = _prepare(fieldname)
  :(Stipple.debounce($M, $fieldname, nothing)) |> esc
end

macro clear_debounce(expr)
  quote
    if $expr isa DataType && $expr <: Stipple.ReactiveModel
      Stipple.debounce($expr, nothing)
    else
      Stipple.debounce(Stipple.@type(), $(_prepare(expr)), nothing)
    end
  end |> esc
end

macro clear_debounce()
  :(Stipple.debounce(Stipple.@type(), nothing)) |> esc
end

"""
    @throttle fieldname ms

    @throttle App fieldname ms

Set field-specific throttle time in ms.
### Parameters

- `APP`: a subtype of ReactiveModel, e.g. `MyApp`
- `fieldname`: fieldname òr fieldnames as written in the declaration, e.g. `x`, `(x, y, z)`
- `ms`: throttle time in ms

### Example
#### Implicit apps
```
@app begin
  @out quick = 12
  @out slow = 12
  @in s = "Hello"
end

# no throttling for fast messaging
@throttle quick 0

# long throttling for long-running tasks
@throttle (slow1, slow2) 1000
```
#### Explicit apps

```
@app MyApp begin
  @out quick = 12
  @out slow = 12
  @in s = "Hello"
end

# no throttling for fast messaging
@throttle MyApp quick 0

# long throttling for long-running tasks
@throttle MyApp slow 1000
```
"""
macro throttle(M, fieldname, ms)
  fieldname = _prepare(fieldname)
  :(Stipple.throttle($M, $fieldname, $ms)) |> esc
end

macro throttle(fieldname, ms)
  fieldname = _prepare(fieldname)
  :(Stipple.throttle(Stipple.@type(), $fieldname, $ms)) |> esc
end

"""
    @clear_throttle

    @clear_throttle fieldname

    @clear_throttle App

    @clear_throttle App fieldname

Clear field-specific throttle time, for setting see `@throttle`.
After calling `@clear throttle` the field will be throttled by the value given in the
`@init` macro.


### Example
#### Implicit apps
```
@app begin
  @out quick = 12
  @out slow = 12
  @in s = "Hello"
end


# set standard throttle time for all fields
@page("/", ui, model = MyApp, throttle = 100)

# no throttling for fast messaging
@throttle quick 0
@throttle slow 1000

# reset to standard value of the app
@clear_throttle quick

# clear all field-specific throttle times
@clear_throttle
```
#### Explicit apps

```
@app MyApp begin
  @out quick = 12
  @out slow = 12
  @in s = "Hello"
end

# set standard throttle time for all fields
@page("/", ui, model = MyApp, throttle = 100)

# no throttling for fast messaging
@throttle MyApp quick 0

@clear_throttle MyApp quick

# clear all field-specific throttle times
@clear_throttle MyApp
```
"""
macro clear_throttle(M, fieldname)
  fieldname = _prepare(fieldname)
  :(Stipple.throttle($M, $fieldname, nothing)) |> esc
end

macro clear_throttle(expr)
  quote
    if $expr isa DataType && $expr <: Stipple.ReactiveModel
      Stipple.throttle($expr, nothing)
    else
      Stipple.throttle(Stipple.@type(), $(_prepare(expr)), nothing)
    end
  end |> esc
end

macro clear_throttle()
  :(Stipple.throttle(Stipple.@type(), nothing)) |> esc
end

import Stipple: @vars

macro vars(expr)
  modelname = model_typename(__module__)
  quote
    Stipple.ReactiveTools.@vars $modelname $expr
  end |> esc
end

macro model()
  esc(quote
    Stipple.@type() |> Base.invokelatest
  end)
end

# the @in, @out and @private macros below are defined so a docstring can be attached
# the actual macro definition is done in the for loop further down
"""
```julia
@in(expr)
```

Declares a reactive variable that is public and can be written to from the UI.

**Usage**
```julia
@app begin
    @in N = 0
end
```
"""
macro in end

"""
```julia
@out(expr)
```

Declares a reactive variable that is public and readonly.

**Usage**
```julia
@app begin
    @out N = 0
end
```
"""
macro out end

"""
```julia
@private(expr)
```

Declares a non-reactive variable that cannot be accessed by UI code.

**Usage**
```julia
@app begin
    @private N = 0
end
```
"""
macro private end

for (fn, mode) in [(:in, :PUBLIC), (:out, :READONLY), (:jsnfn, :JSFUNCTION), (:private, :PRIVATE), (:readonly, :READONLY), (:public, :PUBLIC)]
  Core.eval(@__MODULE__, quote
    macro $fn(expr)
      expr.args[end] = Expr(:tuple, expr.args[end], $(QuoteNode(mode)))
      expr |> esc
    end

  end)
end

export @in, @out, @jsnfn, @private, @readonly, @public

"""
```julia
@app(expr)
```

Sets up and enables the reactive variables and code provided in the expression `expr`.

**Usage**

The code block passed to @app implements the app's logic, handling the states of the UI components and the code that is executed when these states are altered.

```julia
@app begin
   # reactive variables
   @in N = 0
   @out result = 0
   # reactive code to be executed when N changes
   @onchange N begin
     result = 10*N
   end
end
```
"""
macro app(expr = Expr(:block))
  modelname = model_typename(__module__)
  quote
    Stipple.ReactiveTools.@app $modelname $expr __GF_AUTO_HANDLERS__
    $modelname
  end |> esc
end

#===#

"""
        @init(kwargs...)

Create a new app with the following kwargs supported:
- `debounce::Int = JS_DEBOUNCE_TIME`
- `throttle::Int = JS_THROTTLE_TIME`
- `transport::Module = Genie.WebChannels`
- `core_theme::Bool = true`

### Example
```
@app begin
  @in n = 10
  @out s = "Hello"
end

model = @init(debounce = 50)
```
------------

        @init(App, kwargs...)

Create a new app of type `App` with the same kwargs as above

### Example

```
@app MyApp begin
  @in n = 10
  @out s = "Hello"
end

model = @init(MyApp, debounce = 50)
```
"""
macro init(args...)
  init_args = Stipple.expressions_to_args(args)

  type_pos = findfirst(x -> !isa(x, Expr) || x.head ∉ (:kw, :parameters), init_args)
  called_without_type = isnothing(type_pos)

  if called_without_type
    typename = model_typename(__module__)
    insert!(init_args, Stipple.has_parameters(init_args) ? 2 : 1, typename)
  end

  quote
    Stipple.ReactiveTools.init_model($(init_args...))
  end |> esc
end

function init_model(M::Type{<:ReactiveModel}, args...; kwargs...)
  m = __module__ = parentmodule(M)

  initfn = begin
    if Stipple.use_model_storage() && __module__ === Stipple
      Stipple.ModelStorage.Sessions.init_from_storage
    elseif isdefined(__module__, :Stipple) && isdefined(__module__.Stipple, :ModelStorage) &&
      isdefined(__module__.Stipple.ModelStorage, :Sessions) &&
        isdefined(__module__.Stipple.ModelStorage.Sessions, :init_from_storage) &&
          Stipple.use_model_storage()
      __module__.Stipple.ModelStorage.Sessions.init_from_storage
    elseif isdefined(__module__, :init_from_storage) && Stipple.use_model_storage()
      __module__.init_from_storage
    else
      Stipple.init
    end
  end

  model = initfn(M, args...; kwargs...)
  for h in model.handlers__
    model |> h
  end

  # Update the model in all pages where it has been set as instance of an app.
  # Where it has been set as ReactiveModel type, no change is required
  for p in Stipple.Pages._pages
    p.context == m && p.model isa M && (p.model = model)
  end
  model
end

function init_model(m::Module, args...; kwargs...)
  init_model(@eval(m, Stipple.@type), args...; kwargs...)
end

macro app(typename, expr, handlers_fn_name = Symbol(typename, :_handlers), mixin = false)
  :(Stipple.ReactiveTools.@handlers $typename $expr $handlers_fn_name $mixin) |> esc
end

macro app_mixin(typename, expr, handlers_fn_name = Symbol(typename, :_handlers))
  :(Stipple.ReactiveTools.@handlers $typename $expr $handlers_fn_name true) |> esc
end

macro handlers()
  modelname = model_typename(__module__)
  empty_block = Expr(:block)
  quote
    Stipple.ReactiveTools.@handlers $modelname $empty_block __GF_AUTO_HANDLERS__
  end |> esc
end

macro handlers(expr)
  modelname = model_typename(__module__)
  quote
    Stipple.ReactiveTools.@handlers $modelname $expr __GF_AUTO_HANDLERS__
  end |> esc
end

macro handlers(typename, expr, handlers_fn_name = Symbol(typename, :_handlers), mixin = false)
  expr = wrap(expr, :block)
  i_start = 1
  handlercode = []
  initcode = []

  for (i, ex) in enumerate(expr.args)
    if ex isa Expr
      if ex.head == :macrocall && ex.args[1] in Symbol.(["@onbutton", "@onchange"])
        ex_index = .! isa.(ex.args, LineNumberNode)
        if sum(ex_index) < 4
          pos = findall(ex_index)[2]
          insert!(ex.args, pos, :__storage__)
        end
        push!(handlercode, expr.args[i_start:i]...)
      else
        push!(initcode, ex)
      end
      i_start = i + 1
    end
  end

  initcode_expr = macroexpand(__module__, Expr(:block, initcode...)) |> MacroTools.flatten

  # if no initcode is provided and typename is already defined, don't overwrite the existing type and just declare the handlers function
  storage = @eval __module__ Stipple.@var_storage($initcode_expr, $handlers_fn_name)
  initcode_final = isempty(initcode) && isdefined(__module__, typename) ? Expr(:block) : :(Stipple.@type($typename, $storage))
  
  handlercode_final = []
  varnames = setdiff(collect(keys(storage)), Stipple.INTERNALFIELDS)
  d = LittleDict(varnames .=> varnames)
  d_expr = :($d)
  for ex in handlercode
    if ex isa Expr
      replace!(ex.args, :__storage__ => d_expr)
      push!(handlercode_final, @eval(__module__, $ex))
    else
      push!(handlercode_final, ex)
    end
  end

  # println("initcode: ", initcode)
  # println("initcode_final: ", initcode_final)
  # println("handlercode: ", handlercode)
  # println("handlercode_final: ", handlercode_final)

  handlers_expr_name = Symbol(typename, :var"!_handlers_expr")
  handlercode_qn = QuoteNode(handlercode_final)

  expr = quote
    $(initcode_final)
    Stipple.ReactiveTools.delete_events($typename)

    function $handlers_fn_name(__model__)
      $(handlercode_final...)

      __model__
    end
    ($typename, $handlers_fn_name)
  end
  
  mixin === :true && insert!(expr.args, lastindex(expr.args), :($handlers_expr_name = $handlercode_qn))
  
  expr |> esc
end

function wrap(expr, wrapper = nothing)
  if wrapper !== nothing && (! isa(expr, Expr) || expr.head != wrapper)
    Expr(wrapper, expr)
  else
    expr
  end
end

function transform(expr, vars::Vector{Symbol}, test_fn::Function, replace_fn::Function)
  replaced_vars = Symbol[]
  ex = postwalk(expr) do x
      if x isa Expr
        if x.head == :call
          f = x
          while f.args[1] isa Expr && f.args[1].head == :ref
            f = f.args[1]
          end
          if f.args[1] isa Symbol && test_fn(f.args[1])
            union!(push!(replaced_vars, f.args[1]))
            f.args[1] = replace_fn(f.args[1])
          end
          if x.args[1] == :notify && length(x.args) == 2
            if @capture(x.args[2], __model__.fieldname_[])
              x.args[2] = :(__model__.$fieldname)
            elseif x.args[2] isa Symbol
              x.args[2] = :(__model__.$(x.args[2]))
            end
          end
        elseif x.head == :kw && test_fn(x.args[1])
          x.args[1] = replace_fn(x.args[1])
        elseif x.head == :parameters
          for (i, a) in enumerate(x.args)
            if a isa Symbol && test_fn(a)
              new_a = replace_fn(a)
              x.args[i] = new_a in vars ? :($(Expr(:kw, new_a, :(__model__.$new_a[])))) : new_a
            end
          end
        elseif x.head == :ref && length(x.args) >= 2 || x.head == :.
            # if model field is indexed by at least one index argument or if a property is referenced
            # remove [] after __model__, because getindex, setindex!, getproperty, and setproperty!
            # handle Reactive vars correctly and call notify after the update in case of set routines
            @capture(x.args[1], __model__.fieldname_[]) && (x.args[1] = :(__model__.$fieldname))
        elseif x.head == :macrocall && x.args[1] ∈ (Symbol("@push"), Symbol("@push!"), Symbol("@run"))
          head = x.args[1] == Symbol("@push") ? :push! : Symbol(String(x.args[1])[2:end])
          args = filter(x -> !isa(x, LineNumberNode), x.args[2:end])
          has_params = length(args) > 0 && args[1] isa Expr && args[1].head == :parameters
          args = has_params ? vcat([head, args[1]], :__model__, args[2:end]) : vcat([head, :__model__], args)
          x = Expr(:call)
          x.args = Stipple.expressions_to_args(args)
        elseif x.head == :(=) && x.args[1] isa Expr && x.args[1].head == :macrocall && x.args[1].args[1] == Symbol("@js_str")
          x.args[1] = :(__model__[$(x.args[1].args[end])])
        end
      end
      x
  end
  ex, replaced_vars
end

mask(expr, vars::Vector{Symbol}) = transform(expr, vars, in(vars), x -> Symbol("_mask_$x"))
unmask(expr, vars = Symbol[]) = transform(expr, vars, x -> startswith(string(x), "_mask_"), x -> Symbol(string(x)[7:end]))[1]

function fieldnames_to_fields(expr, vars)
  postwalk(expr) do x
    x isa Symbol && x ∈ vars ? :(__model__.$x) : x
  end
end

function fieldnames_to_fields(expr, vars, replace_vars)
  postwalk(expr) do x
    if x isa Symbol
      x ∈ replace_vars && return :(__model__.$x)
    elseif x isa Expr
      if x.head == Symbol("=")
        x.args[1] = postwalk(x.args[1]) do y
          y ∈ vars ? :(__model__.$y) : y
        end
      end
    end
    x
  end
end

function fieldnames_to_fieldcontent(expr, vars)
  postwalk(expr) do x
    x isa Symbol && x ∈ vars ? :(__model__.$x[]) : x
  end
end

function fieldnames_to_fieldcontent(expr, vars, replace_vars)
  postwalk(expr) do x
    if x isa Symbol
      x ∈ replace_vars && return :(__model__.$x[])
    elseif x isa Expr
      if x.head == Symbol("=")
        x.args[1] = postwalk(x.args[1]) do y
          y ∈ vars ? :(__model__.$y[]) : y
        end
      end
    end
    x
  end
end

function get_known_vars(M::Module)
  modeltype = @eval M Stipple.@type
  get_known_vars(modeltype)
end

function get_known_vars(storage::LittleDict)
  reactive_vars = Symbol[]
  non_reactive_vars = Symbol[]
  for (k, v) in storage
    k in Stipple.INTERNALFIELDS && continue
    is_reactive = v isa Symbol ? true : startswith(string(Stipple.split_expr(v)[2]), r"(Stipple\.)?R(eactive)?($|{)")
    push!(is_reactive ? reactive_vars : non_reactive_vars, k)
  end
  reactive_vars, non_reactive_vars
end

function get_known_vars(::Type{M}) where M<:ReactiveModel
  CM = Stipple.get_concrete_type(M)
  reactive_vars = Symbol[]
  non_reactive_vars = Symbol[]
  for (k, v) in zip(fieldnames(CM), fieldtypes(CM))
    k in Stipple.INTERNALFIELDS && continue
    push!(v <: Reactive ? reactive_vars : non_reactive_vars, k)
  end
  reactive_vars, non_reactive_vars
end

"""
```julia
@onchange(var, expr)
```
Declares a reactive update such that when a reactive variable changes `expr` is executed.

**Usage**

This macro watches a list of variables and defines a code block that is executed when the variables change.

```julia
@app begin
    # reactive variables taking their value from the UI
    @in N = 0
    @in M = 0
    @out result = 0
    # reactive code to be executed when N changes
    @onchange N, M begin
        result = 10*N*M
    end
end
```

"""
macro onchange(var, expr)
  quote
    @onchange $__module__ $var $expr
  end |> esc
end

macro onchange(location, vars, expr)
  loc::Union{Module, Type{<:ReactiveModel}, LittleDict} = @eval __module__ $location
  vars = wrap(vars, :tuple)

  if expr isa Expr && expr.head == :call && length(expr.args) == 1
    push!(expr.args, :__model__)
  end
  expr = wrap(expr, :block)

  known_reactive_vars, known_non_reactive_vars = get_known_vars(loc)
  known_vars = vcat(known_reactive_vars, known_non_reactive_vars)
  on_vars = fieldnames_to_fields(vars, known_vars)

  expr, used_vars = mask(expr, known_vars)

  expr = fieldnames_to_fields(expr, known_non_reactive_vars)
  expr = fieldnames_to_fieldcontent(expr, known_reactive_vars)
  expr = unmask(expr, vcat(known_reactive_vars, known_non_reactive_vars))

  fn = length(vars.args) == 1 ? :on : :onany
  :($fn($(on_vars.args...)) do _...
        $(expr.args...)
    end
  ) |> QuoteNode
end

macro onchangeany(var, expr)
  quote
    @warn("The macro `@onchangeany` is deprecated and should be replaced by `@onchange`")
    @onchange $vars $expr
  end |> esc
end

"""
```julia
@onbutton
```
Declares a reactive update that executes `expr` when a button is pressed in the UI.

**Usage**
Define a click event listener with `@click`, and the handler with `@onbutton`.

```julia
@app begin
    @in press = false
    @onbutton press begin
        println("Button presed!")
    end
end

ui() = btn("Press me", @click(:press))

@page("/", ui)
```


"""
macro onbutton(var, expr)
  quote
    @onbutton $__module__ $var $expr
  end |> esc
end

macro onbutton(location, var, expr)
  loc::Union{Module, Type{<:ReactiveModel}, LittleDict} = @eval __module__ $location
  if expr isa Expr && expr.head == :call && length(expr.args) == 1
    push!(expr.args, :__model__)
  end
  expr = wrap(expr, :block)

  known_reactive_vars, known_non_reactive_vars = get_known_vars(loc)
  known_vars = vcat(known_reactive_vars, known_non_reactive_vars)
  var = fieldnames_to_fields(var, known_vars)

  expr, used_vars = mask(expr, known_vars)

  expr = fieldnames_to_fields(expr, known_non_reactive_vars)
  expr = fieldnames_to_fieldcontent(expr, known_reactive_vars)
  expr = unmask(expr, known_vars)

  :(onbutton($var) do
    $(expr.args...)
  end) |> QuoteNode
end

"""
    @handler App expr

Defines a handler function that can be called from within a ReactiveModel App, if not present, the macro will add the variable `__model__` as the first argument.

Parameters:
  - `App`: either
    - a ReactiveModel (e.g. `MyApp`)
    - a list of reactive variables (e.g. `(:r1, :r2)`)
    - a tuple or vector of a list of reactive variables and a list of non-reactive variables (e.g. `((:r,), (:nr,))`)
  - `expr`: function definition, e.g. `function my_handler() println("n: \$n") end`

### Example 1

```julia
@app MyApp begin
  @in i = 0
  @onchange i on_i()
    println("Hello World")
  end
end

@handler MyApp function on_i()
  println("i: \$i")
end
```

### Example 2

```julia-repl
julia> @macroexpand @handler (:a,) function f() a end
quote
    function f(__model__)
        model.a[]
    end
end

julia> @macroexpand @handler ((:a,), (:b,)) function f(x, __model__) a, b end
quote
    function f(x, __model__)
        (__model__.a[], __model__.b)
    end
end
```
"""
macro handler(location, expr)
  location! = Symbol(location, '!')
  
  loc = @eval __module__ $location
  known_reactive_vars, known_non_reactive_vars = if loc isa Union{Module, Type{<:ReactiveModel}, LittleDict}
    Stipple.ReactiveTools.get_known_vars(loc)
  else
    location! = nothing
    loc = if isempty(loc)
      Symbol[], Symbol[]
    else
      if loc[1] isa Union{Vector, Tuple}
        length(loc) == 1 ? (collect(loc[1]), Symbol[]) : (collect(loc[1]), collect(loc[2]))
      else
        collect(loc), Symbol[]
      end
    end
  end
  known_vars = vcat(known_reactive_vars, known_non_reactive_vars)

  f_expr = expr.args[1]
  f_args = f_expr.args
  functionname = f_args[1]
  
  # add __model__ as first argument if not present
  pos = length(f_args) > 1 && f_args[2] isa Expr && f_args[2].head == :parameters ? 3 : 2
  :__model__ ∉ f_args[2:end] && insert!(f_args, pos, :__model__)

  body = Expr(:block, expr.args[2].args...)
  body, _ = ReactiveTools.mask(body, known_vars)
  body = fieldnames_to_fields(body, known_non_reactive_vars)
  body = fieldnames_to_fieldcontent(body, known_reactive_vars)
  body = unmask(body, vcat(known_reactive_vars, known_non_reactive_vars))

  expr.args[2] = body

  output = quote
    $expr
  end

  # add precompilation statement if the function has only one argument
  if length(f_args) == 2 && location! !== nothing
    precompile_expr = quote
      precompile($functionname, ($location!,))
      $functionname
    end
    push!(output.args, precompile_expr.args...)
  end
  output |> esc
end

macro handler(expr)
  location = model_typename(__module__)
  :(@handler $location $expr) |> esc
end

#===#

"""
```julia
@page(url, view)
```
Registers a new page with source in `view` to be rendered at the route `url`.

**Usage**

```julia
@page("/", "view.html")

@page("/", ui; model = MyApp) # for specifying an explicit app
```
"""
macro page(expressions...)
    # for macros to support semicolon parameter syntax it's required to have no positional arguments in the definition
    # therefore find indexes of positional arguments by hand
    inds = findall(x -> !isa(x, Expr) || x.head ∉ (:parameters, :(=)), expressions)
    length(inds) < 2 && throw("Positional arguments 'url' and 'view' required!")
    url, view = expressions[inds[1:2]]
    kwarg_inds = setdiff(1:length(expressions), inds)
    args = Stipple.expressions_to_args(
        expressions[kwarg_inds];
        args_to_kwargs = [:layout, :model, :context],
        defaults = Dict(
            :layout => Stipple.ReactiveTools.DEFAULT_LAYOUT(),
            :context => __module__,
            :model => __module__
        )
    )
    model_parent, model_ind, model_expr = Stipple.locate_kwarg(args, :model)
    model = @eval(__module__, $model_expr)

    if model isa Module
      # the next lines are added for backward compatibility
      # if the app is programmed according to the latest API,
      # eval will not be called; will e removed in the future
      typename = model_typename(__module__)
      if !isdefined(__module__, typename)
        @warn "App not yet defined, this is strongly discouraged, please define an app first"
        @eval(__module__, @app)
      end
    end

    :(Stipple.Pages.Page($(args...), $url, view = $view)) |> esc
end

function __init()
  for f in (:methods, :watch, :computed)
    f_str = string(f)
    Core.eval(@__MODULE__, quote
      """
          @$($f_str)(expr)
          @$($f_str)(App, expr)

      Defines js functions for the `$($f_str)` section of the vue element.

      `expr` can be
      - `String` containing javascript code
      - `Pair` of function name and function code
      - `Function` returning String of javascript code
      - `Dict` of function names and function code
      - `Vector` of the above

      ### Example 1

      ```julia
      @$($f_str) "greet: function(name) {console.log('Hello ' + name)}"
      ```

      ### Example 2

      ```julia
      js_greet() = :greet => "function(name) {console.log('Hello ' + name)}"
      js_bye() = :bye => "function() {console.log('Bye!')}"
      @$($f_str) MyApp [js_greet, js_bye]
      ```
      Checking the result can be done in the following way
      ```
      julia> render(MyApp())[:$($f_str)].s |> println
      {
          "greet":function(name) {console.log('Hello ' + name)},
          "bye":function() {console.log('Bye!')}
      }
      ```
      """
      macro $f(args...)
        vue_options($f_str, args...)
      end
    end)
  end

  #=== Lifecycle hooks ===#

  for (f, field) in (
    (:before_create, :beforeCreate), (:created, :created), (:before_mount, :beforeMount), (:mounted, :mounted),
    (:before_update, :beforeUpdate), (:updated, :updated), (:activated, :activated), (:deactivated, :deactivated),
    (:before_destroy, :beforeDestroy), (:destroyed, :destroyed), (:error_captured, :errorCaptured),)

    f_str = string(f)
    field_str = string(field)
    Core.eval(@__MODULE__, quote
      """
          @$($f_str)(expr)

      Defines js statements for the `$($field_str)` section of the vue element.

      expr can be
        - `String` containing javascript code
        - `Function` returning String of javascript code
        - `Vector` of the above

      ### Example 1

      ```julia
      @$($f_str) \"\"\"
          if (this.cameraon) { startcamera() }
      \"\"\"
      ```

      ### Example 2

      ```julia
      startcamera() = "if (this.cameraon) { startcamera() }"
      stopcamera() = "if (this.cameraon) { stopcamera() }"

      @$($f_str) MyApp [startcamera, stopcamera]
      ```
      Checking the result can be done in the following way
      ```
      julia> render(MyApp())[:$($field_str)]
      JSONText("function(){\n    if (this.cameraon) { startcamera() }\n\n    if (this.cameraon) { stopcamera() }\n}")
      ```
      """
      macro $f(args...)
        vue_options($f_str, args...)
      end
    end)
  end
end

#=== Lifecycle hooks ===#

function vue_options(hook_type, args...)
  if length(args) == 1
    expr = args[1]
    quote
      let M = Stipple.@type
        Stipple.$(Symbol("js_$hook_type"))(::M) = $expr
      end
    end |> esc
  elseif length(args) == 2
    T, expr = args[1], args[2]
    esc(:(Stipple.$(Symbol("js_$hook_type"))(::$T) = $expr))
  else
    error("Invalid number of arguments for vue options")
  end
end

macro event(M, eventname, expr)
  known_reactive_vars, known_non_reactive_vars = get_known_vars(@eval(__module__, $M))
  known_vars = vcat(known_reactive_vars, known_non_reactive_vars)
  expr, used_vars = mask(expr, known_vars)

  expr = fieldnames_to_fields(expr, known_non_reactive_vars)
  expr = fieldnames_to_fieldcontent(expr, known_reactive_vars)
  expr = unmask(expr, known_vars)

  expr = unmask(fieldnames_to_fieldcontent(expr, known_vars), known_vars)
  T = eventname isa QuoteNode ? eventname : QuoteNode(eventname)

  quote
    function Base.notify(__model__::$M, ::Val{$T}, @nospecialize(event))
        $expr
    end
  end |> esc
end

"""
```julia
@event(event, expr)
```
Executes the code in `expr` when a specific `event` is triggered by a UI component.

**Usage**

Define an event trigger such as a click, keypress or file upload for a component using the @on macro.
Then, define the handler for the event with @event.


**Examples**

Keypress:


```julia
@app begin
    @event :keypress begin
        println("The Enter key has been pressed")
    end
end

ui() =  textfield(class = "q-my-md", "Input", :input, hint = "Please enter some words", @on("keyup.enter", :keypress))

@page("/", ui)
```

=======

```julia
<q-input hint="Please enter some words" v-on:keyup.enter="function(event) { handle_event(event, 'keypress') }" label="Input" v-model="input" class="q-my-md"></q-input>
```
File upload:

```julia
@app begin
    @event :uploaded begin
        println("Files have been uploaded!")
    end
end

ui() = uploader("Upload files", url = "/upload" , method="POST", @on(:uploaded, :uploaded), autoupload=true)

route("/upload", method=POST) do
    # process uploaded files
end

@page("/", ui)
```

```julia
julia> print(ui())
<q-uploader url="/upload" method="POST" auto-upload v-on:uploaded="function(event) { handle_event(event, 'uploaded') }">Upload files</q-uploader>
```
"""
macro event(event, expr)
  quote
    @event Stipple.@type() $event $expr
  end |> esc
end


macro client_data(expr)
  if expr.head != :block
    expr = quote $expr end
  end

  output = :(Stipple.client_data())
  for e in expr.args
    e isa LineNumberNode && continue
    e.head = :kw
    push!(output.args, e)
  end

  esc(quote
    let M = Stipple.@type
      Stipple.client_data(::M) = $output
    end
  end)
end

macro client_data(M, expr)
  if expr.head != :block
    expr = quote $expr end
  end

  output = :(Stipple.client_data())
  for e in expr.args
    e isa LineNumberNode && continue
    e.head = :kw
    push!(output.args, e)
  end

  :(Stipple.client_data(::$(esc(M))) = $(esc(output)))
end

macro add_client_data(expr)
  if expr.head != :block
    expr = quote $expr end
  end

  output = :(Stipple.client_data())
  for e in expr.args
    e isa LineNumberNode && continue
    e.head = :kw
    push!(output.args, e)
  end

  esc(quote
    let M = Stipple.@type
      cd_old = Stipple.client_data(M())
      cd_new = $output
      Stipple.client_data(::M) = merge(d1, d2)
    end
  end)
end

macro notify(args...)
  for arg in args
    arg isa Expr && arg.head == :(=) && (arg.head = :kw)
  end

  quote
    Base.notify(__model__, $(args...))
  end |> esc
end

__init()

macro modelstorage()
  quote
    using Stipple.ModelStorage.Sessions
  end |> esc
end

"""
  @deps f


Add a function f to the dependencies of the current app.

------------------------

  @deps M::Module


Add the dependencies of the module M to the dependencies of the current app.
"""
macro deps(expr)
  quote
    Stipple.deps!(Stipple.@type(), $expr)
  end |> esc
end

"""
  @deps(MyApp::ReactiveModel, f::Function)


Add a function f to the dependencies of the app MyApp.
The module needs to define a function `deps()`.

------------------------

  @deps(MyApp::ReactiveModel, M::Module)


Add the dependencies of the module M to the dependencies of the app MyApp.
The module needs to define a function `deps()`.
"""
macro deps(M, expr)
  quote
    Stipple.deps!($M, $expr)
  end |> esc
end

"""
  @clear_deps


Delete all dependencies of the current app.

------------------------

  @clear_deps MyApp


Delete all dependencies of the app MyApp.
"""
macro clear_deps()
  quote
    Stipple.clear_deps!(Stipple.@type())
  end |> esc
end

macro clear_deps(M)
  quote
    Stipple.clear_deps!($M)
  end |> esc
end

end
