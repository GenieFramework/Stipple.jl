mutable struct Reactive{T} <: Observables.AbstractObservable{T}
  o::Observables.Observable{T}
  r_mode::Int
  no_backend_watcher::Bool
  no_frontend_watcher::Bool
  __source__::String

  Reactive{T}() where {T} = new{T}(Observable{T}(), PUBLIC, false, false, "")
  Reactive{T}(o, no_bw::Bool = false, no_fw::Bool = false) where {T} = new{T}(o, PUBLIC, no_bw, no_fw, "")
  Reactive{T}(o, mode::Int, no_bw::Bool = false, no_fw::Bool = false) where {T} = new{T}(o, mode, no_bw, no_fw, "")
  Reactive{T}(o, mode::Int, no_bw::Bool, no_fw::Bool, s::AbstractString) where {T} = new{T}(o, mode, no_bw, no_fw, s)
  Reactive{T}(o, mode::Int, updatemode::Int) where {T} = new{T}(o, mode, updatemode & NO_BACKEND_WATCHER != 0, updatemode & NO_FRONTEND_WATCHER != 0, "")

  # Construct an Reactive{Any} without runtime dispatch
  Reactive{Any}(@nospecialize(o)) = new{Any}(Observable{Any}(o), PUBLIC, false, false, "")
end

Reactive(r::T, arg1, args...) where T = convert(Reactive{T}, (r, arg1, args...))
Reactive(r::T) where T = convert(Reactive{T}, r)

Base.convert(::Type{T}, x::T) where {T<:Reactive} = x  # resolves ambiguity with convert(::Type{T}, x::T) in base/essentials.jl
Base.convert(::Type{T}, x) where {T<:Reactive} = T(x)

Base.convert(::Type{Reactive}, (r, m)::Tuple{T,Int}) where T = m < 16 ? Reactive{T}(Observable(r), m, PUBLIC) : Reactive{T}(Observable(r), PUBLIC, m)

Base.convert(::Type{Reactive{T}}, (r, m)::Tuple{T, Int}) where T = m < 16 ? Reactive{T}(Observable(r), m, PUBLIC) : Reactive{T}(Observable(r), PUBLIC, m)
Base.convert(::Type{Reactive{T}}, (r, w)::Tuple{T, Bool}) where T = Reactive{T}(Observable(r), PUBLIC, w, false, "")
Base.convert(::Type{Reactive{T}}, (r, m, nw)::Tuple{T, Int, Bool}) where T = Reactive{T}(Observable(r), m, nw, false, "")
Base.convert(::Type{Reactive{T}}, (r, nbw, nfw)::Tuple{T, Bool, Bool}) where T = Reactive{T}(Observable(r), PUBLIC, nbw, nfw, "")
Base.convert(::Type{Reactive{T}}, (r, m, nbw, nfw)::Tuple{T, Int, Bool, Bool}) where T = Reactive{T}(Observable(r), m, nbw, nfw, "")
Base.convert(::Type{Reactive{T}}, (r, m, nbw, nfw, s)::Tuple{T, Int, Bool, Bool, String}) where T = Reactive{T}(Observable(r), m, nbw, nfw, s)
Base.convert(::Type{Reactive{T}}, (r, m, u)::Tuple{T, Int, Int}) where T = Reactive{T}(Observable(r), m, u)
Base.convert(::Type{Observable{T}}, r::Reactive{T}) where T = getfield(r, :o)

Base.getindex(r::Reactive{T}) where T = Base.getindex(getfield(r, :o))
Base.setindex!(r::Reactive{T}) where T = Base.setindex!(getfield(r, :o))

# pass indexing and property methods to referenced variable
function Base.getindex(r::Reactive{T}, arg1, args...) where T
  getindex(getfield(r, :o).val, arg1, args...)
end

function Base.setindex!(r::Reactive{T}, val, arg1, args...) where T
  setindex!(getfield(r, :o).val, val, arg1, args...)
  notify(r)
