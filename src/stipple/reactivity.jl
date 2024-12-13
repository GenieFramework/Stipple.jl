"""
        mutable struct Reactive{T} <: Observables.AbstractObservable{T}

`Reactive` is a the base type for variables that are handled by a model. It is an `AbstractObservable` of which the content is
obtained by appending `[]` after the `Reactive` variable's name.
For convenience, `Reactive` can be abbreviated by `R`.

There are several methods of creating a Reactive variable:
- `r = Reactive(8)`
- `r = Reactive{Float64}(8)`
- `r = Reactive{Float64}(8, READONLY)`
- `r = Reactive{String}("Hello", PRIVATE)`
- `r = Reactive(jsfunction"console.log('Hi')", JSFUNCTION)`
"""
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

"""
        mutable struct Reactive{T} <: Observables.AbstractObservable{T}

`Reactive` is a the base type for variables that are handled by a model. It is an `AbstractObservable` of which the content is
obtained by appending `[]` after the `Reactive` variable's name.
For convenience, `Reactive` can be abbreviated by `R`.

There are several methods of creating a Reactive variable:
- `r = Reactive(8)`
- `r = Reactive{Float64}(8)`
- `r = Reactive{Float64}(8, READONLY)`
- `r = Reactive{String}("Hello", PRIVATE)`
- `r = Reactive(jsfunction"console.log('Hi')", JSFUNCTION)`
"""
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

Base.axes(r::Reactive, args...) = Base.axes(getfield(getfield(r, :o), :val), args...)
Base.lastindex(r::Reactive, args...) = Base.lastindex(getfield(getfield(r, :o), :val), args...)

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

export @vars, @define_mixin, @clear_cache, clear_cache, @clear_route, clear_route

export ChannelName, getchannel

const ChannelName = String
const CHANNELFIELDNAME = :channel__

function getchannel(m::M) where {M<:ReactiveModel}
  getfield(m, CHANNELFIELDNAME)
end


function setchannel(m::M, value) where {M<:ReactiveModel}
  setfield!(m, CHANNELFIELDNAME, ChannelName(value))
end

const AUTOFIELDS = [:isready, :isprocessing, :fileuploads, :ws_disconnected] # not DRY but we need a reference to the auto-set fields
const INTERNALFIELDS = [CHANNELFIELDNAME, :modes__] # not DRY but we need a reference to the auto-set fields

@pour reactors begin
  channel__::Stipple.ChannelName = Stipple.channelfactory()
  modes__::LittleDict{Symbol, Int} = LittleDict(:modes__ => PRIVATE, :channel__ => PRIVATE)
  isready::Stipple.R{Bool} = false
  isprocessing::Stipple.R{Bool} = false
  channel_::String = "" # not sure what this does if it's empty
  fileuploads::Stipple.R{Dict{AbstractString,AbstractString}} = Dict{AbstractString,AbstractString}()
  ws_disconnected::Stipple.R{Bool} = false
end

function split_expr(expr)
  expr.args[1] isa Symbol ? (expr.args[1], nothing, expr.args[2]) : (expr.args[1].args[1], expr.args[1].args[2], expr.args[2])
end

function model_to_storage(::Type{T}, prefix = "", postfix = "") where T# <: ReactiveModel
  M = T <: ReactiveModel ? get_concrete_type(T) : T
  fields = fieldnames(M)
  values = getfield.(Ref(M()), fields)
  storage = LittleDict{Symbol, Expr}()
  for (f, type, v) in zip(fields, fieldtypes(M), values)
    f = f in [:channel__, :modes__, AUTOFIELDS...] ? f : Symbol(prefix, f, postfix)
    storage[f] = v isa Symbol ? :($f::$type = $(QuoteNode(v))) : :($f::$type = Stipple._deepcopy($v))
  end
  # fix channel field, which is not reconstructed properly by the code above
  storage[:channel__] = :(channel__::String = Stipple.channelfactory())

  storage
end

function merge_storage(storage_1::AbstractDict, storage_2::AbstractDict; keep_channel = true, context::Module)
  m1 = haskey(storage_1, :modes__) ? Core.eval(context, storage_1[:modes__].args[end]) : LittleDict{Symbol, Int}()
  m2 = haskey(storage_2, :modes__) ? Core.eval(context, storage_2[:modes__].args[end]) : LittleDict{Symbol, Int}()
  modes = merge(m1, m2)

  keep_channel && haskey(storage_2, :channel__) && (storage_2 = delete!(copy(storage_2), :channel__))
  for (field, expr) in storage_2
    field == :modes__ && continue

    reactive = startswith(string(Stipple.split_expr(expr)[2]), r"(Stipple\.)?R(eactive)?($|{)")
    if reactive
      deletemode!(modes, field)
    else
      setmode!(modes, get(m2, field, PUBLIC), field)
    end
  end
  storage = merge(storage_1, storage_2)
  storage[:modes__] = :(modes__::Stipple.LittleDict{Symbol, Int} = $modes)

  storage
