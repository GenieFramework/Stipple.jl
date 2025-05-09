"""
    function js_methods(::Type{<:T}) where {T<:ReactiveModel}

Defines js functions for the `methods` section of the vue element.
Expected result types of the function are
  - `String` containing javascript code
  - `Pair` of function name and function code
  - `Function` returning String of javascript code
  - `Dict` of function names and function code
  - `Vector` of the above

### Example 1

```julia
js_methods(::Type{<:MyDashboard}) = \"\"\"
  mysquare: function (x) {
    return x^2
  }
  myadd: function (x, y) {
    return x + y
  }
\"\"\"
```
### Example 2
```
js_methods(::Type{<:MyDashboard}) = Dict(:f => "function(x) { console.log('x: ' + x) })
```
### Example 3
```
js_greet() = :greet => "function(name) {console.log('Hello ' + name)}"
js_bye() = :bye => "function() {console.log('Bye!')}"
js_methods(::Type{<:MyDashboard}) = [js_greet, js_bye]
```
"""
js_methods(::DataType) = ""
js_methods(::T) where T = js_methods(T)

# deprecated, now part of the model
function js_methods_events()::String
"""
  handle_event: function (event, handler) {
    Genie.WebChannels.sendMessageTo(GENIEMODEL.channel_, 'events', {
        'event': {
            'name': handler,
            'event': event
        }
    })
  }
"""
end

"""
    function js_computed(::Type{<:T}) where {T<:ReactiveModel}

Defines js functions for the `computed` section of the vue element.
These properties are updated every time on of the inner parameters changes its value.
Expected result types of the function are
  - `String` containing javascript code
  - `Pair` of function name and function code
  - `Function` returning String of javascript code
  - `Dict` of function names and function code
  - `Vector` of the above

### Example

```julia
js_computed(app::MyDashboard) = \"\"\"
  fullName: function () {
    return this.firstName + ' ' + this.lastName
  }
\"\"\"
```
"""
js_computed(::DataType) = ""
js_computed(::T) where T = js_computed(T)

const jscomputed = js_computed

"""
    function js_watch(::Type{<:T}) where {T<:ReactiveModel}

Defines js functions for the `watch` section of the vue element.
These functions are called every time the respective property changes.
Expected result types of the function are
  - `String` containing javascript code
  - `Pair` of function name and function code
  - `Function` returning String of javascript code
  - `Dict` of function names and function code
  - `Vector` of the above

### Example

Updates the `fullName` every time `firstName` or `lastName` changes.

```julia
js_watch(::Type{<:MyDashboard}) = \"\"\"
  firstName: function (val) {
    this.fullName = val + ' ' + this.lastName
  },
  lastName: function (val) {
    this.fullName = this.firstName + ' ' + val
  }
\"\"\"
```
"""
js_watch(::DataType) = ""
js_watch(::T) where T = js_watch(T)

const jswatch = js_watch

"""
    function client_data(::Type{<:MyApp})::String

Defines additional data that will only be visible by the browser.

It is meant to keep volatile data, e.g. form data that needs to pass a validation first.
In order to use the data you most probably also want to define [`js_methods`](@ref)
### Example

```julia
import Stipple.client_data
client_data(::Type{<:Example}) = client_data(client_name = js"null", client_age = js"null", accept = false)
```
will define the additional fields `client_name`, `client_age` and `accept` for models of type `Example`.
These definitions should, of course, not overlap with existing fields of your model.
### Note
Previously we defined the client_data function differently. This will continue to work,
but the new way might have some advantages in the future for mixins. Here is the old way:
```julia
client_data(::Example) = client_data(client_name = js"null", client_age = js"null", accept = false)
```
"""
client_data(::Type{<:ReactiveModel}) = Dict{String, Any}()
client_data(::T) where T = client_data(T)

client_data(; kwargs...) = Dict{String, Any}([String(k) => v for (k, v) in kwargs]...)

