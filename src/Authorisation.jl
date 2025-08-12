"""
module Authorisation

Provides a collection of functions to handle user authorisation:
- `get_roles()`, `get_user()`, `is_authorised()`, `default_user()`, `default_role()`

They are predefined such that get_user(App) returns the default user, who has the role default_role(App) and is authorised.
In order to customize authorisation get_user(App) and get_roles(App) or is_authorised(App) need to be overwritten.

### Example 1 - Numbered Users and Admins for a all Apps
```julia
using Stipple, Stipple.ReactiveTools, Stipple.Authorisation

@app MyApp begin
    @in x = 1
end

# define roles as the first part of the string
Stipple.get_roles(::Type{<:ReactiveModel}, user::String) = String[split(user, '_')[1]]

# case 1: normal user
Stipple.get_user(::Type{<:ReactiveModel}) = "user_1"

get_roles(MyApp)
# ["user"]

is_authorised(MyApp)
# true

is_authorised(MyApp, role = "admin")
# false

# case 2: Admin
Stipple.get_user(::Type{MyApp}) = "admin_1"

get_roles(MyApp)
# ["admin"]

is_authorised(MyApp)
# false

is_authorised(MyApp, role = "admin")
# true
```

### Example 2 - User List via Roles for a single App
```julia
using Stipple, Stipple.ReactiveTools, Stipple.Authorisation

@app MyApp begin
    @in x = 1
end

# make roles identical to user
Stipple.get_roles(::Type{MyApp}, user::String) = [user]

# case 1: normal user
Stipple.get_user(::Type{MyApp}) = "user_1"

get_roles(MyApp)
# ["user_1"]

is_authorised(MyApp)
# false

userlist() = ["user_1", "admin_1"]
is_authorised(MyApp, role = userlist())
# true

# case 2: Admin
Stipple.get_user(::Type{MyApp}) = "admin_1"

get_roles(MyApp)
# ["admin_1"]

is_authorised(MyApp, role = userlist())
# true
```

### Example 3 - Overwriting `is_authorised()` for a specific implicit model
```julia
using Stipple, Stipple.ReactiveTools, Stipple.Authorisation

# define an implicit model
@app begin
    @in x = 1
end

userlist() = ["user_1", "admin_1"]

# define `App` as the module's implicit model
App = Stipple.@type

# define `is_authorised()` for the implicit App
# Note that it is important to allow for kwargs, because internal handling will call `is_authorised()` with the `role` kwarg.
Stipple.is_authorised(::Type{App}, user::String; kwargs...) = user ∈ userlist()

Stipple.get_user(::Type{App}) = "user_1"
is_authorised(App)
# true

Stipple.get_user(::Type{App}) = "user_2"
is_authorised(App)
# false

Stipple.get_user(::Type{App}) = "admin_1"
is_authorised(App)
# true
```

### Example 4 - applying authorisation to a Genie web application

```julia
using Stipple, Stipple.ReactiveTools, Stipple.Authorisation

@app MyApp begin
    @in x = 1
end

# define a admin check which returns nothing in case of success and a not-found-page in case of failure
admin_check() = is_authorised(MyApp, role = "admin") ? nothing : not_found()

ui() = "Hello Admin!"
@page("/", ui, model = MyApp, pre = admin_check)
up()

# define the role as first part of the string
Stipple.get_roles(::Type{MyApp}, user::String) = String[split(user, '_')[1]]

# case 1: normal user
Stipple.get_user(::Type{MyApp}) = "user_1"
Genie.Server.openbrowser("http://localhost:8000")
# not-found-page

Stipple.get_user(::Type{MyApp}) = "admin_1"
Genie.Server.openbrowser("http://localhost:8000")
# Hello Admin!
```
"""
module Authorisation

using Stipple

export default_user, default_role, get_user, get_roles, is_authorised, not_found

not_found() = throw(Genie.Exceptions.NotFoundException(Genie.Requests.matchedroute().path))

default_user(::Type)::String = "default"
default_user() = default_user(ReactiveModel)

default_role(::Type)::String = "user"
default_role() = default_role(ReactiveModel)

get_user(::Type{App}) where App <: ReactiveModel = default_user(App)
get_user() = get_user(ReactiveModel)

function get_roles(::Type{App}, user::String) where App
    user == default_user(App) ? [default_role(App)] : String[]
end

get_roles(::Type{App}) where App <: ReactiveModel = get_roles(App, get_user(App))
get_roles(user::String = get_user(ReactiveModel)) = get_roles(ReactiveModel, user)

function is_authorised(::Type{App}, user::String; role::Union{String, Vector{String}} = "user") where App
    roles = get_roles(App, user)
    if role isa String
        role ∈ roles
    else
        !isempty(intersect(role, roles))
    end
end

function is_authorised(::Type{App}; role::Union{String, Vector{String}} = "user") where App <: ReactiveModel
    is_authorised(App, get_user(App); role)
end

is_authorised(; role::Union{String, Vector{String}} = "user") = is_authorised(ReactiveModel; role)

end # module Authorisation