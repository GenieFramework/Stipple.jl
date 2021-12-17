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
      try {
        this.$withoutWatchers(()=>{this[field]=newVal},"function(){return this." + field + "}");
      } catch(ex) {
        console.log(ex);
      }
    },

    updateFieldAt: function (field, newVal, keys) {
      try {
        this.$withoutWatchers(() => {
          var o = this[field]
          for (var i = 0, n = keys.length; i < n-1; ++i) {
            var k = keys[i];
            if (k in o) {
                o = o[k];
            }
          }
          o[keys[i]]=newVal
          this[field].__ob__.dep.notify()
        },"function(){return this." + field + "}");
      } catch(ex) {
        console.log(ex);
      }
    }
  }
}

const reviveMixin = {
  methods: {
    revive_payload: function(obj) {
      if (typeof obj === 'object') {
        for (var key in obj) {
          if ( (typeof obj[key] === 'object') && (obj[key]!=null) && !(obj[key].jsfunction) ) {
            this.revive_payload(obj[key])
          } else {
            if ( (obj[key]!=null) && (obj[key].jsfunction) ) {
              obj[key] = Function(obj[key].jsfunction.arguments, obj[key].jsfunction.body)
              if (key=='stipplejs') { obj[key](); }
            }
          }
        }
      }
      return obj;
    }
  }
}