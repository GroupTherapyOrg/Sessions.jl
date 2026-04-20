(function() {
  window.TherapyHydrate = window.TherapyHydrate || {};
  function hydrate_activitybar() {
    document.querySelectorAll('[data-component="activitybar"]:not([data-hydrated])').forEach(function(island) {
      var props = JSON.parse(island.dataset.props || '{}');
      var _wb = new Uint8Array([0,97,115,109,1,0,0,0,1,8,2,96,0,0,96,1,126,0,2,31,2,6,101,102,102,95,106,115,5,101,102,102,95,48,0,1,6,101,102,102,95,106,115,5,101,102,102,95,49,0,1,3,8,7,0,0,0,0,1,0,0,4,5,1,112,1,2,2,6,46,9,126,1,66,0,11,126,1,66,0,11,111,1,208,114,11,111,1,208,114,11,127,1,65,127,11,127,1,65,0,11,126,1,66,0,11,126,1,66,0,11,126,1,66,0,11,7,166,1,16,8,115,105,103,110,97,108,95,48,3,0,8,115,105,103,110,97,108,95,49,3,1,4,104,107,95,51,3,2,4,104,107,95,53,3,3,12,95,114,116,95,111,98,115,101,114,118,101,114,3,4,9,95,114,116,95,98,97,116,99,104,3,5,11,95,114,116,95,112,101,110,100,105,110,103,3,6,10,95,114,116,95,115,117,98,115,95,48,3,7,10,95,114,116,95,115,117,98,115,95,49,3,8,3,95,104,49,0,2,3,95,104,50,0,3,9,95,101,102,102,101,99,116,95,48,0,4,9,95,101,102,102,101,99,116,95,49,0,5,9,95,114,116,95,102,108,117,115,104,0,6,4,95,104,119,49,0,7,4,95,104,119,50,0,8,9,8,1,0,65,0,11,2,4,5,10,138,2,7,9,0,66,1,35,0,125,36,0,11,9,0,66,1,35,1,125,36,1,11,25,0,35,4,65,0,78,4,64,35,7,66,1,35,4,173,134,132,36,7,11,35,0,16,0,11,25,0,35,4,65,0,78,4,64,35,8,66,1,35,4,173,134,132,36,8,11,35,1,16,1,11,68,2,1,127,1,126,3,64,32,1,65,2,72,4,64,32,0,32,1,173,136,66,1,131,167,4,64,32,1,36,4,66,126,32,1,173,137,34,2,35,7,131,36,7,32,2,35,8,131,36,8,32,1,17,0,0,11,32,1,65,1,106,33,1,12,1,11,11,11,61,1,1,126,35,5,65,1,106,36,5,16,2,35,5,65,0,74,4,64,35,6,35,7,132,36,6,11,35,5,65,1,107,36,5,35,5,69,4,64,3,64,35,6,80,69,4,64,35,6,66,0,36,6,16,6,12,1,11,11,11,11,61,1,1,126,35,5,65,1,106,36,5,16,3,35,5,65,0,74,4,64,35,6,35,8,132,36,6,11,35,5,65,1,107,36,5,35,5,69,4,64,3,64,35,6,80,69,4,64,35,6,66,0,36,6,16,6,12,1,11,11,11,11]);
      var _io = __tw.io(island);
      var _eff={};
      _io.eff_js={eff_0:function(_p0){if(_eff[0])_eff[0](_p0);},eff_1:function(_p0){if(_eff[1])_eff[1](_p0);}};
      WebAssembly.instantiate(_wb, _io).then(function(result) {
        var ex = result.instance.exports;
        island._wasmExports = ex;
        island.dataset.hydrated = "true";
        if (props.initial_sidebar !== undefined && typeof props.initial_sidebar === 'number') ex.signal_0.value = BigInt(props.initial_sidebar);
        if (props.initial_terminal !== undefined && typeof props.initial_terminal === 'number') ex.signal_1.value = BigInt(props.initial_terminal);
        var hk_3 = island.querySelector('[data-hk="3"]');
        ex.hk_3.value = hk_3;
        var hk_5 = island.querySelector('[data-hk="5"]');
        ex.hk_5.value = hk_5;
        _eff[0]=function(_p0){    var fp=document.getElementById('fpanel');
    if(fp)fp.style.display=Number(_p0)?'':'none';
    var b=island.querySelector('[data-ab-btn="explorer"]');
    if(b)b.setAttribute('data-state',Number(_p0)?'on':'off');
    localStorage.setItem('sessions-sidebar',Number(_p0)?'1':'0');
;};
        _eff[1]=function(_p0){    var rp=document.getElementById('repl-panel');
    if(rp)rp.style.display=Number(_p0)?'':'none';
    var b=island.querySelector('[data-ab-btn="terminal"]');
    if(b)b.setAttribute('data-state',Number(_p0)?'on':'off');
    localStorage.setItem('sessions-repl',Number(_p0)?'1':'0');
    if(Number(_p0))setTimeout(function(){window.dispatchEvent(new Event('resize'));},50);
;};
        hk_3.$$click = function(e){ex._hw1();};
        hk_5.$$click = function(e){ex._hw2();};
        island.addEventListener("click", function(e){var el=e.target;while(el&&el!==island){if(el.$$click){el.$$click(e);return;}el=el.parentNode;}});
        ex._rt_flush(BigInt(3));
      }).catch(function(e){console.error('[therapy] WASM instantiation failed for activitybar:',e);});
    });
  }
  window.TherapyHydrate["activitybar"] = hydrate_activitybar;
  if (!window._therapyRouterHydrating) (window.requestIdleCallback||setTimeout)(hydrate_activitybar);
})();