# add default js methods to the model
export console

function console()
    :console => "function (...args) { return window.console(...args) }"
end

