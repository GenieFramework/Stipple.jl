const REVISE_DEBUG_INFO = RefValue(false)

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
    # forward property :val to respective field of Observable
    if field == :val
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
    # forward property :val to respective field of Observable
    if field == :val
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

struct Mixin
  mixin::Union{Expr, Symbol, QuoteNode}
  prefix::String
  postfix::String
end

export @vars, @define_mixin, @clear_cache, clear_cache, @clear_route, clear_route, @mixin
export synchronize!, unsynchronize!

export getchannel

function getchannel(m::M) where {M<:ReactiveModel}
  getfield(m, :channel__)
end


function setchannel(m::M, value) where {M<:ReactiveModel}
  setfield!(m, :channel__, String(value))
end

const AUTOFIELDS = [:isready, :isprocessing, :fileuploads, :ws_disconnected] # not DRY but we need a reference to the auto-set fields
const INTERNALFIELDS = [:channel__, :modes__, :handlers__, :observerfunctions__] # not DRY but we need a reference to the auto-set fields

@pour reactors begin
  channel__::Stipple.ChannelName = Stipple.channelfactory()
  handlers__::Vector{Function} = Function[]
  observerfunctions__::Vector{ObserverFunction} = ObserverFunction[]
  modes__::LittleDict{Symbol, Int} = LittleDict(INTERNALFIELDS .=> PRIVATE)
  isready::Stipple.R{Bool} = false
  isprocessing::Stipple.R{Bool} = false
  channel_::String = "" # not sure what this does if it's empty
  fileuploads::Stipple.R{Dict{AbstractString,AbstractString}} = Dict{AbstractString,AbstractString}()
  ws_disconnected::Stipple.R{Bool} = false
end

function split_expr(expr)
  expr.args[1] isa Symbol ? (expr.args[1], nothing, expr.args[2]) : (expr.args[1].args[1], expr.args[1].args[2], expr.args[2])
end

function expr_isa_var(ex)
  ex isa Symbol && return true
  while ex isa Expr
    if ex.head == :call && ex.args[1] in (:getfield, :getproperty) || ex.head == :.
      ex = ex.args[2]
    else
      return false
    end
  end

  return ex isa QuoteNode && ex.value isa Symbol
end

function var_to_storage(T, prefix = "", postfix = ""; mode = READONLY, mixin_name = nothing)
  M, m = if T isa DataType
    T <: ReactiveModel && (T = get_concrete_type(T))
    T, T()
  else
    typeof(T), T
  end

  fields = collect(fieldnames(M))
  values = Any[getfield.(RefValue(m), fields)...]
  ftypes = Any[fieldtypes(M)...]
  has_reactives = any(ftypes .<: Reactive)

  # if m has no reactive fields, we assume that all fields should be made reactive, default mode is READONLY
  if !has_reactives
    for (i, (f, type, v)) in enumerate(zip(fields, ftypes, values))
      f in [INTERNALFIELDS..., AUTOFIELDS...] && continue
      rtype = Reactive{type}
      ftypes[i] = rtype
      values[i] = !isa(T, DataType) && expr_isa_var(mixin_name) ? Expr(:call, rtype, Expr(:., mixin_name, QuoteNode(f)), mode) : rtype(v, mode)
    end
  end
  storage = LittleDict{Symbol, Expr}()
  for (f, type, v) in zip(fields, ftypes, values)
    f = f in [INTERNALFIELDS..., AUTOFIELDS...] ? f : Symbol(prefix, f, postfix)
    v isa Symbol && (v = QuoteNode(v))
    storage[f] = v isa QuoteNode || v isa Expr ? :($f::$type = $v) : :($f::$type = Stipple._deepcopy($v))
  end
  # fix channel field, which is not reconstructed properly by the code above
  storage[:channel__] = :(channel__::String = Stipple.channelfactory())

  storage
end

