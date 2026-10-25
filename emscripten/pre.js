// Kobo Deluxe web glue: canvas, logging, persistence (IDBFS), click-to-start.
var Module = typeof Module !== 'undefined' ? Module : {};
Module.noInitialRun = true;
Module.print = function () { console.log.apply(console, arguments); };
Module.printErr = function () { console.warn.apply(console, arguments); };
Module.canvas = document.getElementById('canvas');

Module.preRun = Module.preRun || [];
Module.preRun.push(function () {
  // HOME must be set before libc initialises its environment.
  ENV.HOME = '/home/web_user';
  FS.mkdirTree('/home/web_user');
  FS.mount(IDBFS, {}, '/home/web_user');
  // Load saved profiles/settings from IndexedDB before the game can run.
  addRunDependency('kobo-idbfs');
  FS.syncfs(true, function (err) {
    if (err) console.warn('IDBFS load failed', err);
    try { FS.mkdirTree('/home/web_user/.kobodeluxe'); } catch (e) {}
    Module.persistReady = true;
    removeRunDependency('kobo-idbfs');
  });
});

Module.persistNow = function () {
  if (!Module.persistReady || Module._syncing) { Module._dirty = true; return; }
  Module._syncing = true;
  Module._dirty = false;
  try {
    FS.syncfs(false, function (err) {
      Module._syncing = false;
      if (err) console.warn('IDBFS save failed', err);
      else console.log('[persist] synced to IndexedDB');
      if (Module._dirty) Module.persistNow();
    });
  } catch (e) { Module._syncing = false; console.warn(e); }
};

Module.setStatus = function (text) {
  var bar = document.getElementById('bar'), st = document.getElementById('status');
  if (!st) return;
  var m = /(\d+(?:\.\d+)?)\/(\d+)/.exec(text || '');
  if (m && bar) bar.style.width = (100 * m[1] / m[2]).toFixed(1) + '%';
  if (text) { st.textContent = text; } 
  else { Module.loaded = true; if (window.koboLoaded) window.koboLoaded(); }
};
Module.monitorRunDependencies = function (left) {
  if (left === 0 && Module.loaded && window.koboLoaded) window.koboLoaded();
};

window.koboStart = function () {
  if (Module.started) return;
  Module.started = true;
  var c = document.getElementById('canvas');
  c.tabIndex = 0;
  c.focus();
  try { Module.callMain([]); } catch (e) { console.warn(e); }
  c.focus();
  setInterval(Module.persistNow, 5000);
  document.addEventListener('visibilitychange', function () {
    if (document.visibilityState === 'hidden') Module.persistNow();
  });
  window.addEventListener('pagehide', Module.persistNow);
};
