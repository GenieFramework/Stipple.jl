@testset "Classic API" begin
    @vars TestApp begin
        i = 100
        s = "Hello", READONLY
    end

    function handlers(model)
        on(model.i) do i
            model.s[] = "$i"
        end

        model
    end

    model = TestApp |> init |> handlers
    model2 = TestApp |> init |> handlers

    # channels have to be different
    @test model.channel__ != model2.channel__

    # check whether fields are correctly defined
    @test propertynames(model) == tuple(Stipple.INTERNALFIELDS..., Stipple.AUTOFIELDS..., :i, :s)

    # check reactivity
    model.i[] = 20
    @test model.s[] == "20"
end
@testitem "Classic API with mixins" setup=[StippleTests] begin
  @test StippleTests.TestMixin isa DataType
end

@testitem "Classic API with mixins" setup=[StippleTests] begin
    TestMixin = StippleTests.TestMixin
    @vars TestApp begin
        i = 100
        s = "Hello"
        @mixin TestMixin
        @mixin mixin_::TestMixin
        @mixin TestMixin pre_ _post
    end

    function handlers(model)
        on(model.i) do i
            model.s[] = "$i"
        end

        model
    end

    model = TestApp |> init |> handlers
    @test propertynames(model) == tuple(Stipple.INTERNALFIELDS..., Stipple.AUTOFIELDS..., :i, :s, :j, :t, :mixin_j, :mixin_t, :pre_j_post, :pre_t_post)
end


@testitem "Reactive API (explicit)" begin
    using Stipple.ReactiveTools
    @app TestApp2 begin
        @in i = 100
        @out s = "Hello"

        @onchange i begin
            s = "$i"
        end
    end

    model = @init TestApp2
    model2 = @init TestApp2

    # channels have to be different
    @test model.channel__ != model2.channel__

    # check whether fields are correctly defined
    @test propertynames(model) == tuple(Stipple.INTERNALFIELDS..., Stipple.AUTOFIELDS..., :i, :s)

    # check reactivity
    model.i[] = 20
    @test model.s[] == "20"
end

@testitem "Reactive API (explicit) with mixins and handlers" setup=[StippleTests] begin
    using Stipple.ReactiveTools
    TestMixin = StippleTests.TestMixin

    @app TestApp begin
        @in i = 100
        @out s = "Hello"

        @mixin TestMixin
        @mixin mixin_::TestMixin
        @mixin TestMixin "pre_" "_post"

        @onchange i begin
            s = "$i"
        end
    end

    model = TestApp |> init |> TestApp_handlers
    @test propertynames(model) ==  tuple(Stipple.INTERNALFIELDS..., Stipple.AUTOFIELDS..., :i, :s, :j, :t, :mixin_j, :mixin_t, :pre_j_post, :pre_t_post)

    # check reactivity
    model.i[] = 20
    @test model.s[] == "20"

    @debounce TestApp i 101
    @debounce TestApp (a, b, c) 101
    @test Stipple.DEBOUNCE[TestApp][:i] == 101

    @clear_debounce TestApp
    @test haskey(Stipple.DEBOUNCE, TestApp) == false
end

@testitem "Reactive API (implicit)" begin
    using Stipple.ReactiveTools
    @app begin
        @in i2 = 100
        @out s2 = "Hello"

        @onchange i2 begin
            s2 = "$i2"
        end
    end

    model = @init
    model2 = @init

    # channels have to be different
    @test model.channel__ != model2.channel__

    # check whether fields are correctly defined
    @test propertynames(model) ==  tuple(Stipple.INTERNALFIELDS..., Stipple.AUTOFIELDS..., :i2, :s2)

    # check reactivity
    model.i2[] = 20
    @test model.s2[] == "20"

    # check field-specific debouncing
    @debounce i3 101
    @debounce (a, b, c) 101
    @test Stipple.DEBOUNCE[Stipple.@type()][:i3] == 101

    @clear_debounce
    @test haskey(Stipple.DEBOUNCE, Stipple.@type()) == false
end

