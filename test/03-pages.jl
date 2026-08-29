@testitem "Multipage Reactive API (implicit)" setup=[StippleTestSetup] begin
    @eval p1 = @page("/app1", "hello", model = App1)
    @eval p2 = @page("/app2", "world", model = App2)
    channel1a = get_channel(String(p1.route.action().body))
    channel1b = get_channel(String(p1.route.action().body))
    channel2a = get_channel(String(p2.route.action().body))
    channel2b = get_channel(String(p2.route.action().body))

    # channels have to be different
    @test channel1a != channel1b != channel2a != channel2b
end

@testitem "Multipage Reactive API (explicit)" setup=[StippleTestSetup] begin
    @eval p1 = @page("/app1", "hello", model = App1.MyApp)
    @eval p2 = @page("/app2", "world", model = App2.MyApp)
    channel1a = get_channel(String(p1.route.action().body))
    channel1b = get_channel(String(p1.route.action().body))
    channel2a = get_channel(String(p2.route.action().body))
    channel2b = get_channel(String(p2.route.action().body))

    # channels have to be different
    @test channel1a != channel1b != channel2a != channel2b
end