function merge_storage(storage_1::AbstractDict, storage_2::AbstractDict;
  keep_channel = true, context::Module, handlers_expr::Union{Vector, Nothing} = nothing)

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
  
  # merge handlers
  if haskey(storage_1, :handlers__) && haskey(storage_2, :handlers__)
    for storage in (storage_1, storage_2)
      haskey(storage, :handlers__) && postwalk!(storage[:handlers__]) do ex
        MacroTools.@capture(ex, Stipple._deepcopy(x_)) ? x : ex
      end
    end
    h1 = find_assignment(storage_1[:handlers__]).args[end]
    h2 = find_assignment(storage_2[:handlers__]).args[end]

    h1 isa Expr && (h1 = h1.args)
    h2 isa Expr && (h2 = h2.args[2:end])

    # if prefix or postfix is set, we need to create a new handler function
    # the name of the function is composed of the name of the target model
    # the mixin model with prefix and postfix and the suffix "_handlers"
    if handlers_expr !== nothing
      prefix, postfix = handlers_expr[1:2]
      handlers_expr = handlers_expr[3:end]
      h1_name = string(get(h1, 2, ""))
      endswith(h1_name, "_handlers") && (h1_name = h1_name[1:end-9])
      h2_name = string(get(h2, 1, ""))
      endswith(h2_name, "_handlers") && (h2_name = h2_name[1:end-9])
      handlers_fn_name = Symbol(h1_name, "_", prefix, h2_name, postfix, "_handlers")
      function_expr = :(function $handlers_fn_name(__model__)
        $(handlers_expr...)  
        __model__
      end)
      @eval context $function_expr
      h2 = [handlers_fn_name]
    end
    append!(h1, h2)
    delete!(storage_2, :handlers__)
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
  val === :__Any__ || push!(let_block.args, is_non_reactive ? :(var = $val_qn) : :($var = $Rtype{$T}($val_qn)))
  return val, T
end

# deterimine the variables that need to be evaluated to infer the type of the variable
function required_evals!(expr, vars::Set, all_vars::Set)
  expr isa LineNumberNode && return vars
  expr = find_assignment(expr)
  # @mixin statements are currently not evaluated
  expr === nothing && return vars
  if expr.args[1] isa Symbol
    x = expr.args[1]
    push!(vars, x)
    push!(all_vars, x)
  elseif expr.args[1] isa Expr && expr.args[1].head == :(::)
    x = expr.args[1].args[1]
    push!(all_vars, x)
  end
  MacroTools.postwalk(expr.args[end]) do ex
    MacroTools.@capture(ex, x_[]) && x ∈ all_vars && push!(vars, x)
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
  type = if isa(var, Expr) && var.head == Symbol("::")
    # change type T to type R{T} if the variable is reactive
    is_non_reactive || (var.args[end] = :($Rtype{$(var.args[end])}))
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

parse_expression(expr::Expr, mode = nothing, source = nothing, m = nothing, let_block::Union{Expr, Nothing} = nothing, vars::Set = Set()) = parse_expression!(copy(expr), mode, source, m, let_block, vars)

function parse_mixin_params(params)
  striplines!(params)
  mixin, prefix, postfix = if length(params) == 1 && params[1] isa Expr && hasproperty(params[1], :head) && params[1].head == :(::)
    params[1].args[2], string(params[1].args[1]), ""
  elseif length(params) == 1
    params[1], "", ""
  elseif length(params) == 2
    params[1], string(params[2]), ""
  elseif length(params) == 3
    params[1], string(params[2]), string(params[3])
  else
    error("1, 2, or 3 arguments expected, found $(length(params))")
  end
  mixin, prefix, postfix
end

macro mixin(expr...)
  Mixin(parse_mixin_params(collect(expr))...)
end

function add_brackets!(expr, varnames)
  expr isa Expr || return expr
  ex = Stipple.find_assignment(expr)
  ex === nothing && return expr
  val = ex.args[end]
  if val isa Symbol && val ∈ varnames
    ex.args[end] = :($val[])
    return expr
  elseif val isa Expr
    postwalk!(val) do x
      if x isa Symbol && x ∈ varnames
        :($x[])
      else
        x
      end
    end
  end
  expr
end

