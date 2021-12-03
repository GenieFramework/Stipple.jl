# Basics


## Imports

At first, import the package:
```julia
>julia using Stipple
```

We then import `opts` and `OptDict` from Stipple.
```julia 
>julia import Stipple: opts, OptDict 
```

`opts` creates a dictionnary of Symbol `Any` of type `OptDict`:
```julia 
>julia OptDict
Dict{Symbol, Any}
```

As an illustration, let's define an `OptDict`:
```julia
>julia opts(hello = "world")
Dict{Symbol, Any} with 1 entry:
  :hello => "world"
```
We'll see later the usefulness of this function `opts`.

## Defining the model

Let's define our first model:
```julia 
Stipple.@kwdef mutable struct Example <: ReactiveModel 
    s::R{String} = "..."
    n::R{Int} = 1
    a::R{Array} = [3, 2, 1]
end
```
This concrete type `Example` will contain all the data that belong to the model. 
Note that we defined it with `Stipple.@kwdef` rather than `Base.@kwdef` at the beginning of the concrete type declaration. Indeed, if you use `Base.@kwdef`, you cannot redefine your code as you are developing your app. Then, `Stipple.@kwdef` is used here in order to be able to redefine the `Example` as the time we are developing the model.

This concrete type `Example` is a subtype of the abstract type `ReactiveModel`, which is the Stipple equivalent for a Vue element. 

### The Reactive type

Note that we have defined the elements of the `Example` with the following Type declaration:
```julia 
s::R{String}
n::R{Int}
a::R{Array}
```
rather than:
```julia 
s::String
n::Int
a::Array
```
The `R` keyword is just a shortcut for the `Reactive` type:
```julia
>julia R 
Reactive
```

This `Reactive`type is mainly a wrap of the `Observables`type:
```julia 
> julia using Observables 
> julia o = Observable(8)
 Observable{Int64} with 0 listeners. Value:
8
```
You can retrieve the content of the `Observable` such as:
```julia
>julia o[]
8 
```

You can assign a value:
```julia 
>julia o[] = 9 
9
```

The `Reactive` type works mostly the same way than the `Observable` one:
```julia
>julia R(8)
Reactive{Int64}(Observable{Int64} with 0 listeners. Value:
8, 0, false, false)
```

However, this `Reactive` type as some more properties that we will see later.

## Initializing the model

The next step is to initialize the model:
```julia 
>julia model = Stipple.init(Example())

Example(Reactive{String}(Observable{String} with 1 listeners. Value:
"...", 1, false, false), Reactive{Int64}(Observable{Int64} with 1 listeners. Value:
1, 1, false, false), Reactive{Array}(Observable{Array} with 1 listeners. Value:
[3, 2, 1], 1, false, false))
```

## Creating the user interface

Let's create the user interface now:
```julia 
function ui()
    page(vm(model), class = "container", title = "Hello Stipple", [
        h1("Hello World")
        p("I am the first paragraph and I bring you")
        p("", @text(:s))
    ]) |> html
end

```

This user interface is a `function` called when the page is called from the browser. 

This is a function that give nothing else than an `html` text, delivered to the browser.

### The page function

Let's decompose this function. Inside the function `ui()`, we use the `page` function. This function simply gives the basics of an `html` page with all the javascript that you need to communicate with Stipple:
```julia 
>julia page("text")
"<!DOCTYPE html>\n<html>\n<head>\n<title>\n\n</title>\n<meta name=\"viewport\" content=\"width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no\" />\n\n</head>\n<body class style>\n<link href=\"https://fonts.googleapis.com/css?family=Material+Icons\" rel=\"stylesheet\" />\n<link href=\"/stipple.jl/master/assets/css/stipplecore.css\" rel=\"stylesheet\" />\n\n<div id=\"text\" class=\"container\">\n\n</div>\n\n<script src=\"/genie.jl/master/assets/js/____/channels.js\">\n\n</script>\n<script src=\"/stipple.jl/master/assets/js/underscore-min.js\">\n\n</script>\n<script src=\"/stipple.jl/master/assets/js/vue.js\">\n\n</script>\n<script src=\"/stipple.jl/master/assets/js/stipplecore.js\" defer>\n\n</script>\n<script src=\"/stipple.jl/master/assets/js/vue_filters.js\" defer>\n\n</script>\n<script src=\"/stipple.jl/master/assets/js/watchers.js\">\n\n</script>\n<script>\nwindow.CHANNEL = '____';\n</script>\n<script src=\"/stipple.jl/master/assets/js/example.js\" defer onload=\"Stipple.init({theme: 'stipple-blue'});\">\n\n</script>\n\n</body>\n\n</html>\n"
```

### The vm function

For the next one, the `vm()`, you need to give the `model` name as an argument. It comes from the `View Model` from the javascript world.
```julia 
>julia vm(model)
"Example"
```

### HTML rendering functions

We used the functions `h1`, and `p` in this user interface declaration. These are just functions in Julia to define HTML header and paragraph:
```julia
>julia h1("Hello")
"<h1>\nHello\n</h1>\n"
``` 
```julia 
>julia p("World")
"<p>\nWorld\n</p>\n"
```

### The text macro

We used the `@text` macro in this function in order to render the `s` element of our `Example`.  

## Router

Next, we define the route to the ui function:
```julia 
>julia route("/", ui)
[GET] / => ui | :get
```