@testitem "Reactive API (implicit) with mixins and handlers" setup=[StippleTests] begin
    using Stipple.ReactiveTools
    TestMixin = StippleTests.TestMixin

    @app begin
        @in i3 = 100
        @out s3 = "Hello"

        @mixin TestMixin
        @mixin mixin_::TestMixin
        @mixin TestMixin "pre_" "_post"

        @onchange i3 begin
            s3 = "$i3"
        end
    end

    model = @init
    @test propertynames(model) ==  tuple(Stipple.INTERNALFIELDS..., Stipple.AUTOFIELDS..., :i3, :s3, :j, :t, :mixin_j, :mixin_t, :pre_j_post, :pre_t_post)

    model.i3[] = 20
    @test model.s3[] == "20"
end

@testmodule App1 begin
    using Stipple, Stipple.ReactiveTools
    @app begin
        @in i1 = 101
    end

    @app MyApp begin
        @in i1 = 101
    end
end

@testmodule App2 begin
    using Stipple, Stipple.ReactiveTools

    @app begin
        @in i2 = 102
    end

    @app MyApp begin
        @in i2 = 102
    end
end

@testitem "Multipage Reactive API (implicit)" setup=[StippleTests, App1, App2] begin
    using Stipple.ReactiveTools
    get_channel = StippleTests.get_channel

    p1 = @page("/app1", "hello", model = App1)
    p2 = @page("/app2", "world", model = App2)
    
    channel1a = get_channel(String(p1.route.action().body))
    channel1b = get_channel(String(p1.route.action().body))
    channel2a = get_channel(String(p2.route.action().body))
    channel2b = get_channel(String(p2.route.action().body))

    # channels have to be different
    @test channel1a != channel1b != channel2a != channel2b
end

@testitem "Multipage Reactive API (explicit)" setup=[StippleTests, App1, App2] begin
    using Stipple.ReactiveTools
    get_channel = StippleTests.get_channel

    p1 = @page("/app1", "hello", model = App1.MyApp)
    p2 = @page("/app2", "world", model = App2.MyApp)
    channel1a = get_channel(String(p1.route.action().body))
    channel1b = get_channel(String(p1.route.action().body))
    channel2a = get_channel(String(p2.route.action().body))
    channel2b = get_channel(String(p2.route.action().body))

    # channels have to be different
    @test channel1a != channel1b != channel2a != channel2b
end

using DataFrames
@testitem "Extensions" begin
    using DataFrames

    d1 = Dict(:a => [1, 2, 3], :b => ["a", "b", "c"])
    d2 = Dict(:a => [2, 3, 4], :b => ["b", "c", "d"])
    df1 = DataFrame(d1)
    df2 = DataFrame(:a => [[1, 2, 3], [2, 3, 4]], :b => [["a", "b", "c"], ["b", "c", "d"]])
    @test Stipple.stipple_parse(DataFrame, d1) == df1
    @test Stipple.stipple_parse(DataFrame, [d1, d2]) == df2
    @test render(df1) == OrderedDict("a" => [1, 2, 3], "b" => ["a", "b", "c"])

    using OffsetArrays
    @test Stipple.convertvalue(R(OffsetArray([1, 2, 3], -2)), [2, 3, 4]) == OffsetArray([2, 3, 4], -2)
end


# Basic rendering tests (should be enhanced over time perhaps...)
# These tests should probably be repeated in StippleUI to make sure rendering is not overwritten
@testitem "Rendering" begin
    using Tables, DataFrames

    ds = Dict("hello" => [1, 2, 3, 4], "world" => ["five", "six"])
    @test render(ds) == ds

    vd = [Dict("hello" => 1, "world" => 2)]
    @test render(vd) == vd

    df = DataFrame(:a => [1, 2, 3], :b => ["a", "b", "c"])
    @test render(df) == OrderedDict("a" => [1, 2, 3], "b" => ["a", "b", "c"])

    mt = Tables.table([1 2; 3 4])
    @test render(mt) == OrderedDict(:Column1 => [1, 3], :Column2 => [2, 4])
