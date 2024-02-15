window.vueLegacyPlugins = {}
window.vueLegacyComponents = {}
window.vueLegacyContext = "none"
Vue.use = function(plugin, options) {
    window.vueLegacyPlugins[window.vueLegacyContext] = {plugin: plugin, options: options}
    x = window.vueLegacyContext.split('.')
    if (isNaN(parseInt(x[x.length - 1]))) {
        x.push(1)
    } else {
        x[x.length - 1] = x[x.length - 1] * 1 + 1
    }
    window.vueLegacyContext = x.join('.')
}
Vue.component = function(componentname, component) {
    window.vueLegacyComponents[componentname] = component
}