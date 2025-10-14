import Genie.JSONParser: JSONParser, json

Base.string(js::JSONText) = js.s
Base.:(*)(js::JSONText, x) = js.s * x
Base.:(*)(x, js::JSONText) = x * js.s
Base.:(*)(js1::JSONText, js2::JSONText) = JSONText(js1.s * js2.s)

"""
    @js_str -> JSONText

Construct a JSONText, such as `js"button=false"`, without interpolation and unescaping
(except for quotation marks `"`` which still has to be escaped). Avoiding escaping `"`` can be done by
`js\"\"\"alert("Hello World")\"\"\"`.
"""
macro js_str(expr)
  :( JSONText($(esc(expr))) )
end