end

# Basic server tests (should be enhanced over time perhaps...)

@testitem "Serving implicit app" setup=[StippleTests] begin
    using Stipple
    using Stipple.ReactiveTools
    #using ..Pkg
    @test "0" != Genie.Assets.package_version(Stipple)
    
    get_channel = StippleTests.get_channel
    get_debounce = StippleTests.get_debounce
    string_get = StippleTests.string_get

    empty!(Genie.Router._routes)
    begin
        @app begin
            @in i3 = 100
            @out s3 = "Hello"

            @onchange i3 begin
                s3 = "$i3"
            end
        end

        ui() = "DEMO UI"
        debounce = 10
    end

    model = @init
    app_js_name = lowercase(vm(model))
    
    begin
        @page("/", ui)
        @page("/nolayout", ui, layout = "no layout")
        @page("/debounce1", ui, debounce = 50)
        @page("/debounce2", ui; debounce)
        @page("/static", ui; model)
    end

    port = rand(8001:9000)
    up(;port, ws_port = port)

    @test occursin(">DEMO UI<", string_get("http://localhost:$port"))

    @test contains(string_get("http://localhost:$port/nolayout"), r"<!DOCTYPE html><html>\n  <body>\s*(<p>)?no layout(</p>)?\s*</body></html>")
    @test get_debounce(port, app_js_name) == 300

    @clear_cache
    # first get the main page to trigger init function, which sets up the assets
    string_get("http://localhost:$port/debounce1")
    @test get_debounce(port, app_js_name) == 50

    @clear_cache
    string_get("http://localhost:$port/debounce2")
    @test get_debounce(port, app_js_name) == 10

    s1 = string_get("http://localhost:$port/")
    s2 = string_get("http://localhost:$port/")
    s3 = string_get("http://localhost:$port/", cookies = false)

    s4 = string_get("http://localhost:$port/static")
    s5 = string_get("http://localhost:$port/static")
    s6 = string_get("http://localhost:$port/static", cookies = false)

    @test get_channel(s2) == get_channel(s1)
    @test get_channel(s3) != get_channel(s1)
    @test get_channel(s4) == get_channel(s5) == get_channel(s6)

    @clear_cache
    down()
end

@testitem "Serving explicit app" setup=[StippleTests] begin
    using Stipple.ReactiveTools

    get_debounce = StippleTests.get_debounce
    string_get = StippleTests.string_get
    get_channel = StippleTests.get_channel

    begin
        @app MyApp begin
            @in i3 = 100
            @out s3 = "Hello"

            @onchange i3 begin
                s3 = "$i3"
            end
        end

        ui() = "DEMO UI explicit"
        debounce = 11
    end

    model = @init(MyApp)
    app_js_name = lowercase(vm(model))


    begin
        @page("/", ui; model = MyApp)
        @page("/nolayout", ui, layout = "no layout (explicit)", model = MyApp)
        @page("/debounce3", ui, debounce = 51; model = MyApp)
        @page("/debounce4", ui; debounce, model = MyApp)
        @page("/static1", ui; model)
    end

    port = rand(8001:9000)
    up(;port, ws_port = port)

    @clear_cache MyApp
    @test occursin(">DEMO UI explicit<", string_get("http://localhost:$port"))

    @test contains(string_get("http://localhost:$port/nolayout"), r"<!DOCTYPE html><html>\n  <body>\s*(<p>)?no layout \(explicit\)(</p>)?\s*</body></html>")

    @test get_debounce(port, app_js_name) == 300

    @clear_cache MyApp
    # first get the main page to trigger init function, which sets up the assets
    string_get("http://localhost:$port/debounce3")
    @test get_debounce(port, app_js_name) == 51

    @clear_cache MyApp
    string_get("http://localhost:$port/debounce4")
    @test get_debounce(port, app_js_name) == 11

    s1 = string_get("http://localhost:$port/")
    s2 = string_get("http://localhost:$port/")
    s3 = string_get("http://localhost:$port/", cookies = false)

    s4 = string_get("http://localhost:$port/static")
    s5 = string_get("http://localhost:$port/static")
    s6 = string_get("http://localhost:$port/static", cookies = false)

    @test get_channel(s2) == get_channel(s1)
    @test get_channel(s3) != get_channel(s1)
    @test get_channel(s4) == get_channel(s5) == get_channel(s6)

    @clear_cache MyApp
    down()
