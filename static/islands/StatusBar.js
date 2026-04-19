(function() {
  window.TherapyHydrate = window.TherapyHydrate || {};
  function hydrate_statusbar() {
    document.querySelectorAll('[data-component="statusbar"]:not([data-hydrated])').forEach(function(island) {
      island.dataset.hydrated = "true";
      var _wb = new Uint8Array([0,97,115,109,1,0,0,0,1,8,2,96,0,0,96,1,126,0,2,42,3,6,101,102,102,95,106,115,5,101,102,102,95,48,0,1,6,101,102,102,95,106,115,5,101,102,102,95,49,0,1,2,106,115,5,106,115,95,104,49,0,0,3,6,5,0,0,0,1,0,4,5,1,112,1,2,2,6,51,10,126,1,66,0,11,126,1,66,0,11,126,1,66,1,11,111,1,208,114,11,127,1,65,127,11,127,1,65,0,11,126,1,66,0,11,126,1,66,0,11,126,1,66,0,11,126,1,66,0,11,7,170,1,15,8,115,105,103,110,97,108,95,48,3,0,8,115,105,103,110,97,108,95,49,3,1,8,115,105,103,110,97,108,95,50,3,2,4,104,107,95,56,3,3,12,95,114,116,95,111,98,115,101,114,118,101,114,3,4,9,95,114,116,95,98,97,116,99,104,3,5,11,95,114,116,95,112,101,110,100,105,110,103,3,6,10,95,114,116,95,115,117,98,115,95,48,3,7,10,95,114,116,95,115,117,98,115,95,49,3,8,10,95,114,116,95,115,117,98,115,95,50,3,9,3,95,104,49,0,3,9,95,101,102,102,101,99,116,95,48,0,4,9,95,101,102,102,101,99,116,95,49,0,5,9,95,114,116,95,102,108,117,115,104,0,6,4,95,104,119,49,0,7,9,8,1,0,65,0,11,2,4,5,10,203,1,5,11,0,66,1,35,0,125,36,0,16,2,11,25,0,35,4,65,0,78,4,64,35,8,66,1,35,4,173,134,132,36,8,11,35,1,16,0,11,25,0,35,4,65,0,78,4,64,35,9,66,1,35,4,173,134,132,36,9,11,35,2,16,1,11,75,2,1,127,1,126,3,64,32,1,65,2,72,4,64,32,0,32,1,173,136,66,1,131,167,4,64,32,1,36,4,66,126,32,1,173,137,34,2,35,7,131,36,7,32,2,35,8,131,36,8,32,2,35,9,131,36,9,32,1,17,0,0,11,32,1,65,1,106,33,1,12,1,11,11,11,61,1,1,126,35,5,65,1,106,36,5,16,3,35,5,65,0,74,4,64,35,6,35,7,132,36,6,11,35,5,65,1,107,36,5,35,5,69,4,64,3,64,35,6,80,69,4,64,35,6,66,0,36,6,16,6,12,1,11,11,11,11]);
      var _io = __tw.io(island);
      _io.js={js_h1:function(){document.documentElement.classList.toggle('dark');localStorage.setItem('sessions-theme',document.documentElement.classList.contains('dark')?'dark':'light');if(window._sessionsThemeSwitch)_sessionsThemeSwitch()}};
      var _eff={};
      _io.eff_js={eff_0:function(_p0){if(_eff[0])_eff[0](_p0);},eff_1:function(_p0){if(_eff[1])_eff[1](_p0);}};
      var _ss={};
      _io.signals={get_s1:function(){return _ss.get_s1()},get_s2:function(){return _ss.get_s2()}};
      WebAssembly.instantiate(_wb, _io).then(function(result) {
        var ex = result.instance.exports;
        island._wasmExports = ex;
        _ss.get_s1=function(){return ex.signal_1.value;};
        window.__therapy.reg("cellcount",ex.signal_1.value,function(v){ex.signal_1.value=BigInt(Number(v)||0);if(ex._rt_subs_1)ex._rt_flush(ex._rt_subs_1.value);});
        _ss.get_s2=function(){return ex.signal_2.value;};
        window.__therapy.reg("connection",ex.signal_2.value,function(v){ex.signal_2.value=BigInt(Number(v)||0);if(ex._rt_subs_2)ex._rt_flush(ex._rt_subs_2.value);});
        var hk_8 = island.querySelector('[data-hk="8"]');
        ex.hk_8.value = hk_8;
        _eff[0]=function(_p0){    var el=island.querySelector('[data-cell-count]');
    if(el)el.textContent=String(Number(_p0))+' cells';
;};
        _eff[1]=function(_p0){    var d=island.querySelector('[data-ws-dot]');
    if(d)d.style.color=Number(_p0)?'var(--status-done)':'var(--status-error)';
    var l=island.querySelector('[data-ws-label]');
    if(l)l.textContent=Number(_p0)?' connected':' disconnected';
;};
        hk_8.$$click = function(e){ex._hw1();};
        island.addEventListener("click", function(e){var el=e.target;while(el&&el!==island){if(el.$$click){el.$$click(e);return;}el=el.parentNode;}});
        ex._rt_flush(BigInt(3));
      }).catch(function(e){console.error('[therapy] WASM instantiation failed for statusbar:',e);});
    });
  }
  window.TherapyHydrate["statusbar"] = hydrate_statusbar;
  if (!window._therapyRouterHydrating) (window.requestIdleCallback||setTimeout)(hydrate_statusbar);
})();