struct Mixin
  M::DataType
  prefix::String
  postfix::String
end

"""
    js_print(io::IO, x)

Stipple internal print routine for join_js.
Mainly used to allow for printing of JSON.JSONText
"""
js_print(io::IO, x) = print(io, x)

"""
    join_js(xx, delim = ""; skip_empty = true, pre::Function = identity,
      strip_delimiter = true, pre_delim::Union{Function,Nothing} = nothing)

Join elements of an iterator similar to [`join`](@ref) with additonal features
- evaluate the elements if they are callable
- preprocessing of elements, e.g. strip
- optional stripping of delimiter
- dicts/pairs are resolved to json pairs

Parameters:
- `xx`: Iterator
- `delim`: delimiter
- `skip_empty`: if true skip empty entries, e.g. with `pre = strip`, `" "` is ignored
- `pre`: preprocessor function that is applied to the resulting string of each element
- `stip_delimiter`: If true strips a potential delimiter at the end of a string
- `pre_delim`: preprocessor function for delimiter, if `nothing` it defaults to `pre`
- `unique`: if true, remove duplicates before joining

### Example
```
julia> f() = "Hello,";

julia> join_js([1, f, "World,"], ",\\n", pre = strip) |> println
1,
Hello,
World

julia> f() = "hi - ";

julia> join_js([1, f, "2 "], " - ", pre = strip)
"1 - hi - 2"
```
"""
function join_js(xx::Union{Tuple, AbstractArray}, delim = "";
  skip_empty = true,
  pre::Function = identity,
  strip_delimiter = true,
  pre_delim::Union{Function,Nothing} = nothing,
  unique = false,
)
  a = collect_js(xx, delim; skip_empty, pre, strip_delimiter, pre_delim, unique)
  join(a, delim)
end

function flatten(arr)
  rst = Any[]
  grep(v) =   for x in v
              if isa(x, Tuple) ||  isa(x, Array)
              grep(x) 
              else push!(rst, x) end
              end
  grep(arr)
  rst
end

function collect_js(xx::Union{Tuple, AbstractArray}, delim = "";
  skip_empty::Bool = true,
  pre::Function = identity,
  strip_delimiter::Bool = true,
  pre_delim::Union{Function,Nothing} = nothing,
  unique::Bool = false,
  key_replacement::Function = identity,
)
  xx = flatten(xx)
  a = String[]
  firstrun = true
  s_delim = pre_delim === nothing ? pre(delim) : pre_delim(delim)
  n_delim = ncodeunits(s_delim)
  for x_raw in xx
    x = x_raw isa Base.Callable ? x_raw() : x_raw
    io2 = IOBuffer()
    if x isa Union{AbstractDict, Pair, Base.Iterators.Pairs, Vector{<:Pair}}
      s = json(Dict(key_replacement(k) => JSONText(v) for (k, v) in (x isa Pair ? [x] : x)))[2:end - 1]
      print(io2, s)
    elseif x isa JSONText
      print(io2, x.s)
    else
      js_print(io2, x)
    end
    s = String(take!(io2))
    hasdelimiter = strip_delimiter && endswith(s, delim)
    s = pre(hasdelimiter ? s[1:end - ncodeunits(delim)] : s)
    (skip_empty && isempty(s)) || push!(a, s)
  end
  unique ? unique!(a) : a
end

function join_js(x, delim = ""; skip_empty = true, pre::Function = identity, strip_delimiter = true, pre_delim::Union{Function,Nothing} = nothing, unique = false)
  join_js([x], delim; skip_empty, pre, strip_delimiter, pre_delim, unique)
end

const RENDERING_MAPPINGS = Dict{String,String}()
mapping_keys() = collect(keys(RENDERING_MAPPINGS))

"""
    function rendering_mappings(mappings = Dict{String,String})

Registers additional `mappings` as Julia to Vue properties mappings  (eg `foobar` to `foo-bar`).
"""
function rendering_mappings(mappings = Dict{String,String})
  merge!(RENDERING_MAPPINGS, mappings)
end