end

# attribute testing

@testitem "Flexgrid attributes for row(), column(), and cell()" begin

    el = column(col = 2, sm = 9, class = "myclass")
    @test contains(el, "class=\"myclass column col-2 col-sm-9")

    el = column(col = 2, sm = 9, class = :myclass)
    @test contains(el, ":class=\"[myclass,'column','col-2','col-sm-9']\"")

    el = column(col = 2, sm = 9, class! = "myclass")
    @test contains(el, ":class=\"[myclass,'column','col-2','col-sm-9']\"")

    el = column(col = 2, sm = 9, class! = :myclass)
    @test contains(el, ":class=\"[myclass,'column','col-2','col-sm-9']\"")

    # ---------

    el = row(col = 2, sm = 9, class = "myclass")
    @test contains(el, "class=\"myclass row col-2 col-sm-9")

    el = row(col = 2, sm = 9, class = :myclass)
    @test contains(el, ":class=\"[myclass,'row','col-2','col-sm-9']\"")

    el = row(col = 2, sm = 9, class! = "myclass")
    @test contains(el, ":class=\"[myclass,'row','col-2','col-sm-9']\"")

    # ---------

    el = cell(col = 2, sm = 9, class = "myclass")
    @test contains(el, "class=\"myclass st-col col-2 col-sm-9")

    el = cell(col = 2, sm = 9, class = :myclass)
    @test contains(el, ":class=\"[myclass,'st-col','col-2','col-sm-9']\"")

    el = column(col = 2, sm = 9, class! = "myclass")
    @test contains(el, ":class=\"[myclass,'column','col-2','col-sm-9']\"")

    @test cell(sm = 9) == "<div class=\"st-col col col-sm-9\"></div>"

    @test cell(col = -1, sm = 9) == "<div class=\"st-col col-sm-9\"></div>"

    @test htmldiv(col = 9, class = "a b c") == "<div class=\"a b c col-9\"></div>"

    @test htmldiv(col = 9, class = split("a b c")) == "<div :class=\"['a','b','c','col-9']\"></div>"

    @test htmldiv(col = 9, class = Dict(:myclass => "b"), class! = "test") == "<div :class=\"[test,{'myclass':b},'col-9']\"></div>"

    @test row(@gutter :sm [
        cell("Hello", sm = 2,  md = 8)
        cell("World", sm = 10, md = 4)
    ]).data == "<div class=\"row q-col-gutter-sm\"><div class=\"col col-sm-2 col-md-8\">" *
    "<div class=\"st-col\">Hello</div></div><div class=\"col col-sm-10 col-md-4\"><div class=\"st-col\">World</div></div></div>"
end

@testitem "Vue Conditionals and Iterator" begin
    el = column("Hello", @if(:visible))
    @test contains(el, "v-if=\"visible\"")

    el = column("Hello", @else)
    @test contains(el, "v-else")

    el = column("Hello", @elseif(:visible))
    @test contains(el, "v-else-if=\"visible\"")

    el = row(@showif("n > 0"), "The result is '{{ n }}'")
    @test el == "<div v-show=\"n > 0\" class=\"row\">The result is '{{ n }}'</div>"

    el = row(@for("i in [1, 2, 3, 4, 5]"), "{{ i }}")
    @test contains(el, "v-for=\"i in [1, 2, 3, 4, 5]\"")

    # test Julia expressions
    el = row(@showif(:n > 0), "The result is '{{ n }}'")
    @test el == "<div v-show=\"n > 0\" class=\"row\">The result is '{{ n }}'</div>"

    el =  row("hello", @showif(:n^2 ∉ 3:2:11))
    @test el == "<div v-show=\"!((n ** 2) in [3,5,7,9,11])\" class=\"row\">hello</div>"

    @enum Fruit apple=1 orange=2 kiwi=3

    fruit = apple

    el = row(@showif(:fruit == apple), "My fruit is a(n) '{{ fruit }}'")
    @test el == "<div v-show=\"fruit == 'apple'\" class=\"row\">My fruit is a(n) '{{ fruit }}'</div>"
    
    el = htmldiv("Hello World", Stipple.@showif(:s == """abc"d"e"""))
    @test contains(el, raw"""<div v-show="s == 'abc\'d\'e'">""")
