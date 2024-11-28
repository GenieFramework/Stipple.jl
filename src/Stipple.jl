"""
# Stipple

Stipple is a reactive UI library for Julia. It provides a rich API for building rich web UIs with 2-way bindings between
HTML UI elements and Julia. It requires minimum configuration, automatically setting up the WebSockets/Ajax communication
channels and automatically keeping the data in sync.

Stipple allows creating powerful reactive web data dashboards using only Julia coding. It employs a declarative
programming model, the framework taking care of the full data sync workflow.

Stipple uses Vue.js on the frontend and focuses mostly on the low level communication API, allowing data binding to HTML
elements, forms, etc. The core functionality is meant to be extended with specialized plugins, for example for powerful
UIs or plotting features. The plugins are easy to build, requiring a minimum Julia implementation that usually ties into
existing Vue.js libraries.
"""
module Stipple

# only for fast CI testing

function __init__()
    println("Fiat Lux!")
end

end
