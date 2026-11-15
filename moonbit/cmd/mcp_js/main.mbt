// cmd/mcp_js 入口：壳只做三件事——教学表装载（烘焙表进程级单次）、
// Server 构造（Host 钩子注入）、stdin 行循环驱动。全部工具语义在
// vitro/engine/mcp（禁在此加协议/工具逻辑——壳与核心分层，cmd/vitro_js
// 对 cmd/lib/cli 同款纪律）。

///|
fn main {
  @content_data.install_baked()
  js_write_stderr(
    "vitro-dsh-plugin MCP server ready（mbt 核心，12 工具 L0 5 + L1 7，stdio JSON-RPC 2.0，产物目录 <cwd>/vitro-out）\n",
  )
  let srv = @mcp.Server::new(host=@mcp.Host::{
    clock_ms: () => js_clock(),
    render: data => {
      let out = js_render_hook(data.stringify())
      @util.json_parse(out) catch {
        _ => Json::null()
      }
    },
  })
  js_stdin_line_loop(
    line => {
      for frame in srv.handle_line(line) {
        js_write_stdout(frame + "\n")
      }
    },
    () => js_exit(0),
  )
}

///|
extern "js" fn js_clock() -> Double =
  #| function() {
  #| return Date.now();
  #| }

///|
extern "js" fn js_write_stdout(s : String) -> Unit =
  #| function(s) {
  #| process.getBuiltinModule("fs").writeSync(1, Buffer.from(s, "utf8"));
  #| }

///|
extern "js" fn js_write_stderr(s : String) -> Unit =
  #| function(s) {
  #| process.getBuiltinModule("fs").writeSync(2, Buffer.from(s, "utf8"));
  #| }

///|
extern "js" fn js_exit(code : Int32) -> Unit =
  #| function(code) {
  #| process.exit(code);
  #| }

///|
/// 行流注册：on_line = 每行回调；on_close = stdin EOF 回调（exit 语义）。
extern "js" fn js_stdin_line_loop(
  on_line : (String) -> Unit,
  on_close : () -> Unit,
) -> Unit =
  #| function(onLine, onClose) {
  #| const readline = process.getBuiltinModule("readline");
  #| const rl = readline.createInterface({ input: process.stdin, terminal: false });
  #| rl.on("line", (l) => { onLine(l); });
  #| rl.on("close", () => { onClose(); });
  #| }