end

function find_assignment(expr)
  assignment = nothing

  if isa(expr, Expr) && !contains(string(expr.head), "=")
    for arg in expr.args
      assignment = if isa(arg, Expr)
        find_assignment(arg)
      end
    end
  elseif isa(expr, Expr) && contains(string(expr.head), "=")
    assignment = expr
  else
    assignment = nothing
  end

  assignment
end

function get_varname(expr)
  expr = find_assignment(expr)
  var = expr.args[1]
  var isa Symbol ? var : var.args[1]
end

function assignment_to_conversion(expr)
  expr = copy(expr)
  expr.head = :call
  pushfirst!(expr.args, :convert)
  expr.args[2] = expr.args[2].args[2]
  expr
end

function let_eval!(expr, let_block, m::Module, is_non_reactive::Bool = true)
  Rtype = isnothing(m) || ! isdefined(m, :R) ? :(Stipple.R) : :R
  with_type = expr.args[1] isa Expr && expr.args[1].head == :(::)
  var = with_type ? expr.args[1].args[1] : expr.args[1]
  let_expr = Expr(:let, let_block, Expr(:block, with_type ? assignment_to_conversion(expr) : expr.args[end]))
  val = try
    @eval m $let_expr
  catch ex
    with_type || @info "Could not infer type of $var, setting it to `Any`, consider adding a type annotation"
    :__Any__
  end

  T = val === :__Any__ ? Any : typeof(val)
  val_qn = QuoteNode(val)
  val === :__Any__ || push!(let_block.args, is_non_reactive ? :(var = $val) : :($var = $Rtype{$T}($val_qn)))
  return val, T
end

# deterimine the variables that need to be evaluated to infer the type of the variable
function required_evals!(expr, vars::Set)
  expr isa LineNumberNode && return vars
  expr = find_assignment(expr)
  # @mixin statements are currently not evaluated
  expr === nothing && return vars
  if expr.args[1] isa Symbol
    x = expr.args[1]
    push!(vars, x)
  end
  MacroTools.postwalk(expr.args[end]) do ex
    MacroTools.@capture(ex, x_[]) && push!(vars, x)
    ex
  end
  return vars
end

function parse_expression!(expr::Expr, @nospecialize(mode) = nothing, source = nothing, m::Union{Module, Nothing} = nothing, let_block::Union{Expr, Nothing} = nothing, vars::Set = Set())
  expr = find_assignment(expr)

  Rtype = isnothing(m) || ! isdefined(m, :R) ? :(Stipple.R) : :R

  (isa(expr, Expr) && contains(string(expr.head), "=")) ||
  error("Invalid binding expression -- use it with variables assignment ex `@in a = 2`")

  source = (source !== nothing ? String(strip(string(source), collect("#= "))) : "")

  # args[end] instead of args[2] because of potential LineNumberNode
  var = expr.args[1]
  varname = var isa Expr ? var.args[1] : var

  is_non_reactive = mode === nothing
  mode === nothing && (mode = PRIVATE)
  context = isnothing(m) ? @__MODULE__() : m

  # evaluate the expression in the context of the module and append the corresponding assignment to the let_block
  # bt only if var is in the set of required 'vars'
  val = 0
  T = DataType
  let_block !== nothing && varname ∈ vars && ((val, T) = let_eval!(expr, let_block, m, is_non_reactive))

  mode = mode isa Symbol && ! isdefined(context, mode) ? :(Stipple.$mode) : mode
  type = if isa(var, Expr) && var.head == Symbol("::") && ! is_non_reactive
    # change type T to type R{T}
    var.args[end] = :($Rtype{$(var.args[end])})
  else # no type is defined, so determine it from the type of the default value
    try
      # add type definition `::R{T}` to the var where T is the type of the default value
      T = let_block === nothing ? typeof(@eval(context, $(expr.args[end]))) : T
      expr.args[1] = is_non_reactive ? :($var::$T) : :($var::$Rtype{$T})
      is_non_reactive ? T : Rtype
    catch ex
      # if the default value is not defined, we can't infer the type
      # so we just set the type to R{Any}
      @info "Could not infer type of $var, setting it to R{Any}"
      expr.args[1] = is_non_reactive : :($var::Any) : :($var::$Rtype{Any})
      is_non_reactive ? :($var::Any) : :($Rtype{Any})
    end
  end

  is_non_reactive || (expr.args[end] = :($type($(expr.args[end]), $mode, false, false, $source)))
  varname, expr
