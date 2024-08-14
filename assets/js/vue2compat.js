window.vueLegacy={
    plugins: {}, 
    components: {},
    context: "none"
}

Vue.use = function(plugin, options) {
    window.vueLegacy.plugins[window.vueLegacy.context] = {plugin: plugin, options: options}
    // append an increasing number in case of multiple plugins with the same context
    x = window.vueLegacy.context.split('.')
    if (isNaN(parseInt(x[x.length - 1]))) {
        x.push(1)
    } else {
        x[x.length - 1] = x[x.length - 1] * 1 + 1
    }
    window.vueLegacy.context = x.join('.')
}
Vue.component = function(componentname, component) {
    window.vueLegacy.components[componentname] = component
}