///|
/// 渲染落盘钩子（v1 lib/render.mjs + keyframes.mjs + build.mjs 落盘段整体
/// 移植，浏览器资产归壳层——用户拍板「TS 仅限无法 mbt 化的壳层」；帧数据
/// 逻辑已在 mbt 侧单源）。入参 = render_entry 构造的 data JSON（snake_case
/// 键）；出参 {ok,html_path,size_bytes,frame_count,mode_used,warnings[],
/// preview_png_path?,preview_png_b64?,error?}。interactive 无 wasm 时回落
/// static（mbt 侧恒传关键帧——回落即用，无双源分叉）。
extern "js" fn js_render_hook(data_json : String) -> String =
  #| function(dataJson) {
  #| const fs = process.getBuiltinModule("fs");
  #| const path = process.getBuiltinModule("path");
  #| const o = JSON.parse(dataJson);
  #| const esc = (s) => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  #| const jstr = (v) => JSON.stringify(v).replace(/</g, "\\u003c").replace(/\u2028|\u2029/g, (c) => (c === "\u2028" ? "\\u2028" : "\\u2029"));
  #| const sleep = (ms) => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
  #| function resolveWasm() {
  #| const cands = [];
  #| if (process.env.VITRO_MCP_WASM) cands.push(process.env.VITRO_MCP_WASM);
  #| cands.push(path.join(process.cwd(), "engine", "wasm.wasm"), path.join(process.cwd(), "wasm.wasm"));
  #| for (const p of cands) { try { if (fs.existsSync(p)) return p; } catch {} }
  #| return null;
  #| }
  #| function findBrowser() {
  #| const EDGE = ["C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe","C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe","C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe","C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe"];
  #| for (const p of EDGE) { try { if (fs.existsSync(p)) return p; } catch {} }
  #| return null;
  #| }
  #| function shotPng(exe, url, outPng, budget) {
  #| const { spawn } = process.getBuiltinModule("child_process");
  #| const args = ["--headless","--disable-gpu","--user-data-dir=" + outPng + ".prof","--window-size=1280,860","--screenshot=" + outPng,"--virtual-time-budget=" + budget, url];
  #| const ch = spawn(exe, args, { stdio: "ignore" });
  #| const t0 = Date.now();
  #| let r = { ok: false, err: "png not written in 20s", bytes: 0 };
  #| while (Date.now() - t0 < 20000) {
  #| sleep(200);
  #| try { const b = fs.statSync(outPng).size; if (b > 5000) { r = { ok: true, bytes: b }; break; } } catch {}
  #| }
  #| try { ch.kill(); } catch {}
  #| try { fs.rmSync(outPng + ".prof", { recursive: true, force: true }); } catch {}
  #| return r;
  #| }
  #| const CSS = `
  #| :root{--bg:#0f1117;--fg:#e6e8ee;--panel:#171a23;--line:#262b38;--muted:#8b93a7;--accent:#5b9dff;--swap:#ff8a4c;--changed:#ffd166;--ok:#3ecf8e;--err:#ff5d73;--code-bg:#12141c;--code-cur:#1f2941;--code-err:#3a1c22}
  #| [data-theme=light]{--bg:#f7f8fa;--fg:#1c2030;--panel:#ffffff;--line:#e3e6ee;--muted:#667;--accent:#2563eb;--swap:#d2601a;--changed:#9a7b00;--ok:#0e8a5f;--err:#d13438;--code-bg:#f2f3f7;--code-cur:#dbe7ff;--code-err:#ffe1e3}
  #| *{box-sizing:border-box}
  #| html{margin:0;height:100%}
  #| body{margin:0;min-height:100%}
  #| body{background:var(--bg);color:var(--fg);font:14px/1.5 system-ui,"Segoe UI","Microsoft YaHei",sans-serif;display:flex;flex-direction:column}
  #| header{display:flex;align-items:center;gap:10px;padding:10px 16px;border-bottom:1px solid var(--line);flex-wrap:wrap}
  #| header h1{font-size:16px;margin:0;flex:1;min-width:200px}
  #| .badge{background:color-mix(in srgb,var(--accent) 18%,transparent);color:var(--accent);border:1px solid var(--accent);border-radius:999px;padding:1px 10px;font-size:12px}
  #| .badge.gray{color:var(--muted);border-color:var(--muted)}
  #| .ver{color:var(--muted);font-size:11px}
  #| main{flex:1;display:grid;grid-template-columns:minmax(240px,34%) 1fr minmax(200px,22%);gap:10px;padding:10px 14px;min-height:0;overflow:hidden}
  #| @media(max-width:900px){main{grid-template-columns:1fr;overflow:auto}}
  #| section,aside{background:var(--panel);border:1px solid var(--line);border-radius:10px;min-height:0;display:flex;flex-direction:column}
  #| .sec-t{padding:8px 12px;font-size:12px;color:var(--muted);border-bottom:1px solid var(--line);flex:none}
  #| #codeWrap{flex:1;overflow:auto;background:var(--code-bg);border-radius:0 0 10px 10px;font:12.5px/1.65 ui-monospace,Consolas,monospace}
  #| .ln{display:flex;white-space:pre;padding:0 8px 0 0}
  #| .ln .no{width:3.2em;flex:none;text-align:right;color:var(--muted);padding-right:10px;user-select:none}
  #| .ln code{flex:1}
  #| .ln.cur{background:var(--code-cur);box-shadow:inset 3px 0 0 var(--accent)}
  #| .ln.err{background:var(--code-err);animation:pulse 1.6s ease-in-out infinite}
  #| .ln.hl-bp{box-shadow:inset 3px 0 0 var(--swap)}
  #| @keyframes pulse{50%{filter:brightness(1.35)}}
  #| #stage{padding:12px;gap:12px;overflow:auto}
  #| .arr{margin-bottom:14px}
  #| .arr-h{font:600 13px ui-monospace,monospace;color:var(--muted);margin-bottom:6px}
  #| .cells{position:relative;display:grid;gap:6px;grid-template-columns:repeat(var(--n),var(--cw))}
  #| .cell{position:relative;width:var(--cw);height:52px;border:1.5px solid var(--line);border-radius:8px;background:var(--bg);display:flex;align-items:center;justify-content:center;font:600 15px ui-monospace,monospace;transition:transform .18s,background .3s,border-color .3s}
  #| .cell .bar{position:absolute;left:6px;right:6px;bottom:4px;height:calc(var(--v)*30%);max-height:34px;background:color-mix(in srgb,var(--accent) 25%,transparent);border-radius:4px;transition:height .25s}
  #| .cell .idx{position:absolute;top:-18px;left:0;right:0;text-align:center;font-size:10px;color:var(--muted)}
  #| .cell.swap{border-color:var(--swap);transform:translateY(-6px);background:color-mix(in srgb,var(--swap) 16%,var(--bg))}
  #| .cell.changed{animation:flash .6s}
  #| @keyframes flash{0%{background:color-mix(in srgb,var(--changed) 55%,var(--bg));border-color:var(--changed)}100%{}}
  #| .ptrs{display:grid;gap:6px;grid-template-columns:repeat(var(--n),var(--cw));margin-top:4px;min-height:20px}
  #| .ptr{font:11px ui-monospace,monospace;color:var(--accent);text-align:center}
  #| .arc{position:absolute;pointer-events:none;overflow:visible}
  #| #diag{display:flex;flex-direction:column;gap:10px}
  #| .dcard{border:1.5px solid var(--err);border-radius:10px;padding:10px 14px;opacity:0;animation:rise .5s forwards}
  #| .dcard.warn{border-color:var(--changed)}
  #| @keyframes rise{from{opacity:0;transform:translateY(10px)}to{opacity:1}}
  #| .dcard .dcode{font:700 12px ui-monospace,monospace;color:var(--err)}
  #| .dcard .dloc{color:var(--muted);font-size:12px;margin:2px 0 6px}
  #| .dcard .dfix{margin-top:6px;color:var(--ok);font-size:13px}
  #| aside .pane{flex:1;min-height:0;display:flex;flex-direction:column}
  #| #vars{flex:1;overflow:auto;padding:6px 10px}
  #| table{border-collapse:collapse;width:100%;font:12.5px ui-monospace,monospace}
  #| td{padding:3px 6px;border-bottom:1px solid var(--line);vertical-align:top}
  #| #vars td:first-child{white-space:nowrap}
  #| #vars td.ver{white-space:nowrap;font-size:11px}
  #| td.vv{color:var(--accent);word-break:break-all}
  #| td.changed{color:var(--changed)}
  #| #stack{padding:6px 10px;font:12.5px ui-monospace,monospace}
  #| #stack .fr2{padding:2px 6px;border-left:2px solid var(--line);margin:2px 0;color:var(--muted)}
  #| #stack .fr2.top{color:var(--fg);border-color:var(--accent)}
  #| #stack .fr2.top::before{content:"\\25B6 ";}
  #| #stdout{padding:6px 10px;font:12px ui-monospace,monospace;white-space:pre-wrap;color:var(--ok);max-height:110px;overflow:auto;border-top:1px solid var(--line)}
  #| footer{border-top:1px solid var(--line);padding:8px 14px;display:flex;flex-direction:column;gap:6px;flex:none}
  #| #cap{min-height:22px;font-weight:600}
  #| #cap .as{color:var(--muted);font-weight:400;font-size:12px}
  #| .bar-row{display:flex;align-items:center;gap:8px}
  #| button,select,input[type=number]{background:var(--panel);color:var(--fg);border:1px solid var(--line);border-radius:7px;padding:4px 10px;font:13px inherit;cursor:pointer}
  #| button:hover{border-color:var(--accent)}
  #| button:disabled{opacity:.4;cursor:default}
  #| input[type=range]{flex:1;accent-color:var(--accent)}
  #| #fnum{font:12px ui-monospace,monospace;color:var(--muted);min-width:90px;text-align:right}
  #| #bpBox{display:none;gap:6px;align-items:center}
  #| #bpBox.on{display:flex}
  #| .hdrbtn{font-size:12px;padding:2px 8px}
  #| @media (prefers-reduced-motion:reduce){*{animation:none!important;transition:none!important}}
  #| `;
  #| const PLAYER = `
  #| var D=window.__VITRO__;
  #| var S={cur:0,playing:false,timer:null,speed:200,frames:D.frames||[],prevC:null,speakOn:false,lastCap:""};
  #| function $(id){return document.getElementById(id)}
  #| function arrDims(fr,nm){for(var i=0;i<fr.v.length;i++){if(fr.v[i][0]===nm){var m=/\\\[(\\\d+)\\\]\\\[(\\\d+)\\\](?![\\\[])\\s*$/.exec(fr.v[i][1]);if(m)return [+m[1],+m[2]]}}return null}
  #| function ctxMentions(ctx,nm){if(!nm)return false;var esc=nm.replace(/[.*+?^\${}()|[\]\\\\]/g,"\\\\$&");return new RegExp("(^|[^\\\\w.])"+esc+"\\\\s*\\\\[").test(ctx)}
  #| function swapPair(fr,nm,len){
  #| for(var k=0;k<fr.e.length;k++){var ev=fr.e[k];
  #| if(ev[0]!==2||!ctxMentions(ev[5],nm))continue;
  #| var x=ev[2],y=ev[3];
  #| if(!Number.isInteger(x)||!Number.isInteger(y)||x<0||y<0||x===y)continue;
  #| var lo=Math.min(x,y),hi=Math.max(x,y);
  #| if(hi>=len)continue;
  #| return{i:lo,j:hi}}
  #| return null}
  #| function renderCode(){var lines=D.source.split("\\n");var h="";var heat=D.heat||{};
  #| for(var n=1;n<=lines.length;n++){var cls="ln"+(D.errLines&&D.errLines.indexOf(n)>=0?" err":"");
  #| h+='<div class="'+cls+'" data-l="'+n+'"><span class="no">'+n+'</span><code>'+esc(lines[n-1]||" ")+'</code></div>'}
  #| $("codeWrap").innerHTML=h}
  #| function esc(s){return String(s).replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;")}
  #| function renderFrame(){var k=S.cur,fr=S.frames[k],pv=k>0?S.frames[k-1]:null;
  #| if(!fr)return;
  #| var cur=document.querySelector(".ln.cur");if(cur)cur.classList.remove("cur");
  #| var row=document.querySelector('.ln[data-l="'+fr.l+'"]');if(row){row.classList.add("cur");row.scrollIntoView({block:"nearest"})}
  #| var names=D.focus||Object.keys(fr.r||{});
  #| var h="";
  #| for(var ai=0;ai<names.length;ai++){var nm=names[ai],els=(fr.r||{})[nm]||[];
  #| if(!els.length)continue;var pels=pv&&(pv.r||{})[nm]||[];
  #| var sp=swapPair(fr,nm,els.length);
  #| var max=1;for(var q=0;q<els.length;q++){var fv=parseFloat(els[q]);if(isFinite(fv)&&Math.abs(fv)>max)max=Math.abs(fv)}
  #| var dm=arrDims(fr,nm);var cols=dm?dm[1]:els.length;var alabel=dm?(dm[0]+'\u00d7'+dm[1]+' \u77e9\u9635'):(els.length+' \u5143\u7d20');
  #| h+='<div class="arr"><div class="arr-h">'+esc(nm)+'<span class="ver"> \u00b7 '+alabel+'</span></div><div class="cells" style="--n:'+cols+';--cw:64px">';
  #| for(var i2=0;i2<els.length;i2++){var cls2="cell";var sp2=sp&&(i2===sp.i||i2===sp.j);
  #| if(sp2)cls2+=" swap"; else if(pels.length&&pels[i2]!==els[i2])cls2+=" changed";
  #| var v=parseFloat(els[i2]);var ratio=isFinite(v)?Math.max(.06,Math.abs(v)/max):.3;
  #| h+='<div class="'+cls2+'" style="--v:'+ratio.toFixed(2)+'"><span class="idx">'+(dm?(Math.floor(i2/cols)+','+i2%cols):i2)+'</span>'+esc(els[i2])+'<span class="bar"></span></div>'}
  #| h+="</div>";
  #| h+='<div class="ptrs" style="--n:'+cols+';--cw:64px">';
  #| for(var i3=0;i3<els.length;i3++){var p2="";for(var vi=0;vi<fr.v.length;vi++){var va=fr.v[vi];var num=parseInt(va[2]);
  #| if(isFinite(num)&&num===i3&&/^int$/.test(va[1]))p2+=(p2?" ":"")+"\u25be"+va[0]+"="+va[2]}
  #| h+='<div class="ptr">'+p2+'</div>'}
  #| h+="</div></div>"}
  #| if(D.run&&D.run.status){h+='<div class="ver" style="margin-top:4px">run: '+esc(D.run.status)+' \u00b7 \u8fd4\u56de\u503c '+D.run.return_value+' \u00b7 \u5f15\u64ce\u6b65\u6570 '+D.run.steps_executed+'</div>'}
  #| $("stage").innerHTML=h;
  #| var vh="";for(var x=0;x<fr.v.length;x++){var ch2=pv&&pv.v[x]&&pv.v[x][2]!==fr.v[x][2];
  #| vh+="<tr><td>"+esc(fr.v[x][0])+"</td><td class='ver'>"+esc(fr.v[x][1])+"</td><td class='vv"+(ch2?" changed":"")+"'>"+esc(fr.v[x][2])+"</td></tr>"}
  #| $("vars").innerHTML=vh||"<div class='ver' style='padding:8px'>\uff08\u6b64\u5e27\u65e0\u5c40\u90e8\u53d8\u91cf\uff09</div>";
  #| var sh="";for(var y=fr.c.length-1;y>=0;y--)sh+='<div class="fr2'+(y===fr.c.length-1?" top":"")+'">'+esc(fr.c[y])+"</div>";
  #| $("stack").innerHTML=sh;
  #| if(D.outputs&&D.outputs.stdout)$("stdout").textContent=D.outputs.stdout;
  #| var cap=fr.s||"";if(fr.a&&fr.a.d)cap+=' <span class="as">\u2014 '+esc(fr.a.d)+"</span>";
  #| if(fr.h)cap+=' <span class="as" style="color:var(--err)">\u26a0 '+esc(fr.h.o)+"</span>";
  #| $("cap").innerHTML=cap;
  #| var t=fr.s+(fr.a?" "+fr.a.d:"");
  #| if(S.speakOn&&t&&t!==S.lastCap&&window.speechSynthesis){speechSynthesis.cancel();var u=new SpeechSynthesisUtterance(t);u.lang="zh-CN";speechSynthesis.speak(u)}
  #| S.lastCap=t;
  #| $("slider").max=Math.max(0,S.frames.length-1);$("slider").value=k;
  #| $("fnum").textContent=(k+1)+" / "+S.frames.length+(D.thinned?"\uff08\u62bd\u7a00\u81ea "+D.rawCount+" \u6b65\uff09":"");
  #| if(k>=S.frames.length-1)stopPlay()}
  #| function stepTo(k){S.cur=Math.max(0,Math.min(S.frames.length-1,k));renderFrame()}
  #| function stopPlay(){S.playing=false;$("btnPlay").textContent="\u25b6 \u64ad\u653e";if(S.timer){clearInterval(S.timer);S.timer=null}}
  #| function togglePlay(){if(S.playing){stopPlay();return}if(S.cur>=S.frames.length-1&&!window.__VITRO_STEP__)S.cur=0;S.playing=true;$("btnPlay").textContent="\u23f8 \u6682\u505c";S.timer=setInterval(function(){if(S.cur>=S.frames.length-1&&window.__VITRO_STEP__){if(window.__VITRO_DONE__){stopPlay();return}window.__VITRO_STEP__(200)}stepTo(S.cur+1)},S.speed)}
  #| function showDiagnostics(){var h='<div id="diag">';
  #| for(var i=0;i<D.diagnostics.length;i++){var d=D.diagnostics[i];
  #| h+='<div class="dcard'+(/warn/i.test(d.severity||"")?" warn":"")+'" style="animation-delay:'+(i*220)+'ms"><div class="dcode">'+esc(d.code||"")+" \u00b7 "+esc(d.severity||"error")+'</div><div class="dloc">'+esc(d.filename||"main.c")+":"+d.line+":"+d.column+'</div><div>'+esc(d.message)+"</div>"+(d.fix_suggestion?'<div class="dfix">\ud83d\udca1 '+esc(d.fix_suggestion)+"</div>":"")+"</div>"}
  #| h+="</div>";$("stage").innerHTML=h;$("cap").innerHTML='<span style="color:var(--err)">\u7f16\u8bd1\u5931\u8d25\uff1a'+D.diagnostics.length+' \u6761\u8bca\u65ad\uff08\u89c1\u5361\u7247\uff09</span>';
  #| $("slider").disabled=true;$("btnPlay").disabled=true;$("btnPrev").disabled=true;$("btnNext").disabled=true}
  #| function init(){renderCode();
  #| if(D.diagnostics&&D.diagnostics.length&&!D.frames.length){showDiagnostics();return}
  #| $("btnPlay").onclick=togglePlay;$("btnPrev").onclick=function(){stopPlay();stepTo(S.cur-1)};$("btnNext").onclick=function(){stopPlay();stepTo(S.cur+1)};
  #| $("slider").oninput=function(){stopPlay();stepTo(+this.value)};
  #| $("speed").onchange=function(){S.speed=+this.value;if(S.playing){stopPlay();togglePlay()}};
  #| $("theme").onclick=function(){var r=document.documentElement;r.dataset.theme=r.dataset.theme==="dark"?"light":"dark"};
  #| var spk=$("speak");if(spk&&window.speechSynthesis){spk.onclick=function(){S.speakOn=!S.speakOn;spk.textContent=S.speakOn?"\ud83d\udd0a \u6717\u8bfb:\u5f00":"\ud83d\udd07 \u6717\u8bfb:\u5173";if(!S.speakOn)speechSynthesis.cancel()}}
  #| document.onkeydown=function(e){if(e.target.tagName==="INPUT"&&e.target.type==="number")return;
  #| if(e.key===" "){e.preventDefault();togglePlay()}else if(e.key==="ArrowLeft"){stopPlay();stepTo(S.cur-1)}else if(e.key==="ArrowRight"){stopPlay();stepTo(S.cur+1)}else if(e.key==="Home"){stopPlay();stepTo(0)}else if(e.key==="End"){stopPlay();stepTo(S.frames.length-1)}};
  #| if(D.mode==="interactive"){bootInteractive()}else if(S.frames.length){renderFrame();
  #| if(/#play/.test(location.hash)){setTimeout(togglePlay,300)}}}
  #| `;
  #| const INTERACTIVE = `
  #| var E=null,fid=0,running=false,cap=20000,rawCount=0,prevCmp=null;
  #| function inv(method,params){fid++;var r=JSON.parse(E.invoke(JSON.stringify({id:fid,method:method,params:params||{}})));
  #| if(!r.ok)throw new Error(String(r.error||"protocol error"));return r.result}
  #| function bootEngine(bin){return WebAssembly.compile(bin,{builtins:["js-string"],importedStringConstants:"_"}).then(function(mod){return WebAssembly.instantiate(mod,{})}).then(function(inst){E=inst.exports})}
  #| function pullOutputs(){var out={stdout:"",stderr:""};["stdout","stderr"].forEach(function(stream){var cursor=0;
  #| for(;;){var o=inv("output.delta",{cursor:cursor,stream:stream});out[stream]+=stream==="stdout"?l12u(o.delta):o.delta;
  #| if(o.cursor>=o.total||!o.delta)break;cursor=o.cursor}});D.outputs=out;
  #| if(out.stdout)$("stdout").textContent=out.stdout}
  #| function l12u(s){return new TextDecoder().decode(Uint8Array.from(s,function(c){return c.charCodeAt(0)&255}))}
  #| function absorb(batch){rawCount+=batch.payloads?batch.payloads.length:0;
  #| if(batch.payloads)for(var i=0;i<batch.payloads.length;i++){var c=compactFrame(batch.payloads[i],null);
  #| var w=keyWeight(prevCmp,c,false);if(w>0){S.frames.push(c);prevCmp=c}}
  #| if(batch.waiting_input)return"waiting_input";if(batch.paused)return"paused";
  #| if(batch.trapped)return"trapped:"+String(batch.trap_message||"");if(batch.finished)return"finished";return""}
  #| function stepOnce(n){var stops="";
  #| try{for(var k=0;k<(n||800);k++){var b=inv("step.next",{});stops=absorb(b);if(stops)break;
  #| if(prevCmp&&S.frames.length&&rawCount>0&&k>3&&S.frames.length>__LASTN__)break}}catch(e){stops="error:"+e.message}
  #| __LASTN__=S.frames.length;
  #| D.rawCount=rawCount;if(S.frames.length&&!stops)renderFrame();else if(S.frames.length){stopPlay();stepTo(S.frames.length-1)}
  #| if(stops&&stops!=="finished")$("cap").innerHTML='<span style="color:var(--swap)">\u23f9 '+esc(stops)+"</span>";
  #| if(stops==="finished"||stops.indexOf("trapped")===0){window.__VITRO_DONE__=true;try{pullOutputs()}catch(e){}$("btnRunAll").disabled=true;$("btnStep").disabled=true}
  #| return stops}
  #| window.__VITRO_STEP__=function(n){return stepOnce(n||200)};
  #| function bootInteractive(){var bin=Uint8Array.from(atob(D.wasmB64),function(c){return c.charCodeAt(0)});
  #| $("cap").innerHTML='<span class="as">wasm \u5f15\u64ce\u88c5\u8f7d\u4e2d\uff08'+Math.round(bin.length/1024)+'KB\uff09\u2026</span>';
  #| bootEngine(bin).then(function(){
  #| inv("session.create");inv("config.set",{deterministic:true,max_steps:10000000,call_depth_limit:10000,quarantine_budget:262144});
  #| var comp=inv("compile",{source:D.source});
  #| if(!comp.ok){D.diagnostics=comp.diagnostics||[];showDiagnostics();return}
  #| if(comp.algorithm_matches&&comp.algorithm_matches.length){D.algo=comp.algorithm_matches[0]}
  #| var run=inv("run");D.run={status:run.status,return_value:run.return_value,steps_executed:run.steps_executed};
  #| inv("step.begin");
  #| $("bpBox").classList.add("on");
  #| $("btnStep").onclick=function(){stepOnce(1)};
  #| $("btnRunAll").onclick=function(){if(running)return;running=true;$("btnRunAll").textContent="\u2026\u8fd0\u884c\u4e2d";var t0=Date.now();var tick=function(){var stops=stepOnce(1e9);if(S.frames.length)stepTo(S.frames.length-1);if(!stops&&Date.now()-t0<20000){setTimeout(tick,0);return}running=false;$("btnRunAll").textContent="\u25b6 \u8fd0\u884c\u5230\u5e95";if(stops==="finished"||stops.indexOf("trapped")===0){$("btnRunAll").disabled=true}};tick()};
  #| $("btnBp").onclick=function(){var ln=+$("bpLine").value;if(!ln)return;
  #| var last=S.frames.length;try{inv("breakpoints.set",{lines:[ln]})}catch(e){}
  #| stepOnce(1e9);inv("breakpoints.set",{lines:[]});S.cur=last;stepTo(Math.min(last,S.frames.length-1))};
  #| renderFrame();
  #| var guard=0,hasArr=function(){var f=S.frames[S.frames.length-1];return !!f&&Object.keys(f.r||{}).length>0};
  #| var stops0="";
  #| while(guard++<40&&S.frames.length<16&&!stops0){stops0=stepOnce(400)}
  #| stepTo(S.frames.length-1);
  #| $("btnStep").disabled=false;$("btnRunAll").disabled=false;$("btnBp").disabled=false}).catch(function(e){$("cap").innerHTML='<span style="color:var(--err)">\u5f15\u64ce\u88c5\u8f7d\u5931\u8d25\uff1a'+esc(e.message)+"</span>"})}
  #| `;
  #| function arrEq(a, b) {
  #| if (a === b) return true;
  #| if (!a || !b) return false;
  #| const ka = Object.keys(a), kb = Object.keys(b);
  #| if (ka.length !== kb.length) return false;
  #| for (const k of ka) {
  #| const x = a[k], y = b[k];
  #| if (!y || x.length !== y.length) return false;
  #| for (let i = 0; i < x.length; i++) if (x[i] !== y[i]) return false;
  #| }
  #| return true;
  #| }
  #| function compactFrame(p, focusSet) {
  #| const r = {};
  #| for (const a of p.array_snapshots ?? []) if (!focusSet || focusSet.has(a.name)) r[a.name] = a.elements;
  #| return {
  #| i: p.step_index,
  #| l: p.code_line,
  #| f: p.func_name,
  #| s: p.semantic_label ?? "",
  #| a: p.algorithm_step ? { p: p.algorithm_step.phase, d: p.algorithm_step.description } : null,
  #| v: (p.local_vars ?? []).map((x) => [x.name, x.ty_name, x.value]),
  #| c: (p.call_stack ?? []).map((x) => x.func_name),
  #| e: (p.vis_events ?? []).map((x) => [x.ty, x.line, x.extra0, x.extra1, x.extra2, x.context]),
  #| r,
  #| h: p.root_cause_hint ? { c: p.root_cause_hint.category, o: p.root_cause_hint.one_liner, ls: p.root_cause_hint.related_lines, fx: p.root_cause_hint.suggested_fix_desc } : null,
  #| };
  #| }
  #| function keyWeight(prev, c, isEdge) {
  #| let weight = 0;
  #| if (prev === null || isEdge) weight = 3;
  #| if (c.e.length > 0) weight = Math.max(weight, 3);
  #| if (prev !== null && !arrEq(c.r, prev.r)) weight = Math.max(weight, 3);
  #| if (prev !== null && c.c.length !== prev.c.length) weight = Math.max(weight, 2);
  #| if (c.h !== null) weight = Math.max(weight, 3);
  #| if (/^\u4ea4\u6362|^swap/i.test(c.s)) weight = Math.max(weight, 2);
  #| if (prev !== null && c.l !== prev.l && c.l > 0) weight = Math.max(weight, 1);
  #| return weight;
  #| }
  #| const EMBED_SRC = [arrEq, compactFrame, keyWeight].map((f) => f.toString()).join("\n");
  #| function renderHtml(o) {
  #| const { mode, title, source, frames = [], theme = "auto", audio = false, wasmB64 = null } = o;
  #| const focus = o.focus ?? [];
  #| const algoBadge = o.algo
  #| ? `<span class="badge">\u2726 ${esc(o.algo.display_name || o.algo.name)} \u00b7 \u7f6e\u4fe1\u5ea6 ${esc(String(o.algo.confidence ?? ""))}</span>`
  #| : `<span class="badge gray">\u672a\u8bc6\u522b\u7b97\u6cd5</span>`;
  #| const audioBtn = audio ? `<button id="speak" class="hdrbtn" style="display:none">\ud83d\udd07 \u6717\u8bfb:\u5173</button>` : "";
  #| const interactiveExtra = mode === "interactive" ? `<button id="btnStep" class="hdrbtn" disabled>\u5355\u6b65 \u25b6|</button><button id="btnRunAll" class="hdrbtn" disabled>\u25b6 \u8fd0\u884c\u5230\u5e95</button><span id="bpBox"><input type="number" id="bpLine" placeholder="\u884c\u53f7" min="1" style="width:64px"><button id="btnBp" class="hdrbtn" disabled>\u23f1 \u5230\u65ad\u70b9</button></span>` : "";
  #| const data = {
  #| mode, source, frames, focus, algo: o.algo ?? null, run: o.run ?? null, outputs: o.outputs ?? { stdout: "", stderr: "" },
  #| diagnostics: o.compileOk ? (o.warnings || []) : (o.diagnostics || []), thinned: o.thinned ?? false, rawCount: o.rawCount ?? frames.length,
  #| errLines: (o.diagnostics || []).filter((d) => String(d.severity ?? "error").toLowerCase() !== "hint").map((d) => d.line),
  #| wasmB64: o.wasmB64 ?? null,
  #| };
  #| return `<!doctype html>
  #| <html lang="zh-CN" data-theme="${theme === "auto" ? "dark" : theme}">
  #| <head>
  #| <meta charset="utf-8">
  #| <meta name="viewport" content="width=device-width,initial-scale=1">
  #| <title>${esc(title)}</title>
  #| <style>${CSS}</style>
  #| </head>
  #| <body>
  #| <header>
  #| <h1>${esc(title)}</h1>
  #| ${algoBadge}
  #| <span class="ver">vitro ${esc(o.versions?.engine ?? "")} \u00b7 \u534f\u8bae ${esc(o.versions?.protocol ?? "")} \u00b7 ${mode === "interactive" ? "\u4ea4\u4e92\u6a21\u5f0f\uff08\u9875\u5185\u5f15\u64ce\uff09" : "\u9884\u8ba1\u7b97\u6a21\u5f0f"}</span>
  #| ${audioBtn}
  #| <button id="theme" class="hdrbtn">\u25d0 \u4e3b\u9898</button>
  #| </header>
  #| <main>
  #| <section><div class="sec-t">\u6e90\u7801 \u00b7 \u5f53\u524d\u884c</div><div id="codeWrap"></div></section>
  #| <section style="overflow:auto"><div class="sec-t">\u52a8\u753b\u821e\u53f0${focus.length ? " \u00b7 \u805a\u7126 " + esc(focus.join(", ")) : ""}</div><div id="stage"><div class="ver" style="padding:20px">${mode === "interactive" ? "\u5f15\u64ce\u521d\u59cb\u5316\u4e2d\u2026" : "\u65e0\u5e27"}</div></div></section>
  #| <aside>
  #| <div class="pane"><div class="sec-t">\u5c40\u90e8\u53d8\u91cf</div><div id="vars"></div></div>
  #| <div class="pane" style="flex:none;max-height:38%"><div class="sec-t">\u8c03\u7528\u6808</div><div id="stack"></div><div id="stdout"></div></div>
  #| </aside>
  #| </main>
  #| <footer>
  #| <div id="cap" aria-live="polite"></div>
  #| <div class="bar-row">
  #| <button id="btnPrev" title="\u4e0a\u4e00\u5e27\uff08\u2190\uff09">\u25c0|</button>
  #| <button id="btnPlay" title="\u64ad\u653e/\u6682\u505c\uff08\u7a7a\u683c\uff09">\u25b6 \u64ad\u653e</button>
  #| <button id="btnNext" title="\u4e0b\u4e00\u5e27\uff08\u2192\uff09">|\u25b6</button>
  #| ${interactiveExtra}
  #| <input type="range" id="slider" min="0" max="0" value="0" step="1">
  #| <span id="fnum"></span>
  #| <select id="speed" title="\u6b65\u8fdb\u95f4\u9694"><option value="400">0.4s/\u5e27</option><option value="200" selected>0.2s/\u5e27</option><option value="80">0.08s/\u5e27</option><option value="30">0.03s/\u5e27</option></select>
  #| </div>
  #| </footer>
  #| <script>
  #| ${theme === "auto" ? "if(matchMedia('(prefers-color-scheme: light)').matches)document.documentElement.dataset.theme='light';\n" : ""}window.__VITRO__=${jstr(data)};
  #| ${PLAYER}
  #| ${mode === "interactive" ? EMBED_SRC + "\nvar __LASTN__=0;\n" + INTERACTIVE : ""}
  #| init();
  #| </script>
  #| </body>
  #| </html>`;
  #| }
  #| try {
  #| let mode = o.mode === "interactive" ? "interactive" : "static";
  #| const warnings = [];
  #| let wasmB64 = null;
  #| if (mode === "interactive") {
  #| const wp = resolveWasm();
  #| if (wp) wasmB64 = fs.readFileSync(wp).toString("base64");
  #| else { warnings.push("interactive \u9700\u8981 gateway wasm.wasm\uff08VITRO_MCP_WASM / ./engine/wasm.wasm / ./wasm.wasm \u5747\u672a\u627e\u5230\uff09\u2014\u2014\u5df2\u56de\u843d static \u6a21\u5f0f"); mode = "static"; }
  #| }
  #| const ro = {
  #| mode, title: o.title ?? "", source: o.source ?? "",
  #| frames: mode === "interactive" ? [] : (o.frames ?? []),
  #| focus: o.focus ?? [], algo: o.algo ?? null, run: o.run ?? null,
  #| outputs: o.outputs ?? { stdout: "", stderr: "" },
  #| diagnostics: o.diagnostics ?? [], compileOk: !!o.compile_ok,
  #| warnings: o.warnings ?? [], theme: o.theme ?? "auto", audio: !!o.audio,
  #| thinned: !!o.thinned, rawCount: o.raw_count ?? 0,
  #| versions: o.versions ?? {}, wasmB64,
  #| };
  #| const html = renderHtml(ro);
  #| const outDir = o.out_dir && String(o.out_dir).length > 0 ? String(o.out_dir) : path.join(process.cwd(), "vitro-out");
  #| fs.mkdirSync(outDir, { recursive: true });
  #| // #517 P2-11：秒级时间戳 + pid/随机后缀——修前分钟粒度 + program_ slug
  #| // 同分钟互吃（A/B 覆盖链 6 轮：多实例共享 vitro-out 时 png/html 互覆，
  #| // preview_png 渲染出他人页面）；唯一化后并发实例各产各物。
  #| const ts = new Date().toISOString().replace(/[:T]/g, "-").slice(0, 19);
  #| const uniq = process.pid.toString(36) + "-" + Math.random().toString(36).slice(2, 6);
  #| const slug = String(o.slug ?? "program").replace(/[^\w-]/g, "_").slice(0, 40);
  #| const file = path.join(outDir, slug + "_" + ts + "_" + uniq + "_" + mode + ".html");
  #| fs.writeFileSync(file, html, "utf8");
  #| const size = fs.statSync(file).size;
  #| let pngPath = null, pngB64 = null;
  #| if (o.preview_png && mode === "static" && ro.compileOk && ro.frames.length > 0) {
  #| const exe = findBrowser();
  #| if (exe) {
  #| const p = file.replace(/\.html$/, "") + ".png";
  #| const s = shotPng(exe, "file:///" + file.replace(/\\/g, "/") + "#play", p, 4200);
  #| if (s.ok) { pngPath = p; pngB64 = fs.readFileSync(p).toString("base64"); }
  #| else warnings.push("PNG \u9884\u89c8\u5931\u8d25\uff08" + s.err + "\uff09\u2014\u2014\u52a8\u753b\u672c\u4f53\u4e0d\u53d7\u5f71\u54cd");
  #| } else warnings.push("\u672a\u627e\u5230 Edge/Chrome\uff0c\u8df3\u8fc7 PNG \u9884\u89c8");
  #| }
  #| return JSON.stringify({ ok: true, html_path: file, size_bytes: size, frame_count: ro.frames.length, mode_used: mode, warnings, preview_png_path: pngPath, preview_png_b64: pngB64 });
  #| } catch (e) {
  #| return JSON.stringify({ ok: false, error: String(e && e.message ? e.message : e) });
  #| }
  #| }
