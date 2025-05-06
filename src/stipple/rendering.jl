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
function join_js(xx::Union{Tuple, AbstractArray}, delim = ""; skip_empty = true, pre::Function = identity, strip_delimiter = true, pre_delim::Union{Function,Nothing} = nothing)
  io = IOBuffer()
  firstrun = true
  s_delim = pre_delim === nothing ? pre(delim) : pre_delim(delim)
  n_delim = ncodeunits(s_delim)
  for x_raw in xx
    x = x_raw isa Base.Callable ? x_raw() : x_raw
    io2 = IOBuffer()
    if x isa Union{AbstractDict, Pair, Base.Iterators.Pairs, Vector{<:Pair}}
      s = json(Dict(k => JSONText(v) for (k, v) in (x isa Pair ? [x] : x)))[2:end - 1]
      print(io2, s)
    elseif x isa JSONText
      print(io2, x.s)
    else
      js_print(io2, x)
    end
    s = String(take!(io2))
    hasdelimiter = strip_delimiter && endswith(s, delim)
    s = pre(hasdelimiter ? s[1:end - ncodeunits(delim)] : s)
    # if delimter has been removed already don't check for pretreated delimiter
    firstrun || (skip_empty && isempty(s)) || print(io, delim)
    # if first was not printed, firstrun stays true
    firstrun && (firstrun = (skip_empty && isempty(s)))
    print(io, strip_delimiter && ! hasdelimiter && endswith(s, s_delim) ? s[1:end - n_delim] : s)
  end
  String(take!(io))
end

function join_js(x, delim = ""; skip_empty = true, pre::Function = identity, strip_delimiter = true, pre_delim::Union{Function,Nothing} = nothing)
  join_js([x], delim; skip_empty, pre, strip_delimiter, pre_delim)
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
  for (f, field) in ((js_methods, :methods), (js_computed, :computed), (js_watch, :watch))
    js = join_js(f(app), ",\n    "; pre = strip)
    if field == :watch
      watch_auto = join_js(Stipple.js_watch_auto(app), ",\n    "; pre = strip)
      watch_auto == "" || (js = join_js([js, watch_auto], ",\n    "))
    end
    isempty(js) || push!(vue, field => JSONText("{\n    $js\n}"))
  end

  for (f, field) in (
    (js_before_create, :beforeCreate), (js_created, :created), (js_before_mount, :beforeMount), (js_mounted, :mounted),
    (js_before_update, :beforeUpdate), (js_updated, :updated), (js_activated, :activated), (js_deactivated, :deactivated),
    (js_before_destroy, :beforeDestroy), (js_destroyed, :destroyed), (js_error_captured, :errorCaptured),)

    js = join_js(f(app), "\n\n    "; pre = strip)
    if field == :created
      created_auto = join_js(Stipple.js_created_auto(app), "\n\n    "; pre = strip)
      created_auto == "" || (js = join_js([js, created_auto], "\n\n    "))
    elseif field == :mounted
      mounted_auto = """setTimeout(() => {
          this.WebChannel.unsubscriptionHandlers.push(() => this.handle_event({}, 'finalize'))
          console.log('Unsubscription handler installed')
      }, 100)
      """
      js = join_js([js, mounted_auto], "\n\n    ")
    end
    isempty(js) || push!(vue, field => JSONText("function(){\n    $js\n}"))
  end

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