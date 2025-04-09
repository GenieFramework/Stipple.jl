module MyGenieMulti

using Genie

@using modules/ModuleA
@using modules/ModuleB
@using modules/ModuleC
@using modules/ModuleD

function __init__()
    cd(dirname(@__DIR__))
    Genie.Loader.loadenv(context = @__MODULE__)
    up(open_browser = true)
end

end # module MyGenie