"""
    function julia_to_vue(field, mapping_keys = mapping_keys())

Converts Julia names to Vue names (eg `foobar` to `foo-bar`).
"""
function julia_to_vue(field, mapping_keys = mapping_keys()) :: String
  if in(string(field), mapping_keys)
    parts = split(RENDERING_MAPPINGS[string(field)], "-")

    if length(parts) > 1
      extraparts = map((x) -> uppercasefirst(string(x)), parts[2:end])
      string(parts[1], join(extraparts))
    else
      join(parts) |> string
    end
  else
    field |> string
  end
end

"""
    jsrender(x, args...)

Defines separate rendering for the Vue instance. This method is only necessary for non-standard types that
are not transmittable by regular json. Such types need a reviver to be transmitted via json and (optionally)
a render method that is only applied for the rendering of the model.
The model is not transmitted via json but via a js-file. So there it is possible to define non-serializable values.

### Example

```
Stipple.render(z::Complex) = Dict(:mathjs => "Complex", :re => z.re, :im => z.im)
function Stipple.jsrender(z::Union{Complex, R{<:Complex}}, args...)
    JSONText("math.complex('\$(replace(strip(repr(Observables.to_value(z)), '"'), 'm' => ""))')")
end
Stipple.stipple_parse(::Complex, z::Dict{String, Any}) = float(z["re"]) + z["im"]
```
"""
jsrender(x, args...) = render(x, args...)
jsrender(r::Reactive, args...) = jsrender(getfield(getfield(r,:o), :val), args...)

const MIXINS = RefValue(["watcherMixin", "reviveMixin", "eventMixin", "filterMixin"])
add_mixins(mixins::Vector{String}) = union!(push!(MIXINS[], mixins...))
add_mixins(mixin::String) = union!(push!(MIXINS[], mixin))

function mixins(::Type{<:ReactiveModel})
  Mixin[]
end
Stipple.mixins(::T) where T <: ReactiveModel = Stipple.mixins(T)

function get_known_js_vars(::Type{M}) where M<:ReactiveModel
  CM = Stipple.get_concrete_type(M)
  vars = vcat(setdiff(fieldnames(CM), Stipple.AUTOFIELDS, Stipple.INTERNALFIELDS), Symbol.(keys(client_data(CM))))
  
  computed_vars = Symbol.(strip.(first.(split.(collect_js([js_methods(M)]), ':', limit = 2)), '"'))
  method_vars = Symbol.(strip.(first.(split.(collect_js([js_computed(M)]), ':', limit = 2)), '"'))

  vars = vcat(vars, computed_vars, method_vars)
  sort!(sort!(vars), by = x->length(String(x)), rev = true)
end

function get_known_js_vars(::Type{T}) where T
  Symbol[fieldnames(T)...]
end

function js_mixin(m::Mixin, js_f, delim)
  M, prefix, postfix = m.M, m.prefix, m.postfix
  vars = get_known_js_vars(M)
  empty_var = Symbol("") ∈ vars
  empty_var && setdiff!(vars, [Symbol("")])

  replace_rule1 = Regex("\\b(this|GENIEMODEL)\\.($(join(vars, '|')))\\b") => SubstitutionString("\\1.$prefix\\2$postfix")
  replace_rule2 = Regex("\\b(this|GENIEMODEL)\\. ") => SubstitutionString("\\1.$prefix$postfix ")

  no_modifiers = isempty(prefix) && isempty(postfix) || js_f ∉ (js_methods, js_computed, js_watch)
  add_fixes(s) = Symbol(prefix, s, postfix)
  add_fixes(s::JSONText) = Symbol(s.s)
  xx = collect_js([js_f(M)], delim; pre = strip, key_replacement = no_modifiers ? identity : add_fixes)
  
  isempty(prefix) && isempty(postfix) && return xx

  for i in eachindex(xx)
    s = replace(xx[i], replace_rule1)
    empty_var && (s = replace(s, replace_rule2))
    xx[i] = s
  end
  
  return xx
end

