import Genie.JSONParser: JSONParser, json

Base.string(js::JSONText) = json(js)
Base.:(*)(js::JSONText, x) = json(js) * x
Base.:(*)(x, js::JSONText) = x * json(js)
Base.:(*)(js1::JSONText, js2::JSONText) = JSONText(json(js1) * json(js2))

"""
    @js_str -> JSONText

Construct a JSONText, such as `js"button=false"`, without interpolation and unescaping
(except for quotation marks `"`` which still has to be escaped). Avoiding escaping `"`` can be done by
`js\"\"\"alert("Hello World")\"\"\"`.
"""
macro js_str(expr)
  :( JSONText($(esc(expr))) )
end