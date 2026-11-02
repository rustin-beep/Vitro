// desktop/tools/page/demo_run.js —— 页内表达式（经 cdp_probe @file 注入）：
// 驱动 demo UI 完整采集——等「运行」就绪→点→等采集完成→**点「末帧」**→等
// golden 判定→读 {状态行, stdout, 帧数, 版本}。
// 为何主动跳末帧：golden 判定在末帧；幕播放器会在幕边界暂停（本地实锤
// 「已暂停 · 第 22/42 帧」）——靠自动播放到底是 flaky，探针须驱动到末帧。
// 期望（2026-11-02 基线）：status 含 "golden ✓"、stdout="1 2 3 4 5 \n"、42 帧、
// transport=ipc、引擎 0.9.1。
(async () => {
  const sleep = (ms) => new Promise(r => setTimeout(r, ms));
  const btn = (label) => [...document.querySelectorAll('button')]
    .find(b => (b.getAttribute('aria-label') || b.title || b.textContent.trim()) === label
      || b.textContent.trim() === label);
  const statusLine = () => [...document.querySelectorAll('[class*=status],[class*=pill]')]
    .map(e => e.textContent.trim()).join('|');
  // ① 「运行」就绪（smoke 场景探针可能早于 UI 挂载）
  let run = null;
  for (let k = 0; k < 60 && !run; k++) {
    run = btn('运行') || btn('从头采集帧流（编译 + run + step 闭环）');
    if (!run) await sleep(500);
  }
  if (!run) return JSON.stringify({ error: '运行按钮未找到' });
  run.click();
  // ② 等采集完成（编译 ✓ 运行 ✓ 出现，或失败态）
  let status = '';
  for (let k = 0; k < 150; k++) {
    await sleep(200);
    status = statusLine();
    if (/运行 ✓|编译 ✗|受检终止|采集失败/.test(status)) break;
  }
  // ③ 驱动到末帧（循环而非单击：帧流到达后播放器自动从头播并在幕边界
  //    暂停——单次点「末帧」与自动播放竞态，CI runner 实锤停在 22/42）。
  //    每轮：暂停（若在播放）→ 点「末帧」→ 滑条拉满兜底 → 等 → 读状态，
  //    直到 golden 落定且不再「待末帧」。
  let seekMax = '?', seekVal = '?';
  for (let k = 0; k < 25; k++) {
    const pause = btn('暂停（空格）');
    if (pause) pause.click();
    const last = btn('末帧');
    if (last) last.click();
    const seek = document.querySelector('input.vr-seek, input[type=range]');
    if (seek) {
      seekMax = seek.max; seekVal = seek.value;
      if (seek.value !== seek.max) {
        seek.value = seek.max;
        seek.dispatchEvent(new Event('input', { bubbles: true }));
        seek.dispatchEvent(new Event('change', { bubbles: true }));
      }
    }
    await sleep(400);
    status = statusLine();
    if (/golden [✓✗]/.test(status) && !status.includes('golden 待末帧')) break;
  }
  const pres = [...document.querySelectorAll('pre,code')].map(e => e.textContent).filter(t => t && t.length > 10);
  return JSON.stringify({
    // 实际选定的通道（engine.ipc.ts markKind 写入——与「桥存在」解耦，
    // 审阅 P1-2：旧取值式对真走哪臂零判别力）；__vitroTransport 缺席
    // （旧页缓存/极端时序）才退回桥存在性
    transport: window.__vitroTransport || (window.__MoonBit__ ? 'ipc' : 'worker'),
    status: status.slice(0, 200),
    stdout: (pres.find(s => /^\d/.test(s)) || '').slice(0, 100),
    frames: (document.body.textContent.match(/(\d+)\s*帧/) || ['', '?'])[1],
    ver: (document.body.textContent.match(/引擎 [\d.]+ 协议 [\w.]+/) || [''])[0],
    seek: `${seekVal}/${seekMax}`,
  });
})()