end

@testitem "Compatibility of JSONText between JSON3 and JSON" begin
    using JSON
    using Stipple
    jt1 = JSON.JSONText("json text 1")
    jt2 = Stipple.JSONText("json text 2")
    @test JSON.json(jt1) == "json text 1"
    @test Stipple.json(jt1) == "json text 1"
    @test JSON.json(jt2) == "json text 2"
    @test Stipple.json(jt2) == "json text 2"
end

@testitem "Javascript expressions: JSExpr" begin
    # note, you cannot compare a JSExpr by `==` directly as `==` is overloaded for JSExpr
    je1 = @jsexpr(:x+1)
    je2 = @jsexpr(:y+2)
    @test Stipple.json(je1 == je2) == "(x + 1) == (y + 2)"

    je1 = @jsexpr(2 * :xx^2 + 2)
    @test je1.s == "((2 * (xx ** 2)) + 2)"
    @test Stipple.json(je1) == "(2 * (xx ** 2)) + 2"

    je2 = @jsexpr(:y + '2')
    @test Stipple.json(je2) == "y + '2'"

    @test Stipple.json(je1 * je2) == "((2 * (xx ** 2)) + 2) * (y + '2')"
    @test Stipple.json(je1 + je2) == "((2 * (xx ** 2)) + 2) + (y + '2')"
end

@testitem "@page macro with ParsedHTMLStrings" setup=[StippleTests] begin
    using Genie.HTTPUtils.HTTP
    using Stipple.ReactiveTools
    version = Genie.Assets.package_version("Stipple")

    @app i = 1

    port = rand(8001:9000)
    up(;port, ws_port = port)

    # rand is needed to avoid re-using cached routes
    view() = [ParsedHTMLString("""<div id="test" @click="i = i+1">Change @click</div>"""), a("test $(rand(1:10^10))")]
    p1 = view()[1]

    ui() = ParsedHTMLString(view())

    # route function resulting in ParsedHTMLString
    @page("/", ui)
    payload = String(HTTP.payload(HTTP.get("http://127.0.0.1:$port")))
    @test match(r"<div id=\"test\" .*?div>", payload).match == p1
    @test contains(payload, """<link href="/stipple.jl/$version/assets/css/stipplecore.css""")

    # route constant ParsedHTMLString
    @page("/", ui())
    payload = String(HTTP.payload(HTTP.get("http://127.0.0.1:$port")))
    @test match(r"<div id=\"test\" .*?div>", payload).match == p1
    @test contains(payload, """<link href="/stipple.jl/$version/assets/css/stipplecore.css""")

    # ----------------------------

    ui() = view()

    # route function resulting in Vector{ParsedHTMLString}
    @page("/", ui)
    payload = String(HTTP.payload(HTTP.get("http://127.0.0.1:$port")))
    @test match(r"<div id=\"test\" .*?div>", payload).match == p1
    @test contains(payload, r"<a>test \d+</a>")

    @test contains(payload, """<link href="/stipple.jl/$version/assets/css/stipplecore.css""")

    # route constant Vector{ParsedHTMLString}
    @page("/", ui())
    payload = String(HTTP.payload(HTTP.get("http://127.0.0.1:$port")))
    @test match(r"<div id=\"test\" .*?div>", payload).match == p1
    @test contains(payload, """<link href="/stipple.jl/$version/assets/css/stipplecore.css""")

    # Supply a String instead of a ParsedHTMLString.
    # As the '@' character is not correctly parsed, the match is expected to differ
    # Update, since XML2_jll version 2.14.0, the '@' character is correctly parsed, hence we need to differentiate between the two cases
    
    test_fn = VersionNumber(Genie.Assets.package_version("XML2_jll")) > v"2.14.0-" ? (==) : (!=)
    ui() = join(view())

    # route function resulting in String
    @page("/", ui)
    payload = String(HTTP.payload(HTTP.get("http://127.0.0.1:$port")))
    @test test_fn(match(r"<div id=\"test\" .*?div>", payload).match, p1)
    @test contains(payload, """<link href="/stipple.jl/$version/assets/css/stipplecore.css""")
    @test contains(payload, r"<a>test \d+</a>")

    # route constant String
    @page("/", ui())
    payload = String(HTTP.payload(HTTP.get("http://127.0.0.1:$port")))
    @test test_fn(match(r"<div id=\"test\" .*?div>", payload).match, p1)
    @test contains(payload, """<link href="/stipple.jl/$version/assets/css/stipplecore.css""")
    @test contains(payload, r"<a>test \d+</a>")

    down()
