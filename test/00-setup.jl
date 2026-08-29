@testmodule StippleTestSetup begin
    using Reexport
    using Sockets
    using Genie.HTTPUtils.HTTP

    @reexport using Stipple
    @reexport using Stipple.ReactiveTools

    # Cookie jar for managing session cookies across requests.
    const COOKIE_JAR = HTTP.Cookies.CookieJar()

    function unique_test_port()
        server = Sockets.listen(ip"127.0.0.1", 0)
        try
            sockname = Sockets.getsockname(server)
            return sockname isa Tuple ? Int(last(sockname)) : Int(sockname.port)
        finally
            close(server)
        end
    end

    function string_get(x; cookies = true, kwargs...)
        response = if cookies
            HTTP.get(x; retries = 0, status_exception = false, cookiejar = COOKIE_JAR, kwargs...)
        else
            HTTP.get(x; retries = 0, status_exception = false, kwargs...)
        end
        # HTTP v2 response body is accessed directly, v1 uses .body field.
        String(isdefined(response, :body) ? response.body : response)
    end

    function get_channel(s::String)
        match(r"\(\) => window.create[^']+'([^']+)'", s).captures[1]
    end

    function get_debounce(port, modelname = nothing; page = "/")
        html = string_get("http://localhost:$port$page")
        script_matches = collect(eachmatch(r"/stipple\.jl/[^\"']+/assets/js/[^\"']+\.js", html))
        isempty(script_matches) && error("Could not find Stipple model JS asset in page HTML.")
        js_asset_path = script_matches[end].match

        s = string_get("http://localhost:$port$js_asset_path")
        parse(Int, match(r"_.debounce\(.+?(\d+)\)", s).captures[1])
    end

    @vars TestMixin begin
        j = 101
        t = "World", PRIVATE
    end

    module App1
    using Stipple, Stipple.ReactiveTools

    @app begin
        @in i1 = 101
    end

    @app MyApp begin
        @in i1 = 101
    end
    end

    module App2
    using Stipple, Stipple.ReactiveTools

    @app begin
        @in i2 = 102
    end

    @app MyApp begin
        @in i2 = 102
    end
    end

    @enum Fruit apple = 1 orange = 2 kiwi = 3

    export COOKIE_JAR, unique_test_port, string_get, get_channel, get_debounce
    export TestMixin, App1, App2, Fruit, apple, orange, kiwi
end

@testitem "StippleTestSetup" setup=[StippleTestSetup] begin
    @test StippleTestSetup isa Module
end
