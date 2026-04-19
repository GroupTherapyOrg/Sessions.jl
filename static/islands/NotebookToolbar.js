(function() {
  window.TherapyHydrate = window.TherapyHydrate || {};
  function hydrate_notebooktoolbar() {
    document.querySelectorAll('[data-component="notebooktoolbar"]:not([data-hydrated])').forEach(function(island) {
      island.dataset.hydrated = "true";
      var _wb = new Uint8Array([0,97,115,109,1,0,0,0,1,13,3,96,0,0,96,1,126,0,96,2,126,126,0,2,106,7,6,101,102,102,95,106,115,5,101,102,102,95,48,0,1,6,101,102,102,95,106,115,5,101,102,102,95,49,0,1,6,101,102,102,95,106,115,5,101,102,102,95,50,0,2,6,101,102,102,95,106,115,5,101,102,102,95,51,0,1,6,101,102,102,95,106,115,5,101,102,102,95,52,0,1,6,101,102,102,95,106,115,5,101,102,102,95,53,0,1,6,101,102,102,95,106,115,5,101,102,102,95,54,0,1,3,9,8,0,0,0,0,0,0,0,1,4,5,1,112,1,7,7,6,96,19,126,1,66,0,11,126,1,66,0,11,126,1,66,0,11,126,1,66,0,11,126,1,66,0,11,126,1,66,0,11,126,1,66,0,11,126,1,66,1,11,127,1,65,127,11,127,1,65,0,11,126,1,66,0,11,126,1,66,0,11,126,1,66,0,11,126,1,66,0,11,126,1,66,0,11,126,1,66,0,11,126,1,66,0,11,126,1,66,0,11,126,1,66,0,11,7,202,2,27,8,115,105,103,110,97,108,95,48,3,0,8,115,105,103,110,97,108,95,49,3,1,8,115,105,103,110,97,108,95,50,3,2,8,115,105,103,110,97,108,95,51,3,3,8,115,105,103,110,97,108,95,52,3,4,8,115,105,103,110,97,108,95,53,3,5,8,115,105,103,110,97,108,95,54,3,6,8,115,105,103,110,97,108,95,55,3,7,12,95,114,116,95,111,98,115,101,114,118,101,114,3,8,9,95,114,116,95,98,97,116,99,104,3,9,11,95,114,116,95,112,101,110,100,105,110,103,3,10,10,95,114,116,95,115,117,98,115,95,48,3,11,10,95,114,116,95,115,117,98,115,95,49,3,12,10,95,114,116,95,115,117,98,115,95,50,3,13,10,95,114,116,95,115,117,98,115,95,51,3,14,10,95,114,116,95,115,117,98,115,95,52,3,15,10,95,114,116,95,115,117,98,115,95,53,3,16,10,95,114,116,95,115,117,98,115,95,54,3,17,10,95,114,116,95,115,117,98,115,95,55,3,18,9,95,101,102,102,101,99,116,95,48,0,7,9,95,101,102,102,101,99,116,95,49,0,8,9,95,101,102,102,101,99,116,95,50,0,9,9,95,101,102,102,101,99,116,95,51,0,10,9,95,101,102,102,101,99,116,95,52,0,11,9,95,101,102,102,101,99,116,95,53,0,12,9,95,101,102,102,101,99,116,95,54,0,13,9,95,114,116,95,102,108,117,115,104,0,14,9,13,1,0,65,0,11,7,7,8,9,10,11,12,13,10,187,2,8,25,0,35,8,65,0,78,4,64,35,11,66,1,35,8,173,134,132,36,11,11,35,0,16,0,11,25,0,35,8,65,0,78,4,64,35,12,66,1,35,8,173,134,132,36,12,11,35,1,16,1,11,46,0,35,8,65,0,78,4,64,35,14,66,1,35,8,173,134,132,36,14,11,35,8,65,0,78,4,64,35,13,66,1,35,8,173,134,132,36,13,11,35,3,35,2,16,2,11,25,0,35,8,65,0,78,4,64,35,15,66,1,35,8,173,134,132,36,15,11,35,4,16,3,11,25,0,35,8,65,0,78,4,64,35,16,66,1,35,8,173,134,132,36,16,11,35,5,16,4,11,25,0,35,8,65,0,78,4,64,35,17,66,1,35,8,173,134,132,36,17,11,35,6,16,5,11,25,0,35,8,65,0,78,4,64,35,18,66,1,35,8,173,134,132,36,18,11,35,7,16,6,11,110,2,1,126,1,127,3,64,32,2,65,7,72,4,64,32,0,32,2,173,136,66,1,131,167,4,64,32,2,36,8,66,126,32,2,173,137,34,1,35,11,131,36,11,32,1,35,12,131,36,12,32,1,35,13,131,36,13,32,1,35,14,131,36,14,32,1,35,15,131,36,15,32,1,35,16,131,36,16,32,1,35,17,131,36,17,32,1,35,18,131,36,18,32,2,17,0,0,11,32,2,65,1,106,33,2,12,1,11,11,11]);
      var _io = __tw.io(island);
      var _eff={};
      _io.eff_js={eff_0:function(_p0){if(_eff[0])_eff[0](_p0);},eff_1:function(_p0){if(_eff[1])_eff[1](_p0);},eff_2:function(_p0,_p1){if(_eff[2])_eff[2](_p0,_p1);},eff_3:function(_p0){if(_eff[3])_eff[3](_p0);},eff_4:function(_p0){if(_eff[4])_eff[4](_p0);},eff_5:function(_p0){if(_eff[5])_eff[5](_p0);},eff_6:function(_p0){if(_eff[6])_eff[6](_p0);}};
      var _ss={};
      _io.signals={get_s0:function(){return _ss.get_s0()},get_s1:function(){return _ss.get_s1()},get_s2:function(){return _ss.get_s2()},get_s3:function(){return _ss.get_s3()},get_s4:function(){return _ss.get_s4()},get_s5:function(){return _ss.get_s5()},get_s6:function(){return _ss.get_s6()},get_s7:function(){return _ss.get_s7()}};
      WebAssembly.instantiate(_wb, _io).then(function(result) {
        var ex = result.instance.exports;
        island._wasmExports = ex;
        _ss.get_s0=function(){return ex.signal_0.value;};
        window.__therapy.reg("is_executing",ex.signal_0.value,function(v){ex.signal_0.value=BigInt(Number(v)||0);if(ex._rt_subs_0)ex._rt_flush(ex._rt_subs_0.value);});
        _ss.get_s1=function(){return ex.signal_1.value;};
        window.__therapy.reg("stale_count",ex.signal_1.value,function(v){ex.signal_1.value=BigInt(Number(v)||0);if(ex._rt_subs_1)ex._rt_flush(ex._rt_subs_1.value);});
        _ss.get_s2=function(){return ex.signal_2.value;};
        window.__therapy.reg("run_progress_total",ex.signal_2.value,function(v){ex.signal_2.value=BigInt(Number(v)||0);if(ex._rt_subs_2)ex._rt_flush(ex._rt_subs_2.value);});
        _ss.get_s3=function(){return ex.signal_3.value;};
        window.__therapy.reg("run_progress_current",ex.signal_3.value,function(v){ex.signal_3.value=BigInt(Number(v)||0);if(ex._rt_subs_3)ex._rt_flush(ex._rt_subs_3.value);});
        _ss.get_s4=function(){return ex.signal_4.value;};
        window.__therapy.reg("is_unsaved",ex.signal_4.value,function(v){ex.signal_4.value=BigInt(Number(v)||0);if(ex._rt_subs_4)ex._rt_flush(ex._rt_subs_4.value);});
        _ss.get_s5=function(){return ex.signal_5.value;};
        window.__therapy.reg("is_formatting",ex.signal_5.value,function(v){ex.signal_5.value=BigInt(Number(v)||0);if(ex._rt_subs_5)ex._rt_flush(ex._rt_subs_5.value);});
        _ss.get_s6=function(){return ex.signal_6.value;};
        window.__therapy.reg("active_is_file",ex.signal_6.value,function(v){ex.signal_6.value=BigInt(Number(v)||0);if(ex._rt_subs_6)ex._rt_flush(ex._rt_subs_6.value);});
        _ss.get_s7=function(){return ex.signal_7.value;};
        window.__therapy.reg("active_can_format",ex.signal_7.value,function(v){ex.signal_7.value=BigInt(Number(v)||0);if(ex._rt_subs_7)ex._rt_flush(ex._rt_subs_7.value);});
        _eff[0]=function(_p0){    var idle=island.querySelector('[data-pill-mode="idle"]');
    var run=island.querySelector('[data-pill-mode="running"]');
    if(idle)idle.style.display=Number(_p0)?'none':'';
    if(run) run.style.display =Number(_p0)?'':'none';
;};
        _eff[1]=function(_p0){    var btn=island.querySelector('[data-run-stale]');
    if(btn)btn.className=Number(_p0)>0?'pill-btn pill-stale':'pill-btn pill-stale tb-disabled';
    var bd=island.querySelector('[data-stale-badge]');
    if(bd){bd.textContent=String(Number(_p0));bd.style.display=Number(_p0)>0?'':'none';}
;};
        _eff[2]=function(_p0,_p1){    var sep=island.querySelector('[data-pill-sep]');
    var zone=island.querySelector('[data-pill-status]');
    var jump=island.querySelector('[data-pill-jump]');
    var show=Number(_p1)>0;
    if(sep)sep.style.display=show?'':'none';
    if(jump)jump.style.display=show?'':'none';
    if(zone){
        zone.style.display=show?'':'none';
        if(show){
            var pct=Math.max(0,Math.min(100,Math.round(Number(_p0)*100/Number(_p1))));
            zone.innerHTML='<span class="pill-dot"></span><span class="pill-count">'+Number(_p0)+' / '+Number(_p1)+'</span><div class="pill-bar"><div class="pill-bar-fill" style="width:'+pct+'%"></div></div>';
        }
    }
;};
        _eff[3]=function(_p0){    var btn=island.querySelector('[data-save-indicator]');
    if(!btn)return;
    btn.textContent=Number(_p0)?'\u25CF Save':'Save';
    btn.className=Number(_p0)?'pill-btn pill-ghost pill-unsaved':'pill-btn pill-ghost';
;};
        _eff[4]=function(_p0){    var btn=island.querySelector('[data-format-btn]');
    if(!btn)return;
    btn.textContent=Number(_p0)?'Formatting...':'Format';
;};
        _eff[5]=function(_p0){    var nc=island.querySelector('[data-notebook-controls]');
    if(nc)nc.style.display=Number(_p0)?'none':'';
;};
        _eff[6]=function(_p0){    var btn=island.querySelector('[data-format-btn]');
    if(!btn)return;
    if(Number(_p0))btn.classList.remove('tb-disabled');
    else btn.classList.add('tb-disabled');
;};
        ex._rt_flush(BigInt(127));
      }).catch(function(e){console.error('[therapy] WASM instantiation failed for notebooktoolbar:',e);});
    });
  }
  window.TherapyHydrate["notebooktoolbar"] = hydrate_notebooktoolbar;
  if (!window._therapyRouterHydrating) (window.requestIdleCallback||setTimeout)(hydrate_notebooktoolbar);
})();