end

@testitem "Indexing with `end`" begin
    using DataFrames

    r = R([1, 2, 3])
    on(r) do r
        r[end - 1] += 1
    end
    @test r[end] == 3
    r[end] = 4
    @test r[end - 1] == 3
    @test r[end] == 4

    df = DataFrame(:a => 1:3, :b => 12:14)
    @test df[end, 1] == 3
    @test df[end, end] == 14
    @test df[:, end] == 12:14
end

@testitem "adding and removing stylesheets" begin
    function my_css()
        [style("""
            .stipple-core .q-table tbody tr { color: inherit; }
        """)]
    end

    add_css(my_css)
    @test Stipple.Layout.THEMES[][end] == my_css

    n = length(Stipple.Layout.THEMES[])
    remove_css(my_css)
    @test length(Stipple.Layout.THEMES[]) == n - 1
    @test findfirst(==(my_css), Stipple.Layout.THEMES[]) === nothing

    add_css(my_css)
    @test Stipple.Layout.THEMES[][end] == my_css
    remove_css(my_css, byname = true)
    @test findfirst(==(my_css), Stipple.Layout.THEMES[]) === nothing
end

@testitem "parsing" begin
    struct T1
        c::Int
        d::Int
    end

    struct T2
        a::Int
        b::T1
    end

    t2 = T2(1, T1(2, 3))
    t2_dict = JSON3.read(Stipple.json(t2), Dict)

    Base.@kwdef struct T3
        c::Int = 1
        d::Int = 3
    end

    Base.@kwdef struct T4
        a::Int = 1
        b::T3 = T3()
    end

    @test Stipple.stipple_parse(T2, t2_dict) == T2(1, T1(2, 3))
    @test Stipple.stipple_parse(T3, Dict()) == T3(1, 3)
    @test Stipple.stipple_parse(T4, Dict()) == T4(1, T3(1, 3))

    @test Stipple.stipple_parse(Union{Nothing, String}, "hi") == "hi"
    @test Stipple.stipple_parse(Union{Nothing, String}, SubString("hi")) == "hi"
    # the following test is only valid for Julia 1.7 and above because specifity of methods
    # changed in Julia 1.7. As the latest LTS version of Julia is now 1.10, we accept that
    # this specific stipple_parse for Union{Nothing, T} fails for Julia 1.6
    # people can define explicit methods for their types if they need this functionality
    @static if VERSION ≥ v"1.7"
        @test Stipple.stipple_parse(Union{Nothing, SubString}, "hi") == SubString("hi")
    end
    @test Stipple.stipple_parse(Union{Nothing, String}, nothing) === nothing

    @enum Fruit apple=1 orange=2 kiwi=3
    @test Stipple.stipple_parse(Fruit, "apple") == apple
end