end

Base.setindex!(r::Reactive, val, ::typeof(!)) = getfield(r, :o).val = val
Base.getindex(r::Reactive, ::typeof(!)) = getfield(r, :o).val

function Base.getproperty(r::Reactive{T}, field::Symbol) where T
  if field in (:o, :r_mode, :no_backend_watcher, :no_frontend_watcher, :__source__) # fieldnames(Reactive)
    getfield(r, field)
  else
    if field == :val
      @warn """Reactive API has changed, use "[]" instead of ".val"!"""
      getfield(r, :o).val
    else
      getproperty(getfield(r, :o).val, field)
    end
  end
end

function Base.setproperty!(r::Reactive{T}, field::Symbol, val) where T
  if field in fieldnames(Reactive)
    setfield!(r, field, val)
  else
    if field == :val
      @warn """Reactive API has changed, use "setfield_withoutwatchers!() or o.val" instead of ".val"!"""
      getfield(r, :o).val = val
    else
      setproperty!(getfield(r, :o).val, field, val)
      notify(r)
    end
  end
end

function Base.hash(r::T) where {T<:Reactive}
  hash((( getfield(r, f) for f in fieldnames(typeof(r)) ) |> collect |> Tuple))
end

function Base.:(==)(a::T, b::R) where {T<:Reactive,R<:Reactive}
  hash(a) == hash(b)
end

Observables.observe(r::Reactive{T}, args...; kwargs...) where T = Observables.observe(getfield(r, :o), args...; kwargs...)
Observables.listeners(r::Reactive{T}, args...; kwargs...) where T = Observables.listeners(getfield(r, :o), args...; kwargs...)

@static if isdefined(Observables, :appendinputs!)
    Observables.appendinputs!(r::Reactive{T}, obsfuncs) where T = Observables.appendinputs!(getfield(r, :o), obsfuncs)
end

import Base.map!
@inline Base.map!(f::F, r::Reactive, os...; update::Bool=true) where F = Base.map!(f::F, getfield(r, :o), os...; update=update)

const R = Reactive
const PUBLIC = 1
const PRIVATE = 2
const READONLY = 4
const JSFUNCTION = 8
const NO_BACKEND_WATCHER = 16
const NO_FRONTEND_WATCHER = 32
const NO_WATCHER = 48
const NON_REACTIVE = 64

"""
    type ReactiveModel

The abstract type that is inherited by Stipple models. Stipple models are used for automatic 2-way data sync and data
exchange between the Julia backend and the JavaScript/Vue.js frontend.

### Example

```julia
Base.@kwdef mutable struct HelloPie <: ReactiveModel
  plot_options::R{PlotOptions} = PlotOptions(chart_type=:pie, chart_width=380, chart_animations_enabled=true,
                                            stroke_show = false, labels=["Slice A", "Slice B"])
  piechart::R{Vector{Int}} = [44, 55]
  values::R{String} = join(piechart, ",")
end
```
"""
abstract type ReactiveModel end


export @reactors, @reactive, @reactive!, @vars, @add_vars, @old_reactive, @old_reactive!
export ChannelName, getchannel

const ChannelName = String
const CHANNELFIELDNAME = :channel__

function getchannel(m::M) where {M<:ReactiveModel}
  getfield(m, CHANNELFIELDNAME)
end


function setchannel(m::M, value) where {M<:ReactiveModel}
  setfield!(m, CHANNELFIELDNAME, ChannelName(value))
end

const AUTOFIELDS = [:isready, :isprocessing, :_modes] # not DRY but we need a reference to the auto-set fields

@pour reactors begin
  _modes::LittleDict{Symbol, Int} = LittleDict(:_modes => PRIVATE, :channel__ => PRIVATE)
  channel__::Stipple.ChannelName = Stipple.channelfactory()
  isready::Stipple.R{Bool} = false
  isprocessing::Stipple.R{Bool} = false
end

