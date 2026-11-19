@testitem "Indexing with `end`" setup=[StippleTestSetup] begin
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

@testitem "Synchronization" setup=[StippleTestSetup] begin
    # synchronize! is defined for AbstractObservables, so works for both Observables and Reactives
    o = Observable(0)
    o1 = Observable(1)
    o2 = Observable(2)
    o3 = Observable(3)
    r1 = Reactive(4)

    synchronize!(o1, o, update = false)
    synchronize!(o2, o, update = false)
    synchronize!(o3, o, update = false)
    synchronize!(r1, o, update = false)

    @test o1[] == 1
    @test o2[] == 2
    @test o3[] == 3
    @test r1[] == 4

    o[] = 10
    @test o1[] == 10
    @test o2[] == 10
    @test o3[] == 10
    @test r1[] == 10

    o1[] = 20
    @test o[] == 20
    @test o2[] == 20
    @test o3[] == 20
    @test r1[] == 20

    o2[] = 30
    @test o[] == 30
    @test o1[] == 30
    @test o3[] == 30
    @test r1[] == 30

    r1[] = 40
    @test o[] == 40
    @test o1[] == 40
    @test o2[] == 40
    @test o3[] == 40

    @test_logs (:warn, "Synchronization loop detected, skipping synchronization") synchronize!(o1, o)
    @test_logs (:warn, "Synchronization loop detected, skipping synchronization") synchronize!(o, o3)

    unsynchronize!(o1)
    o1[] = 50
    @test o[] == 40
    @test o2[] == 40
    @test o3[] == 40
    @test r1[] == 40

    o[] = 60
    @test o1[] == 50

    unsynchronize!(o)
    o[] = 70
    @test o1[] == 50
    @test o2[] == 60
    @test o3[] == 60

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


@testitem "Headless init" setup=[StippleTestSetup] begin
    @eval begin
        @app HeadlessApp begin
            @in hx = 1
            @out hy = 0

            @onchange hx begin
                hy = 2 * hx
            end
        end
    end

    # observers that Stipple.setup attaches to every field to send changes to the clients have priority 1, @onchange handlers 0
    count_priority(m, p) = sum(count(l -> first(l) == p, getfield(m, f).o.listeners) for f in fieldnames(typeof(m)) if getfield(m, f) isa Reactive)

    normal = @eval @init(HeadlessApp)
    @test haskey(Stipple.LAST_ACTIVITY, Symbol(getchannel(normal)))
    @test count_priority(normal, 1) > 0

    headless = @eval @init(HeadlessApp, headless = true)
    @test headless isa typeof(normal)
    # no purge timer registration and no sending of changes ...
    @test !haskey(Stipple.LAST_ACTIVITY, Symbol(getchannel(headless)))
    @test count_priority(headless, 1) == 0
    # ... but the handlers of the model are attached and work
    @test count_priority(normal, 0) > 0
    @test count_priority(headless, 0) == count_priority(normal, 0)
    headless.hx[] = 21
    @test headless.hy[] == 42
    # the channel marks the model as having no clients, and push! returns without trying to send
    @test getchannel(headless) == Stipple.HEADLESS_CHANNEL
    @test getchannel(normal) != Stipple.HEADLESS_CHANNEL
    @test push!(headless, :hx => headless.hx) === false

    # a model without a browser has no client to wait for: it is ready, and not ready only if asked for
    @test headless.isready[]
    @test !normal.isready[]
    not_ready = @eval @init(HeadlessApp, headless = true, isready = nothing)
    @test !not_ready.isready[]
end

@testitem "isready keyword of init_model runs the handlers" setup=[StippleTestSetup] begin
    @eval begin
        @app ReadyApp begin
            @in rx = 0
            @out ry = 0

            @onchange isready begin
                isready || return
                ry = 7
            end
        end
    end

    m = @eval @init(ReadyApp)
    @test !m.isready[] && m.ry[] == 0
    m = @eval @init(ReadyApp, isready = m -> true)
    @test m.isready[] && m.ry[] == 7
    # a headless model is ready by default, and its handlers have run
    m = @eval @init(ReadyApp, headless = true)
    @test m.isready[] && m.ry[] == 7
end
