mutable struct Reactive{T} <: Observables.AbstractObservable{T}
  o::Observables.Observable{T}
  r_mode::Int
  no_backend_watcher::Bool
  no_frontend_watcher::Bool

  Reactive{T}() where {T} = new{T}(Observable{T}(), PUBLIC, false, false)
  Reactive{T}(o, no_bw::Bool = false, no_fw::Bool = false) where {T} = new{T}(o, PUBLIC, no_bw, no_fw)
  Reactive{T}(o, mode::Int, no_bw::Bool = false, no_fw::Bool = false) where {T} = new{T}(o, mode, no_bw, no_fw)
  Reactive{T}(o, mode::Int, updatemode::Int) where {T} = new{T}(o, mode, updatemode & NO_BACKEND_WATCHER != 0, updatemode & NO_FRONTEND_WATCHER != 0)

  # Construct an Reactive{Any} without runtime dispatch
  Reactive{Any}(@nospecialize(o)) = new{Any}(Observable{Any}(o), PUBLIC, false, false)
end

Reactive(r::T, arg1, args...) where T = convert(Reactive{T}, (r, arg1, args...))
Reactive(r::T) where T = convert(Reactive{T}, r)

Base.convert(::Type{T}, x::T) where {T<:Reactive} = x  # resolves ambiguity with convert(::Type{T}, x::T) in base/essentials.jl
Base.convert(::Type{T}, x) where {T<:Reactive} = T(x)

Base.convert(::Type{Reactive{T}}, (r, m)::Tuple{T, Int}) where T = m < 16 ? Reactive{T}(Observable(r), m, PUBLIC) : Reactive{T}(Observable(r), PUBLIC, m)
Base.convert(::Type{Reactive{T}}, (r, w)::Tuple{T, Bool}) where T = Reactive{T}(Observable(r), PUBLIC, w, false)
Base.convert(::Type{Reactive{T}}, (r, m, nw)::Tuple{T, Int, Bool}) where T = Reactive{T}(Observable(r), m, nw, false)
Base.convert(::Type{Reactive{T}}, (r, nbw, nfw)::Tuple{T, Bool, Bool}) where T = Reactive{T}(Observable(r), PUBLIC, nbw, nfw)
Base.convert(::Type{Reactive{T}}, (r, m, nbw, nfw)::Tuple{T, Int, Bool, Bool}) where T = Reactive{T}(Observable(r), m, nbw, nfw)
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
  Observables.notify!(r)
end

Base.setindex!(r::Reactive, val, ::typeof(!)) = getfield(r, :o).val = val
Base.getindex(r::Reactive, ::typeof(!)) = getfield(r, :o).val

function Base.getproperty(r::Reactive{T}, field::Symbol) where T
  if field in (:o, :r_mode, :no_backend_watcher, :no_frontend_watcher) # fieldnames(Reactive)
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
      Observables.notify!(r)
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


export @reactors, @reactive, @reactive!
export ChannelName, getchannel

const ChannelName = String
const CHANNELFIELDNAME = :channel__

function getchannel(m::T) where {T<:ReactiveModel}
  getfield(m, CHANNELFIELDNAME)
end


function setchannel(m::T, value) where {T<:ReactiveModel}
  setfield!(m, CHANNELFIELDNAME, ChannelName(value))
end

const AUTOFIELDS = [:isready, :isprocessing] # not DRY but we need a reference to the auto-set fields

@pour reactors begin
  channel__::Stipple.ChannelName = Stipple.channelfactory()
  isready::Stipple.R{Bool} = false
  isprocessing::Stipple.R{Bool} = false
end

@mix Stipple.@with_kw mutable struct reactive
  Stipple.@reactors
end


@mix Stipple.@kwredef mutable struct reactive!
  Stipple.@reactors
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