import Genie.JSONParser: JSONParser, json

Base.string(js::JSONText) = json(js)
Base.:(*)(js::JSONText, x) = json(js) * x
Base.:(*)(x, js::JSONText) = x * json(js)
Base.:(*)(js1::JSONText, js2::JSONText) = JSONText(json(js1) * json(js2))

"""
    @js_str -> JSONText

Construct a JSONText, such as `js"button=false"`, without interpolation and unescaping
(except for quotation marks `"`` which still has to be escaped). Avoiding escaping `"`` can be done by
```
js\"\"\"alert("Hello World")\"\"\"
# JSONText("alert(\"Hello World\")")
```
Interpolation and escaping is supported via the `i` flag, such as
```
js\"\"\"alert("1 + 2 == \$(1 + 2)")\"\"\"i
# JSONText("alert(\"1 + 2 == 3\")")
```
"""
macro js_str(s)
  :( JSONText($(esc(s))) )
end

macro js_str(s, flags)
  flags == "i" || @warn "Only 'i' flag currently supported (string interpolation)."
  if 'i' in flags
    :( JSONText($(esc(Meta.parse("\"$s\"")))) )
  else
    :( JSONText($(esc(s))) )
  end
end