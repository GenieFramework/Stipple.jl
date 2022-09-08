# support for handling JS `undefined` values
export Undefined, UNDEFINED

struct Undefined
end

const UNDEFINED = Undefined()
const UNDEFINED_PLACEHOLDER = "__undefined__"
const UNDEFINED_VALUE = "undefined"

@json lower(x::Undefined) = UNDEFINED_PLACEHOLDER
Base.show(io::IO, x::Undefined) = Base.print(io, UNDEFINED_VALUE)