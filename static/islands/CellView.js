(function() {
  window.TherapyHydrate = window.TherapyHydrate || {};
  function hydrate_cellview() {
    document.querySelectorAll('[data-component="cellview"]:not([data-hydrated])').forEach(function(island) {
      var props = JSON.parse(island.dataset.props || '{}');
      var _wb = new Uint8Array([0,97,115,109,1,0,0,0,1,23,5,96,0,0,96,1,126,0,96,3,111,111,127,0,96,2,126,126,0,96,0,1,127,2,62,4,3,100,111,109,9,115,104,111,119,95,115,119,97,112,0,2,6,101,102,102,95,106,115,5,101,102,102,95,48,0,3,6,101,102,102,95,106,115,5,101,102,102,95,49,0,1,6,101,102,102,95,106,115,5,101,102,102,95,50,0,1,3,9,8,0,0,0,0,4,0,1,0,4,5,1,112,1,4,4,6,76,15,126,1,66,0,11,126,1,66,0,11,126,1,66,0,11,126,1,66,1,11,111,1,208,114,11,111,1,208,114,11,127,1,65,127,11,127,1,65,0,11,126,1,66,0,11,126,1,66,0,11,126,1,66,0,11,126,1,66,0,11,126,1,66,0,11,111,1,208,114,11,127,1,65,127,11,7,243,1,21,8,115,105,103,110,97,108,95,48,3,0,8,115,105,103,110,97,108,95,49,3,1,8,115,105,103,110,97,108,95,50,3,2,8,115,105,103,110,97,108,95,51,3,3,4,104,107,95,50,3,4,4,104,107,95,52,3,5,12,95,114,116,95,111,98,115,101,114,118,101,114,3,6,9,95,114,116,95,98,97,116,99,104,3,7,11,95,114,116,95,112,101,110,100,105,110,103,3,8,10,95,114,116,95,115,117,98,115,95,48,3,9,10,95,114,116,95,115,117,98,115,95,49,3,10,10,95,114,116,95,115,117,98,115,95,50,3,11,10,95,114,116,95,115,117,98,115,95,51,3,12,3,95,104,49,0,4,9,95,101,102,102,101,99,116,95,48,0,5,9,95,101,102,102,101,99,116,95,49,0,6,9,95,101,102,102,101,99,116,95,50,0,7,12,95,115,104,111,119,95,98,97,114,101,95,52,0,8,12,95,115,104,111,119,95,52,95,102,114,97,103,3,13,9,95,114,116,95,102,108,117,115,104,0,10,4,95,104,119,49,0,11,9,10,1,0,65,0,11,4,9,5,6,7,10,184,2,8,9,0,66,1,35,3,125,36,3,11,46,0,35,6,65,0,78,4,64,35,9,66,1,35,6,173,134,132,36,9,11,35,6,65,0,78,4,64,35,10,66,1,35,6,173,134,132,36,10,11,35,0,35,1,16,1,11,25,0,35,6,65,0,78,4,64,35,11,66,1,35,6,173,134,132,36,11,11,35,2,16,2,11,25,0,35,6,65,0,78,4,64,35,12,66,1,35,6,173,134,132,36,12,11,35,3,16,3,11,5,0,35,3,167,11,50,1,1,127,35,6,65,0,78,4,64,35,12,66,1,35,6,173,134,132,36,12,11,35,3,167,65,0,71,34,0,35,14,70,4,64,15,11,32,0,36,14,35,5,35,13,32,0,16,0,11,82,2,1,127,1,126,3,64,32,1,65,4,72,4,64,32,0,32,1,173,136,66,1,131,167,4,64,32,1,36,6,66,126,32,1,173,137,34,2,35,9,131,36,9,32,2,35,10,131,36,10,32,2,35,11,131,36,11,32,2,35,12,131,36,12,32,1,17,0,0,11,32,1,65,1,106,33,1,12,1,11,11,11,61,1,1,126,35,7,65,1,106,36,7,16,4,35,7,65,0,74,4,64,35,8,35,12,132,36,8,11,35,7,65,1,107,36,7,35,7,69,4,64,3,64,35,8,80,69,4,64,35,8,66,0,36,8,16,10,12,1,11,11,11,11]);
      var _io = __tw.io(island);
      var _eff={};
      _io.eff_js={eff_0:function(_p0,_p1){if(_eff[0])_eff[0](_p0,_p1);},eff_1:function(_p0){if(_eff[1])_eff[1](_p0);},eff_2:function(_p0){if(_eff[2])_eff[2](_p0);}};
      WebAssembly.instantiate(_wb, _io).then(function(result) {
        var ex = result.instance.exports;
        island._wasmExports = ex;
        island.dataset.hydrated = "true";
        if (props.initial_state !== undefined && typeof props.initial_state === 'number') ex.signal_0.value = BigInt(props.initial_state);
        if (props.initial_stale !== undefined && typeof props.initial_stale === 'number') ex.signal_1.value = BigInt(props.initial_stale);
        if (props.initial_runtime_ns !== undefined && typeof props.initial_runtime_ns === 'number') ex.signal_2.value = BigInt(props.initial_runtime_ns);
        if (props.initial_open !== undefined && typeof props.initial_open === 'number') ex.signal_3.value = BigInt(props.initial_open);
        var hk_2 = island.querySelector('[data-hk="2"]');
        ex.hk_2.value = hk_2;
        var hk_4 = island.querySelector('[data-hk="4"]');
        ex.hk_4.value = hk_4;
        _eff[0]=function(_p0,_p1){    var el=island.querySelector('.code-cell');
    if(!el)return;
    var base='code-cell relative overflow-hidden';
    if(Number(_p0)===1)base+=' cv-queued executing';
    else if(Number(_p0)===2)base+=' cv-running executing';
    else if(Number(_p0)===4)base+=' cv-errored';
    else if(Number(_p0)===5)base+=' cv-skipped';
    if(Number(_p1))base+=' stale';
    el.className=base;
;};
        _eff[1]=function(_p0){    var b=island.querySelector('.rt-badge');
    if(!b)return;
    var n=Number(_p0);
    if(n<=0){b.textContent='';return;}
    var ms=n/1e6;
    if(ms<1){b.textContent=(n/1e3).toFixed(1)+'\u00b5s';return;}
    if(ms<1000){b.textContent=ms.toFixed(1)+'ms';return;}
    var s=ms/1000;
    if(s<60){b.textContent=s.toFixed(1)+'s';return;}
    var m=s/60;
    if(m<60){b.textContent=m.toFixed(1)+'min';return;}
    b.textContent=(m/60).toFixed(1)+'hr';
;};
        _eff[2]=function(_p0){    var c=island.querySelector('.cell-code-wrap');
    if(c)c.style.display=Number(_p0)?'':'none';
    var wrap=island.closest('.cell-wrap');
    if(wrap){
        if(Number(_p0)) wrap.classList.remove('code-hidden');
        else wrap.classList.add('code-hidden');
    }
    if(!island._foldInit){island._foldInit=true;return;}
    var cid=wrap?wrap.dataset.cellId:'';
    if(cid&&window.TherapyWS&&TherapyWS.sendMessage){
        TherapyWS.sendMessage('notebook',{action:'toggle_fold',cell_id:cid,folded:!Number(_p0)});
    }
;};
        var _show_4_frag = document.createDocumentFragment();
        while(hk_4.firstChild) _show_4_frag.appendChild(hk_4.firstChild);
        hk_4.style.display = '';
        ex._show_4_frag.value = _show_4_frag;
        hk_2.$$click = function(e){ex._hw1();};
        island.addEventListener("click", function(e){var el=e.target;while(el&&el!==island){if(el.$$click){el.$$click(e);return;}el=el.parentNode;}});
        ex._rt_flush(BigInt(15));
      }).catch(function(e){console.error('[therapy] WASM instantiation failed for cellview:',e);});
    });
  }
  window.TherapyHydrate["cellview"] = hydrate_cellview;
  if (!window._therapyRouterHydrating) (window.requestIdleCallback||setTimeout)(hydrate_cellview);
})();