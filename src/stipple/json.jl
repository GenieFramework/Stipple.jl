import Genie.JSONParser: JSONParser, json

Base.string(js::JSONText) = json(js)
Base.:(*)(js::JSONText, x) = json(js) * x
Base.:(*)(x, js::JSONText) = x * json(js)
Base.:(*)(js1::JSONText, js2::JSONText) = JSONText(json(js1) * json(js2))

"""
    js" -> JSONText

Construct a JSONText. String interpolation is supported via the `i` flag.
Special characters `'\\n'`, `'\\t'` `'\\\\'` need to be escaped like in regular Strings,
e.g. `js"Hello World\\nit's a great day!"`. Other escapings are not supported.
Usage of triple quotes is recommended for js syntax highlighting in many editors, e.g. VS code.
### Examples
```
js\"\"\"alert("Hello World")\"\"\"
# JSONText("alert(\"Hello World\")")

js\"\"\"alert("1 + 2 == \$(1 + 2)")\"\"\"i
# JSONText("alert(\"1 + 2 == 3\")")
```
"""
macro js_str(s, flags="")
  isempty(flags) || flags == "i" || @warn "Only 'i' flag currently supported (string interpolation)."
  interpolate = 'i' in flags

  parts = Any[]
  io = IOBuffer()

  i = 1
  len = lastindex(s)
  backslash_odd = false

  while i ≤ len
    c = s[i]

    if c == '\\'
      # only write one of consecutive backslashes
      backslash_odd || write(io, c)
      backslash_odd = ! backslash_odd
      i = nextind(s, i)
    elseif c == '$' && ! backslash_odd && interpolate
      # parse content after non-escaped '$'

      # push io content to parts
      io.size > 0 && push!(parts, String(take!(io)))

      expr, i = Meta.parse(s, nextind(s, i), greedy=false)

      if expr === nothing || expr == :()
          throw(Meta.ParseError("syntax: empty interpolation in string"))
      end

      # push parsed content to parts
      push!(parts, esc(expr))
    else
      # if a backslash precedes the character, overwrite the backslash with the unescaped form
      if backslash_odd
        seek(io, position(io) - 1)
        if c == 'n'
          c = '\n'
        elseif c == 't'
          c = '\t'
        elseif c != '$'
          throw(ArgumentError("invalid escape character '\\$c' in js_str"))
        end
      end
      write(io, c)
      backslash_odd = false
      i = nextind(s, i)
    end
  end

  io.size > 0 && push!(parts, String(take!(io)))

  :( JSONText(string($(parts...))) )
end