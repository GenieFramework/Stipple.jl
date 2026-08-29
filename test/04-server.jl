# Basic server tests (should be enhanced over time perhaps...)

@testitem "Serving implicit app" tags=[:server] setup=[StippleTestSetup] begin
    @eval begin
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

    @eval model = @init

    @eval begin
        @page("/", ui)
        @page("/nolayout", ui, layout = "no layout")
        @page("/debounce", ui, debounce = 50)
        @page("/debounce2", ui; debounce)
        @page("/static", ui; model)
    end

    port = unique_test_port()
    current_storage = Stipple.use_model_storage()
    current_channel_sharing = Stipple.SHARE_CHANNELS_ACROSS_WINDOWS[]

    up(; port, ws_port = port)

    try
        @test occursin(">DEMO UI<", string_get("http://localhost:$port"))

        @test contains(string_get("http://localhost:$port/nolayout"), r"<!DOCTYPE html><html>\n  <body>\s*(<p>)?no layout(</p>)?\s*</body></html>")

        @test get_debounce(port, "main_reactivemodel") == 300

        @clear_cache
        # first get the main page to trigger init function, which sets up the assets
        string_get("http://localhost:$port/debounce")
        @test get_debounce(port, "main_reactivemodel") == 50

        @clear_cache
        string_get("http://localhost:$port/debounce2")
        @test get_debounce(port, "main_reactivemodel") == 10

        # Clear cookies before testing session persistence
        empty!(COOKIE_JAR.entries)

        s1 = string_get("http://localhost:$port/")
        s2 = string_get("http://localhost:$port/")
        s3 = string_get("http://localhost:$port/", cookies = false)

        s4 = string_get("http://localhost:$port/static")
        s5 = string_get("http://localhost:$port/static")
        s6 = string_get("http://localhost:$port/static", cookies = false)

        @test get_channel(s2) == get_channel(s1)
        @test get_channel(s3) != get_channel(s1)
        @test get_channel(s4) == get_channel(s5) == get_channel(s6)

        Stipple.enable_model_storage(false)
        empty!(COOKIE_JAR.entries)

        s7 = string_get("http://localhost:$port/")
        s8 = string_get("http://localhost:$port/")
        s9 = string_get("http://localhost:$port/", cookies = false)

        @test get_channel(s8) != get_channel(s7)
        @test get_channel(s9) != get_channel(s7)

        Stipple.SHARE_CHANNELS_ACROSS_WINDOWS[] = true
        empty!(COOKIE_JAR.entries)

        s10 = string_get("http://localhost:$port/")
        s11 = string_get("http://localhost:$port/")
        s12 = string_get("http://localhost:$port/", cookies = false)

        @test get_channel(s11) == get_channel(s10)
        @test get_channel(s12) != get_channel(s10)
    finally
        Stipple.enable_model_storage(current_storage)
        Stipple.SHARE_CHANNELS_ACROSS_WINDOWS[] = current_channel_sharing
        @clear_cache
        try
            down()
        catch
        end
    end
end

@testitem "Serving explicit app" tags=[:server] setup=[StippleTestSetup] begin
    @eval begin
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

    @eval model = @init(MyApp)

    @eval begin
        @page("/", ui; model = MyApp)
        @page("/nolayout", ui, layout = "no layout (explicit)", model = MyApp)
        @page("/debounce", ui, debounce = 51; model = MyApp)
        @page("/debounce2", ui; debounce, model = MyApp)
        @page("/static1", ui; model)
    end

    port = unique_test_port()
    up(; port, ws_port = port)

    try
        @clear_cache MyApp
        @test occursin(">DEMO UI explicit<", string_get("http://localhost:$port"))

        @test contains(string_get("http://localhost:$port/nolayout"), r"<!DOCTYPE html><html>\n  <body>\s*(<p>)?no layout \(explicit\)(</p>)?\s*</body></html>")

        @test get_debounce(port, "myapp") == 300

        @clear_cache MyApp
        # first get the main page to trigger init function, which sets up the assets
        string_get("http://localhost:$port/debounce")
        @test get_debounce(port, "myapp") == 51

        @clear_cache MyApp
        string_get("http://localhost:$port/debounce2")
        @test get_debounce(port, "myapp") == 11

        # Clear cookies before testing session persistence
        empty!(COOKIE_JAR.entries)

        s1 = string_get("http://localhost:$port/")
        s2 = string_get("http://localhost:$port/")
        s3 = string_get("http://localhost:$port/", cookies = false)

        s4 = string_get("http://localhost:$port/static1")
        s5 = string_get("http://localhost:$port/static1")
        s6 = string_get("http://localhost:$port/static1", cookies = false)

        @test get_channel(s2) == get_channel(s1)
        @test get_channel(s3) != get_channel(s1)
        @test get_channel(s4) == get_channel(s5) == get_channel(s6)
    finally
        @clear_cache MyApp
        try
            down()
        catch
        end
    end