@testitem "Exporting and loading model field values" begin
    using Stipple.ReactiveTools

    @app TestApp2 begin
        @in i = 100
        @out s = "Hello"
        @private x = 4
    end

    model = @init TestApp2

    exported_values = Stipple.ModelStorage.model_values(model)
    @test exported_values[:i] == 100
    @test exported_values[:s] == "Hello"
    @test exported_values[:x] == 4

    values_json = Stipple.json(exported_values)
    exported_values_json = Stipple.ModelStorage.model_values(model, json = true)
    @test values_json == exported_values_json

    values_dict = Dict(:i => 20, :s => "world", :x => 5)
    Stipple.ModelStorage.load_model_values!(model, values_dict)
    @test model.i[] == 20
    @test model.s[] == "world"
    @test model.x[] == 5

    values_json = Dict(:i => 30, :s => "zero", :x => 50) |> Stipple.json |> string
    Stipple.ModelStorage.load_model_values!(model, values_json)
    @test model.i[] == 30
    @test model.s[] == "zero"
    @test model.x[] == 50

end

@testitem "Finalizers" begin
    using Stipple.ReactiveTools

    current_storage = Stipple.use_model_storage()
    Stipple.enable_model_storage(false)
    @app MyApp begin
        @in i = 100
        @out s = "Hello"
        @private x = 4

        @onchange isready begin
            @info "Model is ready"
        end
    end

    model = @init MyApp
    @test length(model.isready.o.listeners) == 2
    @test_logs (:info, "Calling finalizers") notify(model, Val(:finalize), "")
    @test length(model.isready.o.listeners) == 0

    model = @init MyApp
    @event MyApp :finalize begin
        @info "Custom finalizer"
    end

    @test_logs (:info, "Custom finalizer") notify(model, Val(:finalize), "")
    @test length(model.isready.o.listeners) == 2

    Stipple.enable_model_storage(current_storage)
end

@testitem "Observable synchronization" begin
    using Observables

    o = Observable(0)
    o1 = Observable(1)
    o2 = Observable(2)
    o3 = Observable(3)

    synchronize!(o1, o, update = false)
    synchronize!(o2, o, update = false)
    synchronize!(o3, o, update = false)

    @test o1[] == 1
    @test o2[] == 2
    @test o3[] == 3

    o[] = 10
    @test o1[] == 10
    @test o2[] == 10
    @test o3[] == 10

    o1[] = 20
    @test o[] == 20
    @test o2[] == 20
    @test o3[] == 20

    o2[] = 30
    @test o[] == 30
    @test o1[] == 30
    @test o3[] == 30

    @test_logs (:warn, "Synchronization loop detected, skipping synchronization") synchronize!(o1, o)
    @test_logs (:warn, "Synchronization loop detected, skipping synchronization") synchronize!(o, o3)

    unsynchronize!(o1)
    o1[] = 40
    @test o[] == 30
    @test o2[] == 30
    @test o3[] == 30

    o[] = 50
    @test o1[] == 40

    unsynchronize!(o)
    o[] = 60
    @test o1[] == 40
    @test o2[] == 50
    @test o3[] == 50

    o = Observable(0)
    o1 = Observable(1)
    synchronize!(o1, o; bidirectional = false)

    @test length(o.listeners) == 1
    @test length(o1.listeners) == 0

    unsynchronize!(o1)
    @test length(o.listeners) == 1

    unsynchronize!(o1, o)
    @test length(o.listeners) == 0
end

@testitem "Priority" begin
    using Stipple.ReactiveTools

    # test app example from the docstring
    @app begin
        # reactive variables
        @in N = 0
        @out result = 0
     
        @onchange N begin
          result = 10 * N
        end
        
        @onchange N begin
          N[!] = clamp(N, 0, 10)
        end priority = 1
    end

    model = @init
    @test model.N[] == 0
    @test model.result[] == 0

    model.N[] = 5
    @test model.N[] == 5
    @test model.result[] == 50

    model.N[] = -20
    @test model.N[] == 0
    @test model.result[] == 0

    model.N[] = 20
    @test model.N[] == 10
    @test model.result[] == 100
end