@mix Stipple.@with_kw mutable struct old_reactive
  Stipple.@reactors
end


@mix Stipple.@kwredef mutable struct old_reactive!
  Stipple.@reactors
end

function split_expr(expr)
  expr.args[1] isa Symbol ? (expr.args[1], nothing, expr.args[2]) : (expr.args[1].args[1], expr.args[1].args[2], expr.args[2])
end

function model_to_storage(::Type{M_init}) where M_init <: ReactiveModel
  M = get_concrete_model(M_init)
  fields = fieldnames(M)
  values = getfield.(Ref(M()), fields)
  storage = LittleDict{Symbol, Expr}()
  for (f, type, v) in zip(fields, fieldtypes(M), values)
    v_copy = Stipple._deepcopy(v)
    storage[f] = v isa Symbol ? :($f::$type = $(QuoteNode(v))) : :($f::$type = $v_copy)
  end

  storage
end

macro var_storage(expr, new_inputmode = :auto)
  m = __module__
  if expr.head != :block
      expr = quote $expr end
  end

  if new_inputmode == :auto
    new_inputmode = true
    for e in expr.args
        e isa LineNumberNode && continue
        e.args[1] isa Symbol && continue

        type = e.args[1].args[2]
        if startswith(string(type), r"(Stipple\.)?R(eactive)?($|{)")
            new_inputmode = false
            break
        end
    end
  end

  storage = init_storage()
  
  source = nothing
  for e in expr.args
      if e isa LineNumberNode
          source = e
          continue
      end
      mode = :PUBLIC
      reactive = true
      var, ex = if new_inputmode
          #check whether flags are set
          if e.args[end] isa Expr && e.args[end].head == :tuple
              flags = e.args[end].args[2:end]
              if length(flags) > 0 && flags[1] ∈ [:READONLY, :PRIVATE, :JSFUNCTION, :NON_REACTIVE]
                  newmode = intersect(setdiff(flags, [:NON_REACTIVE]), [:READONLY, :PRIVATE, :JSFUNCTION])
                  length(newmode) > 0 && (mode = newmode[end])
                  reactive = :NON_REACTIVE ∉ flags
                  e.args[end] = e.args[end].args[1]
              end
          end
          var, ex = Stipple.ReactiveTools.parse_expression!(e, reactive ? mode : nothing, source, m)
      else
          var = e.args[1]
          if var isa Symbol
              reactive = false
          else
              type = var.args[2]
              reactive = startswith(string(type), r"(Stipple\.)?R(eactive)?($|{)")
              var = var.args[1]
          end
          if occursin(Stipple.SETTINGS.private_pattern, string(var))
              mode = :PRIVATE
          elseif occursin(Stipple.SETTINGS.readonly_pattern, string(var))
              mode = :READONLY
          end
          var, e
      end
      # prevent overwriting of control fields
      var in Stipple.AUTOFIELDS && continue
      if reactive == false
          Stipple.setmode!(storage[:_modes], Core.eval(Stipple, mode), var)
      end

      storage[var] = ex
    end

    esc(:($storage))
end

macro type(modelname, storage)
  modelconst = Symbol(modelname, '!')
  output = @eval(__module__, values($storage))
  esc(quote
      abstract type $modelname <: Stipple.ReactiveModel end
      Stipple.@kwredef mutable struct $modelconst <: $modelname
          $(output...)
      end

      delete!.(Ref(Stipple.DEPS), filter(x -> x isa Type && x <: $modelname, keys(Stipple.DEPS)))
      Stipple.Genie.Router.delete!(Symbol(Stipple.routename($modelname)))
      
      $modelconst
  end)
end