macro var_storage(expr, handler = nothing)
  m = __module__
  expr = macroexpand(m, expr) |> MacroTools.flatten
  if !isa(expr, Expr) || expr.head != :block
    expr = quote $expr end
  end

  storage = init_storage(handler)

  source = nothing
  required_vars = Set()
  all_vars = Set()
  let_block = Expr(:block, :(_ = 0))
  required_evals!.(expr.args, RefValue(required_vars), RefValue(all_vars))
  add_brackets!.(expr.args, RefValue(required_vars))
  for e in expr.args
      if e isa LineNumberNode
        source = e
        continue
      end
      mode = :PUBLIC
      reactive = true
      if e isa Expr && e.head == :(=)
        #check whether flags are set
        if e.args[end] isa Expr && e.args[end].head == :tuple
          flags = e.args[end].args[2:end]
          if length(flags) > 0 && flags[1] ∈ [:PUBLIC, :READONLY, :PRIVATE, :JSFUNCTION, :NON_REACTIVE]
            newmode = intersect(setdiff(flags, [:NON_REACTIVE]), [:READONLY, :PRIVATE, :JSFUNCTION])
            length(newmode) > 0 && (mode = newmode[end])
            reactive = :NON_REACTIVE ∉ flags
            e.args[end] = e.args[end].args[1]
          end
        end
        var, ex = parse_expression!(e, reactive ? mode : nothing, source, m, let_block, required_vars)
        # prevent overwriting of control fields
        var ∈ [INTERNALFIELDS..., AUTOFIELDS...] && continue
        if reactive == false
            Stipple.setmode!(storage[:modes__], Core.eval(Stipple, mode), var)
        end

        storage[var] = ex
      else
        if e isa Mixin
          mixin, prefix, postfix = e.mixin, e.prefix, e.postfix
          mixin_storage = Stipple.var_to_storage(@eval(m, $mixin), prefix, postfix; mixin_name = mixin)

          pre_length = lastindex(prefix)
          post_length = lastindex(postfix)
      
          handlers_expr_name = Symbol(mixin, :var"!_handlers_expr")
          handlers_expr = if pre_length + post_length > 0 && isdefined(m, handlers_expr_name)
            varnames = setdiff(collect(keys(mixin_storage)), Stipple.AUTOFIELDS, Stipple.INTERNALFIELDS)
            oldvarnames = [Symbol("$var"[1 + pre_length:end-post_length]) for var in varnames]
            # make a deepcopy of the handlers_expr, because we modify it by prefix and postfix
            handlers_expr = deepcopy(@eval(m, $handlers_expr_name))
            for h in handlers_expr
              h isa Expr || continue
              postwalk!(h) do x
                if x isa Symbol && x ∈ oldvarnames
                  Symbol(prefix, x, postfix)
                elseif x isa QuoteNode && x.value isa Symbol && x.value ∈ oldvarnames
                  QuoteNode(Symbol(prefix, x.value, postfix))
                else
                  x
                end
              end
            end
            vcat([prefix, postfix], handlers_expr)
          else
            nothing
          end
          merge!(storage, merge_storage(storage, mixin_storage; context = m, handlers_expr))
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
  delete!.(RefValue(Stipple.DEPS), filter(x -> x isa Type && x <: M, keys(Stipple.DEPS)))
  Stipple.Genie.Router.delete!(M)
  return nothing
end

macro clear_cache(App)
  :(Stipple.clear_cache($(esc(App))))
end

function restore_constructor(::Type{T}) where T<:ReactiveModel
  # When Revise registeres macros it seems to execute them and to delete most of the traces, e.g. it
  # deletes constructors of structs it created. As we define a variable that points to the latest compiled struct
  # the program throws an error when it tries to access the deleted constructor.
  # This function redefines the deleted constructor by referring to the constructor of the latest valid version.
  parent = parentmodule(T)
  AM = get_abstract_type(T)
  abstract_modelname = AM.name.name
  modelconst = Symbol(abstract_modelname, '!')

  M = getfield(parent, modelconst)
  length(methods(M, ())) > 0 && return false

  nn = split(String(M.name.name), '_')
  i = tryparse(Int, nn[end])
  i === nothing && return T
  undef_modelname = Symbol(modelconst, '_', i)
  i -= 1

  while i > 0
      modelname = Symbol(modelconst, '_', i)
      M = getfield(parent, modelname)
      if length(methods(M, ())) > 0
        # latest true definition found, so redefine the constructor
        ex = :(begin
          Stipple.REVISE_DEBUG_INFO[] && @info "Redefining model constructor"
          $undef_modelname(; kwargs...) = $modelname(; kwargs...)
        end)
        @eval parent $ex
        return true
      end
      i -= 1
  end
  return false
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

    function $modelname(; kwargs...)
      # Check existence of constructor, it might have been removed by Revise.
      # In that case reset the modelconst to the latest valid version
      # via the get_concrete_type method, see below
      if @isdefined($modelconst) && length(methods($modelconst, ())) == 0
        Stipple.restore_constructor($modelconst)
      end
      $modelconst(; kwargs...)
    end

    function Stipple.get_concrete_type(::Type{$modelname})
      if @isdefined($modelconst) && length(methods($modelconst, ())) == 0
        Stipple.restore_constructor($modelconst)
      end
      $modelconst
    end

    delete!.(Base.RefValue(Stipple.DEPS), filter(x -> x isa Type && x <: $modelname, keys(Stipple.DEPS)))
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
  delete!.(RefValue(storage),  [:channel__, Stipple.AUTOFIELDS...])

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