end

@testitem "Page with ParsedHTMLStrings" tags=[:server] setup=[StippleTestSetup] begin
    using Genie.HTTPUtils.HTTP

    port = unique_test_port()
    up(; port, ws_port = port)

    try
        # rand is needed to avoid re-using cached routes
        # route function resulting in ParsedHTMLString
        @eval begin
            view() = [ParsedHTMLString("""<div id="test" @click="i = i+1">Change @click</div>"""), a("test $(rand(1:10^10))")]
            p1 = view()[1]
            ui() = ParsedHTMLString(view())

            @app # empty app to allow @page macro
        end

        @eval @page("/", ui)

        response = HTTP.get("http://127.0.0.1:$port")
        payload = String(isdefined(response, :body) ? response.body : response)
        @test match(r"<div id=\"test\" .*?div>", payload).match == p1
        @test contains(payload, r"<link href=\"/stipple\.jl/[^\"/]+/assets/css/stipplecore\.css\"")

        # route constant ParsedHTMLString
        @eval @page("/", ui())
        response = HTTP.get("http://127.0.0.1:$port")
        payload = String(isdefined(response, :body) ? response.body : response)
        @test match(r"<div id=\"test\" .*?div>", payload).match == p1
        @test contains(payload, r"<link href=\"/stipple\.jl/[^\"/]+/assets/css/stipplecore\.css\"")

        # ----------------------------

        ui() = view()

        # route function resulting in Vector{ParsedHTMLString}
        @eval @page("/", ui)
        response = HTTP.get("http://127.0.0.1:$port")
        payload = String(isdefined(response, :body) ? response.body : response)
        @test match(r"<div id=\"test\" .*?div>", payload).match == p1
        @test contains(payload, r"<a>test \d+</a>")

        @test contains(payload, r"<link href=\"/stipple\.jl/[^\"/]+/assets/css/stipplecore\.css\"")

        # route constant Vector{ParsedHTMLString}
        @eval @page("/", ui())
        response = HTTP.get("http://127.0.0.1:$port")
        payload = String(isdefined(response, :body) ? response.body : response)
        @test match(r"<div id=\"test\" .*?div>", payload).match == p1
        @test contains(payload, r"<link href=\"/stipple\.jl/[^\"/]+/assets/css/stipplecore\.css\"")

        # Supply a String instead of a ParsedHTMLString.
        # As the '@' character is not correctly parsed, the match is expected to differ.
        # Update, since XML2_jll version 2.14.0, the '@' character is correctly parsed, hence we need to differentiate between the two cases.
        test_fn = VersionNumber(Genie.Assets.package_version("XML2_jll")) > v"2.14.0-" ? (==) : (!=)
        ui() = join(view())

        # route function resulting in String
        @eval @page("/", ui)
        response = HTTP.get("http://127.0.0.1:$port")
        payload = String(isdefined(response, :body) ? response.body : response)
        @test test_fn(match(r"<div id=\"test\" .*?div>", payload).match, p1)
        @test contains(payload, r"<link href=\"/stipple\.jl/[^\"/]+/assets/css/stipplecore\.css\"")
        @test contains(payload, r"<a>test \d+</a>")

        # route constant String
        @eval @page("/", ui())
        response = HTTP.get("http://127.0.0.1:$port")
        payload = String(isdefined(response, :body) ? response.body : response)
        @test test_fn(match(r"<div id=\"test\" .*?div>", payload).match, p1)
        @test contains(payload, r"<link href=\"/stipple\.jl/[^\"/]+/assets/css/stipplecore\.css\"")
        @test contains(payload, r"<a>test \d+</a>")
    finally
        try
            down()
        catch
        end
    end
end
