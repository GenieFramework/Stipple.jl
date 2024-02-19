const watcherMixin = {
  methods: {
    $withoutWatchers: function (cb, filter) {
      let ww = (filter === null) ? this._watchers : [];

      if (typeof(filter) == "string") {
        this._watchers.forEach((w) => { if (w.expression == filter) {ww.push(w)} } )
      } else { // if it is a true regex
        this._watchers.forEach((w) => { if (w.expression.match(filter)) {ww.push(w)} } )
      }

      const watchers = ww.map((watcher) => ({ cb: watcher.cb, sync: watcher.sync }));

      for (let index in ww) {
        ww[index].cb = () => null;
        ww[index].sync = true;
      }

      cb();

      for (let index in ww) {
        ww[index].cb = watchers[index].cb;
        ww[index].sync = watchers[index].sync;
      }

    },

    updateField: function (field, newVal) {
      if (field=='js_app') { newVal(); return }

      try {
        this.$withoutWatchers(()=>{this[field]=newVal},"function(){return this." + field + "}");
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
      Genie.WebChannels.sendMessageTo(CHANNEL, 'watchers', {'payload': {
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
      console.debug('event: ' + JSON.stringify(event_data) + ":" + event_handler)
      if (mode=='addclient') { event_data._addclient = true}
      Genie.WebChannels.sendMessageTo(window.CHANNEL, 'events', {
          'event': {
              'name': event_handler,
              'event': event_data
          }
      })
    }
  }
}