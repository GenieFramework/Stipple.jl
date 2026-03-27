// add prototype functions to allow for julia-based indexing:
// Array methods
Object.defineProperty(Array.prototype, 'juliaGet', {
  value: function(index) {
    return this[index - 1];
  },
  enumerable: false,
  writable: true,
  configurable: true
});

Object.defineProperty(Array.prototype, 'juliaSet', {
  value: function(index, value) {
    this[index - 1] = value;
    return this;
  },
  enumerable: false,
  writable: true,
  configurable: true
});

// Object methods
Object.defineProperty(Object.prototype, 'juliaGet', {
  value: function(key) {
    return this[key];
  },
  enumerable: false,
  writable: true,
  configurable: true
});

Object.defineProperty(Object.prototype, 'juliaSet', {
  value: function(key, value) {
    this[key] = value;
    return this;
  },
  enumerable: false,
  writable: true,
  configurable: true
});

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
    setFieldRaw: function (path, value) {
      // convert path to keys (e.g. "a[0].b" -> ["a", 0, "b"])
      const pathRegex = /([^.[\]]+)|\[(?:'([^']*)'|"([^"]*)"|([^\]]*))\]/g;
      const keys = [];
      let match;

      while ((match = pathRegex.exec(path)) !== null) {
        let key = match[1] || match[2] || match[3] || match[4];

        // if match[4] is a hit, check wether it is a number and parse it to a decimal number
        if (match[4] && /^\d+$/.test(match[4])) {
          key = parseInt(match[4], 10);
        }
        
        keys.push(key);
      }
      // travel down the tree
      let current = this; 

      for (let i = 0; i < keys.length; i++) {
        const key = keys[i];

        // prevent prototype pollution
        if (key === '__proto__' || key === 'constructor' || key === 'prototype') {
          throw new Error("Alert: Illegal field name '" + key + "'");
        }
        // if at the end of the tree, set the value
        if (i === keys.length - 1) {
          current[key] = value;
          return current[key]
        } else {
          // otherwise travel down
          current = current[key] || {};
        }
      }
    },
    setField: function (index, value) {
      // set a field's value and always triggers a push to the backend
      // accepts multilevel indexing
      // update the field without trigger
      this.updateField(index, value)
      firstindex = index.match(/(?:^[\["'.]*)([^.\'"\[]+)/)?.[1]
      firstindex = firstindex || index
      // explicitly push to the backend
      this.push(firstindex)
    },
    updateField: function (index, newVal) {
      if (index=='js_app') { newVal(); return }

      try {
        // make sure we know the first index
        firstindex = index.match(/(?:^[\["'.]*)([^.\'"\[]+)/)?.[1]
        firstindex = firstindex || index
        if (this['_ignore_' + firstindex]) {
          this['_ignore_' + firstindex](() => this.setFieldRaw(index, newVal));
        } else {
          this.setFieldRaw(index, newVal)
        }
        if (index=='js_model' && typeof(this[index])=='function') { 
          this[index]()
          this[index] = null
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
    },
    pushJSResult: function (val) {
      this.WebChannel.sendMessageTo(this.channel_, 'watchers', {'payload': {
          'field': '__js_result__',
          'newval': val,
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

const navigationMixin = {
  methods: {
    goTo: function (location) {
      window.location = location
    },
    reloadPage: function() {
      window.location.reload()
    },
    goBack: function(steps = 1) {
      window.history.go(-steps)
    },
    goForward: function(steps = 1) {
      window.history.go(steps)
    },
  }
}
