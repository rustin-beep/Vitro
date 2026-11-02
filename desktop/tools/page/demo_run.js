// desktop/tools/page/demo_run.js —— 页内表达式（经 cdp_probe @file 注入）：
// 驱动 demo UI 完整采集——点「运行」→ 轮询采集完成 → 读 {状态行, stdout, 帧数, 版本}。
// 期望（2026-11-02 实测基线）：status 含 "编译 ✓ 运行 ✓ golden ✓"、
// stdout="1 2 3 4 5 \n"、42 帧、transport=ipc、引擎 0.9.1。
(async () => {
  const run = [...document.querySelectorAll('button')].find(b => b.textContent.trim() === '运行');
  if (!run) return JSON.stringify({ error: '运行按钮未找到' });
  run.click();
  let status = '';
  for (let k = 0; k < 150; k++) {
    await new Promise(r => setTimeout(r, 200));
    status = [...document.querySelectorAll('[class*=status],[class*=pill]')].map(e => e.textContent.trim()).join('|');
    if (!status.includes('采集中') && !status.includes('运行 …')) break;
  }
  const pres = [...document.querySelectorAll('pre,code')].map(e => e.textContent).filter(t => t && t.length > 10);
  return JSON.stringify({
    transport: window.__MoonBit__ ? 'ipc' : 'worker',
    status: status.slice(0, 200),
    stdout: (pres.find(s => /^\d/.test(s)) || '').slice(0, 100),
    frames: (document.body.textContent.match(/(\d+)\s*帧/) || ['', '?'])[1],
    ver: (document.body.textContent.match(/引擎 [\d.]+ 协议 [\w.]+/) || [''])[0],
  });
})()