Debounce time used to indicate the minimum duration that an input must pause before a front-end change is sent to the backend (for example to batch send
payloads when the user types into an text field, to avoid overloading the server).
"""
const JS_DEBOUNCE_TIME = 300 #ms
"""
    const JS_THROTTLE_TIME

Throttle time used to indicate the minimum duration before a new input signal is sent to the backend (for example to update a model variable with a
lower frequency, to avoid overloading the server).
"""
const JS_THROTTLE_TIME = 0   #ms
const SETTINGS = Settings()


"""
    Base.notify(@nospecialize(observable::AbstractObservable), priority::Union{Int, Function})

Implement observable notification with priority filtering.

### Example
```
# only notify listeners with priority 1
notify(observable, 1)

# only notify listeners with priority greater than 0
notify(observable, >(0))

# notify all listeners except those with priority 1
notify(observable, ≠(1))
```
"""
function Base.notify(@nospecialize(observable::AbstractObservable), priority::Union{Int, Function})
  val = observable[]
  for (p, f) in Observables.listeners(observable)::Vector{Pair{Int, Any}}
      (priority isa Int ? p == priority : priority(p)) || continue
      result = Base.invokelatest(f, val)
      if result isa Consume && result.x
          # stop calling callbacks if event got consumed
          return true
      end
  end
  return false
end

function get_synced_observers(o::AbstractObservable)
  oo = AbstractObservable[]
  for cb in getindex.(Observables.listeners(o), 2)
      p = propertynames(cb)
      (length(p) == 2 && p[1] == :priority && p[2] ∈ (:o1, :o2)) || continue
      push!(oo, getfield(cb, p[2]))
  end
  unique!(oo)
end

function get_syncing_listeners(o::AbstractObservable)
  cbs = Function[]
  for cb in getindex.(Observables.listeners(o), 2)
      p = propertynames(cb)
      (length(p) == 2 && p[1] == :priority && p[2] ∈ (:o1, :o2)) || continue
      push!(cbs, cb)
  end
  return cbs
end

function loop_check(o1::AbstractObservable, o2::AbstractObservable)
  loop_warn = true
  pool = get_synced_observers(o2)
  while o1 ∉ pool
    loop_warn = false
    new_pool = AbstractObservable[]
    for o in pool
      o_pool = get_synced_observers(o)
      setdiff!(o_pool, pool, new_pool)
      if !isempty(o_pool)
        (loop_warn = o1 ∈ o_pool) && break
        union!(new_pool, o_pool)
      end
    end
    (loop_warn || isempty(new_pool)) && break
    union!(pool, new_pool)
  end
  
  return loop_warn
end

"""
    synchronize!(o1::AbstractObservable, o2::AbstractObservable; priority::Union{Int,Nothing} = nothing, update = true, biderectional = false)

Synchronize two observables by setting the value of `o1` to the value of `o2`.
Other than `connect!()` this function works bidirectional without creating a loop back.
Synchronizing multiple observables is possible, but care should be taken to always synchronize to the same root observable.

### parameters
- `o1::AbstractObservable`: The first observable to synchronize.
- `o2::AbstractObservable`: The observable to synchronize with
- `priority::Union{Int,Nothing}`: The priority of the synchronization listeners.

    The priority is used as identifier of a synchronization pair.
    If more than one observables is synchronized they should have different priorities.
    If `nothing` (default), search for a unique priority so that the order of synchronization is identical to 
    the order of synchronize!() calls.
- `update::Bool`: If `true` then `o1` will be updated with the value of `o2`, default: `true`
- `biderectional`: If `true` (default) perform two-way synchronization, if `false` sync o1 to follow o2.
    The latter functionally identical to `connect!()`, however `unsynchronize!()` only works correctly on 
    variables synced with `synchronize!()`
  
### Example 1

```
o = Observable(0)
on(o -> println("o: \$o"), o)

o1 = Observable(1)
on(o1 -> println("o1: \$o1"), o)

o2 = Observable(2)
on(o2 -> println("o2: \$o2"), o)

synchronize!(o1, o)
synchronize!(o2, o)

o[] = 10;
# o: 10
# o1: 10
# o2: 10

o1[] = 11;
# o: 11
# o1: 11
# o2: 11

o2[] = 12;
# o: 12
# o1: 12
# o2: 12
```

