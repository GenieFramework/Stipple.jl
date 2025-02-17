struct JSFunction
  arguments::String
  body::String
end

JSFunction(s::Symbol...; body = "") = JSFunction(join(s, ", "), "$body")
JSFunction(s1::Symbol, body::Union{AbstractString, JSONText} = "") = JSFunction("$s1", "$body")
JSFunction(s1::Symbol, s2::Symbol, body::Union{AbstractString, JSONText} = "") = JSFunction(join([s1, s2], ", "), "$body")
JSFunction(s1::Symbol, s2::Symbol, s3::Symbol, body::Union{AbstractString, JSONText} = "") = JSFunction(join([s1, s2, s3], ", "), "$body")
JSFunction(s1::Symbol, s2::Symbol, s3::Symbol, s4::Symbol, body::Union{AbstractString, JSONText} = "") = JSFunction(join([s1, s2, s3, s4], ", "), "$body")

StructTypes.StructType(::Type{JSFunction}) = StructTypes.CustomStruct()
StructTypes.lower(jsfunc::JSFunction) = Dict(:jsfunction => OrderedDict(:arguments => jsfunc.arguments, :body => jsfunc.body))

function Stipple.render(jsfunc::JSFunction)
  opts(jsfunction = opts(arguments = jsfunc.arguments; body = jsfunc.body))
end

function Stipple.jsrender(jsfunc::JSFunction, args...)
  body = rstrip(jsfunc.body)
  body = contains(body, '\n') ? "\n$body\n" : " $body "
  JSONText("function($(jsfunc.arguments)) {$body}")
end

"""
    function parse_jsfunction(s::AbstractString)

Checks whether the string is a valid js function and returns a `Dict` from which a reviver function
in the backend can construct a function.
"""
function parse_jsfunction(s::AbstractString)
    # look for classical function definition (not a full syntax check, though)
    m = match( r"^\s*function\s*\(([^)]*)\)\s*{(.*)}\s*$"s, s)
    !isnothing(m) && length(m.captures) == 2 && return JSFunction(m[1], m[2])
    
    # look for pure function definition including unbracketed single parameter
    m = match( r"^\s*\(?([^=<>:;.(){}\[\]]*?)\)?\s*=>\s*({*.*?}*)\s*$"s , s )
    (isnothing(m) || length(m.captures) != 2) && return nothing
    
    # if pure function body is without curly brackets, add a `return`, otherwise strip the brackets
    # Note: for utf-8 strings m[2][2:end-1] will fail if the string ends with a wide character, e.g. ϕ
    body = startswith(m[2], "{") ? m[2][2:prevind(m[2], lastindex(m[2]))] : "return " * m[2]
    return JSFunction(m[1], body)
end

"""
    function replace_jsfunction!(js::Union{Dict, JSONText})

Replaces all JSONText values that contain a valid js function by a `Dict` that codes the function for a reviver.
For JSONText variables it encapsulates the dict in a JSONText to make the function type stable.
"""
replace_jsfunction!(x) = x # fallback is identity function

function replace_jsfunction!(d::Dict)
    for (k,v) in d
        if isa(v, Dict) || isa(v, Array)
            replace_jsfunction!(v)
        elseif isa(v, JSONText)
            jsfunc = parse_jsfunction(v.s)
            isnothing(jsfunc) || ( d[k] = opts(jsfunction=jsfunc) )
        end
    end
    return d
end

function replace_jsfunction!(v::Array)
  replace_jsfunction!.(v)
end

"""
Replaces all JSONText values on a copy of the input, see [`replace_jsfunction!`](@ref).
"""
function replace_jsfunction(d::Dict)
  replace_jsfunction!(deepcopy(d))
end

function replace_jsfunction(v::Vector)
  replace_jsfunction!.(deepcopy(v))
end

function replace_jsfunction(js::JSONText)
    jsfunc = parse_jsfunction(js.s)
    isnothing(jsfunc) ? js : JSONText(json(opts(jsfunction=jsfunc)))
end

replace_jsfunction(s::AbstractString) = replace_jsfunction(JSONText(s))

"""
    function jsfunction(jscode::String)

Build a dictionary that is converted to a js function in the frontend by the reviver.
There is also a string macro version `jsfunction"<js code>"`
"""
function jsfunction(jscode::String)
  jsfunc = parse_jsfunction(jscode)
  isnothing(jsfunc) ? JSFunction("", jscode) : jsfunc
end

"""
    jsfunction"<js code>"

Build a dictionary that is converted to a js function in the frontend by the reviver.
"""
macro jsfunction_str(expr)
  :( jsfunction($(esc(expr))) )
end

"""
    function Base.run(model::ReactiveModel, jscode::String; context = :model)

Execute js code in the frontend. `context` can be `:model`, `:app` or `:console`
"""
function Base.run(model::ReactiveModel, jscode::String; context = :model, kwargs...)
  context ∈ (:model, :app) && return push!(model, Symbol("js_", context) => jsfunction(jscode); channel = getchannel(model), kwargs...)
  context == :console && push!(model, :js_model => jsfunction("console.log('$jscode')"); channel = getchannel(model), kwargs...)

  nothing
end

function isconnected(model, message::AbstractString = "")
    push!(model, :js_model => jsfunction("console.log('$message')"); channel = getchannel(model))
end

"""
  function Base.setindex!(model::ReactiveModel, val, index::AbstractString)

Set model fields or subfields on the client.
```
model["plot.data[0].selectedpoints"] = [1, 3]
model["table_selection"] = rowselection(model.table[], [2, 4])
```
Note:
- Array indices are zero-based because the code is executed on the client side
- Table indices are 1-based because they rely on the hidden "__id" columns, which is one-based
"""
function Base.setindex!(model::ReactiveModel, val, index::AbstractString)
  run(model, "this.$index = $(strip(json(render(val)), '"'))")
end

"""
  function Base.notify(model::ReactiveModel, field::JSONText)

Notify model fields or subfields on the client side. Typically used after
```
model["plot.data[0].selectedpoints"] = [1, 3]
notify(model, js"plot.data")
```
"""
function Base.notify(model::ReactiveModel, field::JSONText)
  run(model, "this.$(field.s).__ob__.dep.notify()")
end