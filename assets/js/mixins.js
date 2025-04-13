const watcherMixin = {
  methods: {
    // Acknowledgement: copied watchIgnorable from VueUse
    watchIgnorable: function (source,cb,options) {
      const ignoreCount = Vue.ref(0)
      const syncCount = Vue.ref(0)
      const syncStop = Vue.watch(
        source,
        () => {
          syncCount.value++
        },
        { ...options, flush: 'sync' },
      )
      const stop = Vue.watch( source,
        (...args) => {
          const ignore = ignoreCount.value > 0 && 
            ignoreCount.value === syncCount.value
    
          ignoreCount.value = 0
          syncCount.value = 0
    
          if (!ignore) {
            cb(...args)
          }
        }, 
        options 
      )
      const ignoreUpdates = (updater) => {
        const prev = syncCount.value
        updater()
        const changes = syncCount.value - prev
        // Add sync changes done in updater
        ignoreCount.value += changes
      }
      const ignorePrevAsyncUpdates = () => {
        // All sync changes til are ignored
        ignoreCount.value = syncCount.value
      }
      return { 
        ignoreUpdates,
        ignorePrevAsyncUpdates,
        stop: () => {
          syncStop()
          stop()
        }
      }
    },

    updateField: function (field, newVal) {
      if (field=='js_app') { newVal(); return }

      try {
        if (this['_ignore_' + field]) {
          this['_ignore_' + field](()=>{this[field] = newVal});
        } else {
          this[field] = newVal
        }
        if (field=='js_model' && typeof(this[field])=='function') { 
          this[field]()
          this[field] = null
        }
      } catch(ex) {
        if (Genie.Settings.env == 'dev') {
          console.error(ex);
        }
      }
    },

    push: function (field) {
      this.WebChannel.sendMessageTo(this.channel_, 'watchers', {'payload': {
          'field': field,
          'newval': this[field],
          'oldval': null,
          'sesstoken': document.querySelector("meta[name='sesstoken']")?.getAttribute('content')
      }})
    }
  }
}

const reviveMixin = {
  methods: {
    revive_jsfunction: function (k, v) {
      if ( (typeof v==='object') && (v!=null) && (v.jsfunction) ) {
        return Function(v.jsfunction.arguments, v.jsfunction.body)
      } else {
        return v
      }
    },
    // deprecated, kept for compatibility
    revive_payload: function(obj) {
      if (typeof obj === 'object') {
        for (var key in obj) {
          if ( (typeof obj[key] === 'object') && (obj[key]!=null) && !(obj[key].jsfunction) ) {
            this.revive_payload(obj[key])
          } else {
            if ( (obj[key]!=null) && (obj[key].jsfunction) ) {
              obj[key] = Function(obj[key].jsfunction.arguments, obj[key].jsfunction.body)
            }
          }
        }
      }
      return obj;
    }
  }
}

const eventMixin = {
  methods: {
    handle_event: function (event_data, event_handler, mode) {
      if (event_data === undefined) { event_data = {} }
      console.debug('event: ', event_data, "\nevent (json): " + JSON.stringify(event_data) + "\nevent handler: :" + event_handler)
      if (mode=='addclient') { event_data._addclient = true}
      this.WebChannel.sendMessageTo(this.channel_, 'events', {
          'event': {
              'name': event_handler,
              'event': event_data
          }
      })
    },
    addClickInfo: function (event) {
        new_event = {}
        new_event.x = event.x
        new_event.y = event.y
        new_event.clientX = event.clientX
        new_event.clientY = event.clientY
        new_event.offsetX = event.offsetX
        new_event.offsetY = event.offsetY
        new_event.layerX = event.layerX
        new_event.layerY = event.layerY
        new_event.pageX = event.pageX
        new_event.pageY = event.pageY
        new_event.screenX = event.screenX
        new_event.screenY = event.screenY
        
        new_event.button = event.button
        new_event.buttons = event.buttons
        new_event.ctrlKey = event.ctrlKey
        new_event.shiftKey = event.shiftKey
        new_event.altKey = event.altKey
        new_event.metaKey = event.metaKey
        new_event.detail = event.detail
        new_event.target = event.target
        new_event.timeStamp = event.timeStamp
        new_event.type = event.type
        return {...new_event, ...event}
    }
  }
}
