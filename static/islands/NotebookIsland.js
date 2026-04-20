(function() {
  window.TherapyHydrate = window.TherapyHydrate || {};
  function hydrate_notebookisland() {
    document.querySelectorAll('[data-component="notebookisland"]:not([data-hydrated])').forEach(function(island) {
      var _wb = new Uint8Array([0,97,115,109,1,0,0,0,6,16,3,127,1,65,127,11,127,1,65,0,11,126,1,66,0,11,7,42,3,12,95,114,116,95,111,98,115,101,114,118,101,114,3,0,9,95,114,116,95,98,97,116,99,104,3,1,11,95,114,116,95,112,101,110,100,105,110,103,3,2]);
      var _io = __tw.io(island);
      WebAssembly.instantiate(_wb, _io).then(function(result) {
        var ex = result.instance.exports;
        island._wasmExports = ex;
        island.dataset.hydrated = "true";
        queueMicrotask(function(){if(window._initAllCM) _initAllCM();if(window._setupWSBridge) _setupWSBridge();});
      }).catch(function(e){console.error('[therapy] WASM instantiation failed for notebookisland:',e);});
    });
  }
  window.TherapyHydrate["notebookisland"] = hydrate_notebookisland;
  if (!window._therapyRouterHydrating) (window.requestIdleCallback||setTimeout)(hydrate_notebookisland);
})();