for (f, field) in (
  (:js_before_create, :beforeCreate), (:js_created, :created), (:js_before_mount, :beforeMount), (:js_mounted, :mounted),
  (:js_before_update, :beforeUpdate), (:js_updated, :updated), (:js_activated, :activated), (:js_deactivated, :deactivated),
  (:js_before_destroy, :beforeDestroy), (:js_destroyed, :destroyed), (:js_error_captured, :errorCaptured),)

  field_str = string(field)
  Core.eval(@__MODULE__, quote
    """
        function $($f)(::Type{<:T})::Union{Function, String, Vector} where {T<:ReactiveModel}

    Defines js statements for the `$($field_str)` section of the vue element.

    Result types of the function can be
    - `String` containing javascript code
    - `Function` returning String of javascript code
    - `Vector` of the above

    ### Example 1

    ```julia
    $($f)(::Type{<:MyDashboard}) = \"\"\"
        if (this.cameraon) { startcamera() }
    \"\"\"
    ```

    ### Example 2

    ```julia
    startcamera() = "if (this.cameraon) { startcamera() }"
    stopcamera() = "if (this.cameraon) { stopcamera() }"

    $($f)(::Type{<:MyDashboard}) = [startcamera, stopcamera]
    ```
    Checking the result can be done in the following way
    ```
    julia> render(MyApp())[:$($field_str)]
    JSONText("function(){\n    if (this.cameraon) { startcamera() }\n\n    if (this.cameraon) { stopcamera() }\n}")
    ```
    ### Note
    Previously we defined the function differently. This will continue to work,
    but the new way might have some advantages in the future for mixins. Here is the old way:
    ```julia
    $($f)(::MyDashboard) = [startcamera, stopcamera]
    ```
    """
    $f(::Type{<:ReactiveModel})::String = ""
    $f(::T) where T = $f(T)
  end)
end

const jscreated = js_created
const jsmounted = js_mounted

"""
    js_add_reviver(revivername::String)

Add a reviver function to the list of Genie's revivers.

### Example

Adding the reviver function of 'mathjs'
```julia
js_add_reviver("math.reviver")
```
This function is meant for package developer who want to make additional js content available for the user.
This resulting script needs to be added to the dependencies of an app in order to be executed.
For detailed information have a look at the package StippleMathjs.

If you want to add a custom reviver to your model you should rather consider using `@mounted`, e.g.

```julia
@methods \"\"\"
myreviver: function(key, value) { return (key.endsWith('_onebased') ? value - 1 : value) }
\"\"\"
@mounted "Genie.Revivers.addReviver(this.myreviver)"
```
"""  
function js_add_reviver(revivername::String)
  """
  document.addEventListener('DOMContentLoaded', () => Genie.WebChannels.subscriptionHandlers.push(function(event) {
      Genie.Revivers.addReviver($revivername);
  }));
  """
end

"""
    js_add_serializer(serializername::String)

Add a serializer function to the list of Genie's serializers.

This function is meant for package developer who want to make additional js content available for the user.
This resulting script needs to be added to the dependencies of an app in order to be executed.

If you want to add a custom serializer to your model you should rather consider using `@mounted`, e.g.

```julia
@methods \"\"\"
myserializer: function(value) { return value + 1 }
\"\"\"
@mounted "Genie.Serializers.addSerializer(this.myserializer)"
```
"""
function js_add_serializer(serializername::String)
  """
  document.addEventListener('DOMContentLoaded', () => Genie.WebChannels.subscriptionHandlers.push(function(event) {
      Genie.Serializers.addSerializer($serializername);
  }));
  """
end

"""
    js_initscript(initscript::String)

Add a js script that is executed as soon as the connection to the server is established.
It needs to be added to the dependencies of an app in order to be executed, e.g.

```julia
@deps () -> [script(js_initscript("console.log('Hello from my App')"))]
```
"""
function js_initscript(initscript::String)
  """
  document.addEventListener('DOMContentLoaded', () => Genie.WebChannels.subscriptionHandlers.push(function(event) {
      $(initscript)
  }));
  """
end

js_created_auto(::DataType) = ""
js_created_auto(::T) where T = js_created_auto(T)

js_watch_auto(::DataType) = ""
js_watch_auto(::T) where T = js_watch_auto(T)

# methods to be used directly as arguments to js_methods

export add_click_info

"""
    add_click_info()

Adds information about the click event to the event object.

### Example
```julia
@app begin
    @in x = 1
end

@methods add_click_info

@event :myclick begin
    @info event
    notify(__model__, "(x, y) clicked: (\$(event["clientX"]), \$(event["clientY"]))")
end

ui() = cell("Hello world!", @on(:click, :myclick, :addClickInfo))
"""
function add_click_info()
  :addClickInfo => js"""function (event) {
    console.log('Hi')
      new_event = {}
      new_event.x = event.x
      new_event.y = event.y
      new_event.offsetX = event.offsetX
      new_event.offsetY = event.offsetY
      new_event.layerX = event.layerX
      new_event.layerY = event.layerY
      new_event.pageX = event.pageX
      new_event.pageY = event.pageY
      new_event.screenX = event.screenX
      new_event.screenY = event.screenY
      
      new_event.button = event.button
      new_event.buttons = event.buttons
      new_event.ctrlKey = event.ctrlKey
      new_event.shiftKey = event.shiftKey
      new_event.altKey = event.altKey
      new_event.metaKey = event.metaKey
      new_event.detail = event.detail
      new_event.target = event.target
      new_event.timeStamp = event.timeStamp
      new_event.type = event.type
      return {...new_event, ...event}
  }
  """
end