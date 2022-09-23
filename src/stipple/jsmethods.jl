"""
    function js_methods(app::T) where {T<:ReactiveModel}

Defines js functions for the `methods` section of the vue element.

### Example

```julia
js_methods(app::MyDashboard) = \"\"\"
  mysquare: function (x) {
    return x^2
  }
  myadd: function (x, y) {
    return x + y
  }
\"\"\"
```
"""
function js_methods(app::T)::String where {T<:ReactiveModel}
  ""
end

function js_methods_events()::String
"""
  handle_event: function (event, handler) {
    Genie.WebChannels.sendMessageTo(window.CHANNEL, 'events', {
        'event': {
            'name': handler
        }
    })
  }
"""
end

"""
    function js_computed(app::T) where {T<:ReactiveModel}

Defines js functions for the `computed` section of the vue element.
These properties are updated every time on of the inner parameters changes its value.

### Example

```julia
js_computed(app::MyDashboard) = \"\"\"
  fullName: function () {
    return this.firstName + ' ' + this.lastName
  }
\"\"\"
```
"""
function js_computed(app::T)::String where {T<:ReactiveModel}
  ""
end

const jscomputed = js_computed

"""
    function js_watch(app::T) where {T<:ReactiveModel}

Defines js functions for the `watch` section of the vue element.
These functions are called every time the respective property changes.

### Example

Updates the `fullName` every time `firstName` or `lastName` changes.

```julia
js_watch(app::MyDashboard) = \"\"\"
  firstName: function (val) {
    this.fullName = val + ' ' + this.lastName
  },
  lastName: function (val) {
    this.fullName = this.firstName + ' ' + val
  }
\"\"\"
```
"""
function js_watch(m::T)::String where {T<:ReactiveModel}
  ""
end

const jswatch = js_watch

"""
    function js_created(app::T)::String where {T<:ReactiveModel}

Defines js statements for the `created` section of the vue element.
They are executed directly after the creation of the vue element.

### Example

```julia
js_created(app::MyDashboard) = \"\"\"
    if (this.cameraon) { startcamera() }
\"\"\"
```
"""
function js_created(app::T)::String where {T<:ReactiveModel}
  ""
end

const jscreated = js_created

"""
    function js_mounted(app::T)::String where {T<:ReactiveModel}

Defines js statements for the `mounted` section of the vue element.
They are executed directly after the mounting of the vue element.

### Example

```julia
js_created(app::MyDashboard) = \"\"\"
    if (this.cameraon) { startcamera() }
\"\"\"
```
"""
function js_mounted(app::T)::String where {T<:ReactiveModel}
  ""
end

const jsmounted = js_mounted

"""
    function client_data(app::T)::String where {T<:ReactiveModel}

Defines additional data that will only be visible by the browser.

It is meant to keep volatile data, e.g. form data that needs to pass a validation first.
In order to use the data you most probably also want to define [`js_methods`](@ref)
### Example

```julia
import Stipple.client_data
client_data(m::Example) = client_data(client_name = js"null", client_age = js"null", accept = false)
```
will define the additional fields `client_name`, `clientage` and `accept` for the model `Example`. These should, of course, not overlap with existing fields of your model.
"""
client_data(app::T) where T <: ReactiveModel = Dict{String, Any}()

client_data(;kwargs...) = Dict{String, Any}([String(k) => v for (k, v) in kwargs]...)