end

parse_expression(expr::Expr, mode = nothing, source = nothing, m = nothing, let_block::Expr = nothing, vars::Set = Set()) = parse_expression!(copy(expr), mode, source, m, let_block, vars)

macro var_storage(expr)
  m = __module__
  if expr.head != :block
      expr = quote $expr end
  end

  storage = init_storage()

  source = nothing
  required_vars = Set()
  let_block = Expr(:block, :(_ = 0))
  required_evals!.(expr.args, Ref(required_vars))
  for e in expr.args
      if e isa LineNumberNode
          source = e
          continue
      end
      mode = :PUBLIC
      reactive = true
      if e.head == :(=)
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
        var, ex = parse_expression!(e, reactive ? mode : nothing, source, m, let_block, required_vars)
        # prevent overwriting of control fields
        var ∈ keys(Stipple.init_storage()) && continue
        if reactive == false
            Stipple.setmode!(storage[:modes__], Core.eval(Stipple, mode), var)
        end

        storage[var] = ex
      else
        # parse @mixin call, which is now only defined in ReactiveTools, but wouldn't work here
        if e.head == :macrocall && (e.args[1] == Symbol("@mixin") || e.args[1] == Symbol("@mix_in"))
          e.args = filter!(x -> ! isa(x, LineNumberNode), e.args)
          prefix = postfix = ""
          if e.args[2] isa Expr && e.args[2].head == :(::)
            prefix = string(e.args[2].args[1])
            e.args[2] = e.args[2].args[2]
          else
            length(e.args) ≥ 3 && (prefix = string(e.args[3]))
            length(e.args) ≥ 4 && (postfix = string(e.args[4]))
          end

          mixin_storage = @eval __module__ Stipple.model_to_storage($(e.args[2]), $prefix, $postfix)
          storage = merge_storage(storage, mixin_storage; context = __module__)
        end
        :modes__, e
      end

    end

    esc(:($storage))
end

Stipple.Genie.Router.delete!(M::Type{<:ReactiveModel}) = Stipple.Genie.Router.delete!(Symbol(Stipple.routename(M)))

function clear_route(M::Type{<:ReactiveModel})
  Stipple.Genie.Router.delete!(M)
  return nothing
end

macro clear_route(App)
  :(Stipple.clear_route($(esc(App))))
end

function clear_cache(M::Type{<:ReactiveModel})
  delete!.(Ref(Stipple.DEPS), filter(x -> x isa Type && x <: M, keys(Stipple.DEPS)))
  Stipple.Genie.Router.delete!(M)
  return nothing
end

macro clear_cache(App)
  :(Stipple.clear_cache($(esc(App))))
end

macro type(modelname, storage)
  modelname isa DataType && (modelname = modelname.name.name)
  modelconst = Symbol(modelname, '!')

  output = quote end
  output.args = @eval __module__ collect(values($storage))
  output_qn = QuoteNode(output)

  quote
    abstract type $modelname <: Stipple.ReactiveModel end

    Stipple.@kwredef mutable struct $modelconst <: $modelname
      $output
    end

    $modelname(; kwargs...) = $modelconst(; kwargs...)
    Stipple.get_concrete_type(::Type{$modelname}) = $modelconst

    delete!.(Ref(Stipple.DEPS), filter(x -> x isa Type && x <: $modelname, keys(Stipple.DEPS)))
    Stipple.Genie.Router.delete!(Symbol(Stipple.routename($modelname)))

    $modelname
  end |> esc
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
"""
macro vars(modelname, expr)
  quote
    Stipple.@type($modelname, values(Stipple.@var_storage($expr)))
  end |> esc
end

macro define_mixin(mixin_name, expr)
  storage = @eval(__module__, Stipple.@var_storage($expr))
  delete!.(Ref(storage),  [:channel__, Stipple.AUTOFIELDS...])

  quote
      Base.@kwdef struct $mixin_name
          $(values(storage)...)
      end
  end |> esc
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