function render_js_options!(::Union{M, Type{M}}, vue::Dict{Symbol, Any} = Dict{Symbol, Any}(); mixin = false, indent = 4) where {M<:ReactiveModel}
  indent isa Integer && (indent = repeat(" ", indent))
  pre = isempty(indent) ? strip : s -> replace(strip(s), "\n" => "\n$indent")
  sep1 = ",\n\n$indent"
  sep2 = "\n\n$indent"

  for (f, field) in ((js_methods, :methods), (js_computed, :computed), (js_watch, :watch))
    xx = Any[f(M)]
    for m in mixins(M)
      push!(xx, js_mixin(m, f, sep1))
    end

    if field == :watch
      watch_auto = js_watch_auto(M)
      isempty(watch_auto) || push!(xx, watch_auto)
    end

    js = join_js(xx, sep1; pre, unique = true)
    isempty(js) || push!(vue, field => JSONText("{\n    $js\n}"))
  end

  for (f, field) in (
    (js_before_create, :beforeCreate), (js_created, :created), (js_before_mount, :beforeMount), (js_mounted, :mounted),
    (js_before_update, :beforeUpdate), (js_updated, :updated), (js_activated, :activated), (js_deactivated, :deactivated),
    (js_before_destroy, :beforeDestroy), (js_destroyed, :destroyed), (js_error_captured, :errorCaptured),)

    xx = Any[f(M)]
    for m in mixins(M)
      push!(xx, js_mixin(m, f, sep2))
    end

    if field == :created
      created_auto = Stipple.js_created_auto(M)
      isempty(created_auto) || push!(xx, created_auto)
    elseif field == :mounted && ! mixin
      mounted_auto = """setTimeout(() => {
          this.WebChannel.unsubscriptionHandlers.push(() => this.handle_event({}, 'finalize'))
          console.log('Unsubscription handler installed')
      }, 100)
      """
      push!(xx, mounted_auto)
    end

    js = join_js(xx, sep2; pre, unique = true)
    isempty(js) || push!(vue, field => JSONText("function(){\n    $js\n}"))
  end
  vue
end

"""
    function Stipple.render(app::M, fieldname::Union{Symbol,Nothing} = nothing)::Dict{Symbol,Any} where {M<:ReactiveModel}

Renders the Julia `ReactiveModel` `app` as the corresponding Vue.js JavaScript code.
"""
function Stipple.render(app::M)::Dict{Symbol,Any} where {M<:ReactiveModel}
  result = OptDict()

  for field in fieldnames(typeof(app))
    f = getfield(app, field)

    occursin(SETTINGS.private_pattern, String(field)) && continue
    f isa Reactive && f.r_mode == PRIVATE && continue

    result[field] = Stipple.jsrender(f, field)
  end

  # convert :data to () => ({   })
  data = json(merge(result, client_data(app)))

  vue = Dict(
    :mixins => JSONText.(MIXINS[]),
    :data => JSONText("() => ($data)")
  )

  render_js_options!(app, vue)

  vue
end

"""
    function Stipple.render(val::T, fieldname::Union{Symbol,Nothing} = nothing) where {T}

Default rendering of value types. Specialize `Stipple.render` to define custom rendering for your types.
"""
function Stipple.render(val::T, fieldname::Union{Symbol,Nothing}) where {T}
  Stipple.render(val)
end

function Stipple.render(val::T) where {T}
  (! (val isa AbstractDict || val isa AbstractVector) && Tables.istable(val)) ? rendertable(val) : val
end

function Stipple.rendertable(@nospecialize table)
  OrderedDict(zip(Tables.columnnames(table), Tables.columns(table)))
end

"""
    function Stipple.render(o::Reactive{T}, fieldname::Union{Symbol,Nothing} = nothing) where {T}

Default rendering of `Reactive` values. Specialize `Stipple.render` to define custom rendering for your type `T`.
"""
function Stipple.render(o::Reactive{T}, fieldname::Union{Symbol,Nothing} = nothing) where {T}
  Stipple.render(o[], fieldname)
end

"""
    js_attr(x)

Renders a Julia expression as Javascript Expression that can be passed as an attribute value in html elements.
### Example
```
using StippleUI

quasar(
  :btn__toggle,
  fieldname = :btn_value,
  options = js_attr([opts(label = "Off", value = false), opts(label = "On", value = true)])
)

# "<q-btn-toggle v-model=\\"btn_value\\" :options=\\"[{'value':false,'label':'Off'}, {'value':true,'label':'On'}]\\"></q-btn-toggle>"
```
"""
function js_attr(x)
  Symbol(replace(replace(json(render(x)), "'" => raw"\'"), '"' => '''))
end

Stipple.render(X::Matrix) = [X[:, i] for i in 1:size(X, 2)]