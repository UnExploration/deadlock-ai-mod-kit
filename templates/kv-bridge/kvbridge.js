// kvbridge.js: persistent key/value storage for Deadlock Panorama mods.
// Loads the kit's shared storage page (store/index.html at the kit's root, served over HTTPS) in a
// hidden CitadelHTMLPanel and exchanges JSON with it: request in the URL #fragment, reply in
// document.title (HTMLTitle event). Every request carries the mod's namespace (opts.ns), and the
// page only lets it touch keys under '<ns>/'. Docs: docs/04-persistence-and-io.md (pattern A).
// new-mod.ps1 -Kind data copies it into the mod; keep PREFIX/protocol in sync with the page.
// Requests are serialized: one in flight at a time.
'use strict';

var KVBridge = (function () {
  var HELLO_RETRY_SEC = 2;                 // plus timeoutSec per attempt: ~30 s total before 'offline'
  var HELLO_MAX_TRIES = 4;

  function normalizePage(url) { return String(url).split('#')[0].toLowerCase(); }

  function KVBridge(opts) {
    this.page = opts.page;                 // the storage page address (https only, trailing slash)
    this.ns = opts.ns;                     // this mod's namespace, e.g. 'notepad.v1'; keys are '<ns>/<key>'
    this.prefix = opts.prefix;             // reply tag, e.g. 'KV1:'
    this.protocol = opts.protocol || 2;
    this.timeoutSec = opts.timeoutSec || 6;
    this.log = opts.log || function () {};
    this.panel = null;
    this.state = 'idle';                   // idle | connecting | ready | offline
    this.queue = [];
    this.inflight = null;                  // { id, cb, timer }
    this.seq = 0;
    this.waiters = [];
  }

  // parent: a panel that lives as long as you need storage (e.g. your mod's root panel).
  KVBridge.prototype.start = function (parent, panelId) {
    if (this.state !== 'idle') return;
    var self = this;
    var p = parent.FindChildTraverse(panelId);
    if (!p) {
      p = $.CreatePanel('CitadelHTMLPanel', parent, panelId);
      p.hittest = false;
      p.style.width = '2px';
      p.style.height = '2px';
      p.style.opacity = '0.01';
    }
    this.panel = p;
    $.RegisterEventHandler('HTMLTitle', p, function (a, b) { self._onTitle(b === undefined ? a : b); });
    // Never log the fragment: it carries the request (possibly user text).
    $.RegisterEventHandler('HTMLURLChanged', p, function (a, b) { self.log('bridge url ' + String(b === undefined ? a : b).split('#')[0]); });
    this.state = 'connecting';
    if (typeof this.ns !== 'string' || !this.ns) { this.log('bridge needs opts.ns'); return this._settle('offline'); }
    this._hello(1);
  };

  // cb(state) once the bridge is 'ready' or 'offline'.
  KVBridge.prototype.onSettled = function (cb) {
    if (this.state === 'ready' || this.state === 'offline') this._call(cb, this.state);
    else this.waiters.push(cb);
  };

  KVBridge.prototype.get = function (key, cb) {
    this._request({ o: 'get', k: key }, function (m) { cb(m.ok ? null : m.e, m.ok && m.x === 1 ? m.v : null); });
  };
  KVBridge.prototype.set = function (key, value, cb) {
    this._request({ o: 'set', k: key, v: value }, function (m) { if (cb) cb(m.ok ? null : m.e); });
  };
  KVBridge.prototype.del = function (key, cb) {
    this._request({ o: 'del', k: key }, function (m) { if (cb) cb(m.ok ? null : m.e); });
  };
  KVBridge.prototype.getJSON = function (key, cb) {
    this.get(key, function (err, v) {
      if (err || v === null) return cb(err, null);
      var parsed;
      try { parsed = JSON.parse(v); } catch (e) { return cb('bad_json', null); }
      cb(null, parsed);
    });
  };
  KVBridge.prototype.setJSON = function (key, obj, cb) { this.set(key, JSON.stringify(obj), cb); };

  // cb(err, keys[]): follows paging until every key under prefix is collected.
  KVBridge.prototype.list = function (prefix, cb) {
    var self = this, keys = [];
    (function page(start) {
      self._request({ o: 'list', p: prefix, s: start }, function (m) {
        if (!m.ok) return cb(m.e, keys);
        keys = keys.concat(m.keys || []);
        if (m.next > start) page(m.next); else cb(null, keys);   // next must advance, or stop
      });
    })(0);
  };

  // ---- internals ---------------------------------------------------------------------------

  KVBridge.prototype._call = function (cb, arg) {
    try { cb(arg); } catch (e) { this.log('callback error ' + e); }
  };

  KVBridge.prototype._panelAlive = function () {
    try { return !!this.panel && this.panel.IsValid(); } catch (e) { return false; }
  };

  KVBridge.prototype._hello = function (attempt) {
    var self = this;
    this._enqueue({ o: 'hello' }, function (m) {
      if (m.ok && m.v === self.protocol && m.ns === self.ns && normalizePage(m.h) === normalizePage(self.page)) return self._settle('ready');
      if (m.ok) { self.log('bridge protocol/page/ns mismatch v=' + m.v + ' ns=' + m.ns + ' h=' + normalizePage(m.h)); return self._settle('offline'); }
      if (attempt >= HELLO_MAX_TRIES || m.e === 'panel_gone' || m.e === 'bad_ns') return self._settle('offline');
      $.Schedule(HELLO_RETRY_SEC, function () { self._hello(attempt + 1); });
    }, true);
  };

  KVBridge.prototype._settle = function (state) {
    this.state = state;
    this.log('bridge ' + state);
    var w = this.waiters; this.waiters = [];
    for (var n = 0; n < w.length; n++) this._call(w[n], state);
    if (state === 'offline') {
      var q = this.queue; this.queue = [];
      for (var k = 0; k < q.length; k++) this._call(q[k].cb, { ok: false, e: 'offline' });
    }
    this._pump();
  };

  KVBridge.prototype._request = function (msg, cb) {
    if (this.state === 'idle') return this._call(cb, { ok: false, e: 'not_started' });
    if (this.state === 'offline') return this._call(cb, { ok: false, e: 'offline' });
    this._enqueue(msg, cb, false);
  };

  KVBridge.prototype._enqueue = function (msg, cb, hello) {
    var item = { msg: msg, cb: cb, hello: !!hello };
    if (hello) this.queue.unshift(item); else this.queue.push(item);
    this._pump();
  };

  KVBridge.prototype._pump = function () {
    if (this.inflight || !this.queue.length || !this.panel) return;
    if (this.state !== 'ready' && !this.queue[0].hello) return;
    var item = this.queue.shift(), self = this;
    if (!this._panelAlive()) {                // owner panel destroyed: fail everything, go offline
      this._call(item.cb, { ok: false, e: 'panel_gone' });
      if (this.state !== 'offline') this._settle('offline');
      return;
    }
    var id = 'r' + (++this.seq) + '_' + Date.now();
    var msg = { i: id, ns: this.ns };
    for (var key in item.msg) msg[key] = item.msg[key];
    var timer = $.Schedule(this.timeoutSec, function () {
      if (!self.inflight || self.inflight.id !== id) return;
      self.inflight = null;
      self._call(item.cb, { i: id, ok: false, e: 'timeout' });
      self._pump();
    });
    this.inflight = { id: id, cb: item.cb, timer: timer };
    this.panel.SetURL(this.page + '#' + encodeURIComponent(JSON.stringify(msg)));
  };

  KVBridge.prototype._onTitle = function (title) {
    if (typeof title !== 'string' || title.indexOf(this.prefix) !== 0) return;
    var m;
    try { m = JSON.parse(title.slice(this.prefix.length)); } catch (e) { return; }
    var f = this.inflight;
    if (!f || m.i !== f.id) return;          // HTMLTitle fires ~2x per navigation: drop duplicates
    this.inflight = null;
    try { $.CancelScheduled(f.timer); } catch (e) {}
    this._call(f.cb, m);
    this._pump();
  };

  return KVBridge;
})();

if (typeof module !== 'undefined') module.exports = KVBridge;   // Node tests; `module` is undefined in Panorama
