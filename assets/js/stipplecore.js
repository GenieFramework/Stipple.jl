!(function (e) {
  var t = {};
  function n(r) {
    if (t[r]) return t[r].exports;
    var o = (t[r] = { i: r, l: !1, exports: {} });
    return e[r].call(o.exports, o, o.exports, n), (o.l = !0), o.exports;
  }
  (n.m = e),
    (n.c = t),
    (n.d = function (e, t, r) {
      n.o(e, t) || Object.defineProperty(e, t, { enumerable: !0, get: r });
    }),
    (n.r = function (e) {
      "undefined" != typeof Symbol && Symbol.toStringTag && Object.defineProperty(e, Symbol.toStringTag, { value: "Module" }), Object.defineProperty(e, "__esModule", { value: !0 });
    }),
    (n.t = function (e, t) {
      if ((1 & t && (e = n(e)), 8 & t)) return e;
      if (4 & t && "object" == typeof e && e && e.__esModule) return e;
      var r = Object.create(null);
      if ((n.r(r), Object.defineProperty(r, "default", { enumerable: !0, value: e }), 2 & t && "string" != typeof e))
        for (var o in e)
          n.d(
            r,
            o,
            function (t) {
              return e[t];
            }.bind(null, o)
          );
      return r;
    }),
    (n.n = function (e) {
      var t =
        e && e.__esModule
          ? function () {
              return e.default;
            }
          : function () {
              return e;
            };
      return n.d(t, "a", t), t;
    }),
    (n.o = function (e, t) {
      return Object.prototype.hasOwnProperty.call(e, t);
    }),
    (n.p = ""),
    n((n.s = 2));
})([
  function (e, t, n) {},
  function (e, t, n) {},
  function (e, t, n) {
    "use strict";
    n.r(t);
    n(0), n(1);
    var r = function () {
      var e = this.$createElement;
      return (this._self._c || e)("section", { staticClass: "st-dashboard" }, [this._t("default")], 2);
    };
    r._withStripped = !0;
    var o = function () {
      var e = this,
        t = e.$createElement,
        n = e._self._c || t;
      return n(
        "div",
        { staticClass: "st-big-number", class: e.color ? "st-big-number--" + e.color : "" },
        [
          e.title ? n("q-badge", [e._v(e._s(e.title))]) : e._e(),
          e._v(" "),
          e.icon ? n("q-icon", { staticClass: "st-big-number__icon", class: e.color ? "bg-" + e.color : "", attrs: { name: e.icon } }) : e._e(),
          e._v(" "),
          n("span", { staticClass: "st-big-number__num" }, [e.arrow ? n("q-icon", { attrs: { name: "arrow_drop_" + e.arrow } }) : e._e(), e._v("\n        " + e._s(e.random ? e.randomize() : e.number ? e.number : 0) + "\n      ")], 1),
        ],
        1
      );
    };
    function i(e, t, n, r, o, i, s, a) {
      var u,
        c = "function" == typeof e ? e.options : e;
      if (
        (t && ((c.render = t), (c.staticRenderFns = n), (c._compiled = !0)),
        r && (c.functional = !0),
        i && (c._scopeId = "data-v-" + i),
        s
          ? ((u = function (e) {
              (e = e || (this.$vnode && this.$vnode.ssrContext) || (this.parent && this.parent.$vnode && this.parent.$vnode.ssrContext)) || "undefined" == typeof __VUE_SSR_CONTEXT__ || (e = __VUE_SSR_CONTEXT__),
                o && o.call(this, e),
                e && e._registeredComponents && e._registeredComponents.add(s);
            }),
            (c._ssrRegister = u))
          : o &&
            (u = a
              ? function () {
                  o.call(this, (c.functional ? this.parent : this).$root.$options.shadowRoot);
                }
              : o),
        u)
      )
        if (c.functional) {
          c._injectStyles = u;
          var l = c.render;
          c.render = function (e, t) {
            return u.call(t), l(e, t);
          };
        } else {
          var p = c.beforeCreate;
          c.beforeCreate = p ? [].concat(p, u) : [u];
        }
      return { exports: e, options: c };
    }
    o._withStripped = !0;
    var s = i(
      {
        name: "StBigNumber",
        data: function () {
          return {};
        },
        props: ["number", "title", "icon", "color", "arrow", "random"],
        methods: {
          randomize: function () {
            return Math.floor(2e4 * Math.random() + 1);
          },
        },
      },
      o,
      [],
      !1,
      null,
      "4d31d652",
      null
    );
    var a = s.exports,
      u = i({ name: "Dashboard", components: { StBigNumber: a } }, r, [], !1, null, "4d047983", null);
    var c = u.exports;
    // window.Stipple = {
    //   init: function (e) {
    //     var t;
    //     if (!Vue) throw "Stipple requires Vue";
    //     e = Object.assign({}, e);
    //     Vue.component("StDashboard", c);
    //     Vue.component("StBigNumber", a);
    //     (t = document.querySelector("html").classList).add.apply(t, ["stipple-core", e.theme ? e.theme : "stipple-blue"]);
    //   },
    // };
  },
]);