### Example 2
```
using Stipple, Stipple.ReactiveTools
using StippleUI

const X = Observable(0)

@app Observer begin
    @in x = 0

    @onchange isready begin
        synchronize!(__model__.x, X)
    end
end

@event Observer :finalize begin
    println("unsynchronizing ...")
    @info unsynchronize!(__model__.x)
    notify(__model__, Val(:finalize))
end

@page("/", slider(1:100, :x), model = Observer)

@debounce Observer x 0
@throttle Observer x 10

up()
```

### Example 3

Modification of Example 2 to sync only tabs with the same session id (i.e. the same browser).

```
using Stipple, Stipple.ReactiveTools
using StippleUI
using GenieSession

const XX = Dict{String, Reactive}()

@app Observer begin
    @in x = 0
    @private session = ""

    @onchange isready begin
        r = get!(XX, session, R(x))
        synchronize!(__model__.x, r)
    end
end

@page("/", slider(1:100, :x), model = Observer, post = model -> begin model.session[] = session().id; nothing end)

@event Observer :finalize begin
    println("unsynchronizing ...")
    @info unsynchronize!(__model__.x)
    notify(__model__, Val(:finalize))
end

@debounce Observer x 0
@throttle Observer x 10

up()
```
Note that `post` has been used to attach the session id to the model. Make sure that the
attached function returns nothing in order to proceed with the page rendering.
If `post` returns a value, the page will render that value instead of the page content.
For further information see [`@page`](@ref).

Unsynchronization via the event :finalize is important to suppress syncing to models
that have been replaced by page reloading or navigation.
"""
function synchronize!(o1::AbstractObservable, o2::AbstractObservable; priority::Union{Int,Nothing} = nothing, update = true, bidirectional = true)
  if priority === nothing
    priorities = getindex.(Observables.listeners(o2), 1)
    bidirectional || union!(priorities, getindex.(Observables.listeners(o1), 1))
    setdiff!(priorities, typemin(Int))
    priority = isempty(priorities) ? -1 : minimum(priorities) - 1
  end

  if loop_check(o1, o2)
    @warn "Synchronization loop detected, skipping synchronization"  
    return ObserverFunction[]
  end

  function update_o1(x)
    o1.val = x
    notify(o1, !=(priority))
  end
  function update_o2(x)
    o2.val = x
    notify(o2, !=(priority))
  end
  if bidirectional
    ObserverFunction[on(update_o1, o2; update, priority), on(update_o2, o1; priority)]
  else
    ObserverFunction[on(update_o1, o2; update, priority)]
  end
end


"""
    unsynchronize!(o::AbstractObservable, o_sync::Union{AbstractObservable, Nothing} = nothing)

Remove synchronization of observables.

### Parameters
- `o::AbstractObservable`: The observable to unsynchronize.
- `o_sync::Union{AbstractObservable, Nothing}`: The observable to unsynchronize with,
  if `nothing` (default) remove all bidirectional synchronizations and all unidirectional synchronizations from `o`,
  if `o_sync` is passed, remove all synchronizations between `o` and `o_sync`.
  
### Example 1

```
o = Observable(0)
on(o -> println("o: \$o"), o)
o1 = Observable(1)
on(o1 -> println("o1: \$o1"), o)
o2 = Observable(2)
on(o2 -> println("o2: \$o2"), o)
o3 = Observable(3)

synchronize!(o1, o)
synchronize!(o2, o)
synchronize!(o3, o, biderectional = false)

# unsync o2 only
unsynchronize!(o2)

# wrong way of unsyncing o3, because it's unidirectional
unsynchronize!(o3)

# correct way of unsyncing o3
unsynchronize!(o3, o)

# unsync all syncs from o
unsynchronize!(o)
```
"""
function unsynchronize!(o::AbstractObservable, o_sync::Union{AbstractObservable, Nothing} = nothing)
  oo1 = o_sync === nothing ? (o,) : (o, o_sync)
  oo2 = o_sync === nothing ? (nothing,) : (o_sync, o)
  # two runs to cover all unidirectional syncs if two observables are passed
  # single run if o2 === nothing, readonyly syncs from other observables are not removed
  # however, unidirectional syncs to other observables are removed
  for (o1, o2) in zip(oo1, oo2)
    cbs1 = get_syncing_listeners(o1)
    for cb in cbs1
      fieldname = propertynames(cb)[2]
      o_source = getfield(cb, fieldname)
      o2 === nothing || o_source === o2 || continue
      # remove back syncs if o2 === nothing  
      if o2 === nothing
        cbs2 = filter!(o -> getfield(o, propertynames(o)[2]) === o1, get_syncing_listeners(o_source))
        off.(RefValue(o_source), cbs2)
      end
      off(o1, cb)
    end
  end
end