"""
`@vars(expr)`
```
@vars MyDashboard begin
  a::Int = 1
  b::Float64 = 2
  c::String = "Hello"
  d::String = "readonly", NON_REACTIVE, READONLY
  e::String = "private",  NON_REACTIVE, PRIVATE
end
```
This macro replaces the old `@reactive!` and doesn't need the Reactive in the declaration.
Instead the non_reactives are marked by a flag. The old declaration syntax is still supported
to make adaptation of old code easier. 
```
@vars HHModel begin
  a::R{Int} = 1
  b::R{Float64} = 2
  c::String = "Hello"
  d_::String = "readonly"
  e__::String = "private"
end
```
by

```julia
@reactive! mutual struct HHModel <: ReactiveModel
  a::R{Int} = 1
  b::R{Float64} = 2
  c::String = "Hello"
  d_::String = "readonly"
  e__::String = "private"
end
```

Old syntax is still supported by @vars and can be forced by the `new_inputmode` argument.

"""
macro vars(modelname, expr, new_inputmode = :auto)
  modelconst = Symbol(modelname, '!')
  storage = @eval(__module__, values(Stipple.@var_storage($expr, $new_inputmode)))

  esc(:(Stipple.@type $modelname $storage))
end

macro add_vars(modelname, expr, new_inputmode = :auto)
  modelconst = Symbol(modelname, '!')

  storage = @eval(__module__, Stipple.@var_storage($expr, $new_inputmode))
  new_storage = if isdefined(__module__, modelname)
    old_storage = @eval(__module__, Stipple.model_to_storage($modelname))
    ReactiveTools.merge_storage(old_storage, storage)
  else
    storage
  end
    
  esc(:(Stipple.@type $modelname $new_storage))
end

macro reactive!(expr)
  warning = """@reactive! is deprecated, please replace use `@vars` instead.
  
  In case of errors, please replace `@reactive!` by `@old_reactive!` and open an issue at
  https://github.com/GenieFramework/Stipple.jl.

  If you use `@old_reactive!`, make sure to call `accessmode_from_pattern!()`, because the internals for
  accessmode have changed, e.g.
  ```
  model = init(MyDashboard) |> accessmode_from_pattern! |> handlers |> ui |> html
  ```
  """
  
  output = @eval(__module__, values(Stipple.@var_storage($(expr.args[3]), false)))
  expr.args[3] = quote $(output...) end

  esc(quote
    @warn $warning
    Stipple.@kwredef $expr
  end)
end

macro reactive(expr)
  warning = """@reactive is deprecated, please replace use `@vars` instead.
  
  In case of errors, please replace `@reactive` by `@old_reactive!` and open an issue at
  https://github.com/GenieFramework/Stipple.jl.
  If you use `@old_reactive!`, make sure to call `accessmode_from_pattern!()`, because the internals for
  accessmode have changed, e.g.
  ```
  model = init(MyDashboard) |> accessmode_from_pattern! |> handlers |> ui |> html
  ```
  
  """
  
  output = @eval(__module__, values(Stipple.@var_storage($(expr.args[3]), false)))
  expr.args[3] = quote $(output...) end

  esc(:(Base.@kwdef $expr))
end

#===#

mutable struct Settings
  readonly_pattern
  private_pattern
end
Settings(; readonly_pattern = r"_$", private_pattern = r"__$") = Settings(readonly_pattern, private_pattern)

function Base.hash(r::T) where {T<:ReactiveModel}
  hash((( getfield(r, f) for f in fieldnames(typeof(r)) ) |> collect |> Tuple))
end

function Base.:(==)(a::T, b::R) where {T<:ReactiveModel,R<:ReactiveModel}
  hash(a) == hash(b)
end

#===#

struct MissingPropertyException{T<:ReactiveModel} <: Exception
  property::Symbol
  entity::T
end
Base.string(ex::MissingPropertyException) = "Entity $entity does not have required property $property"

#===#

"""
    const JS_DEBOUNCE_TIME

Debounce time used to indicate the minimum frequency for sending data payloads to the backend (for example to batch send
payloads when the user types into an text field, to avoid overloading the server).
"""
const JS_DEBOUNCE_TIME = 300 #ms
const SETTINGS = Settings()