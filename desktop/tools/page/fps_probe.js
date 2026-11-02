// desktop/tools/page/fps_probe.js —— 页内表达式（经 cdp_probe @file 注入
// Runtime.evaluate，跑在 CEF 渲染进程，非 node 脚本——不进 tsconfig 面）。
// 注入 CSS transform 动画 + rAF 计数 2 秒 ⇒ {frames_in_2s, fps, min/max_frame_ms, visibility}。
// 口径：窗口须可见（隐藏窗被合成器节流）。P 线实测 160.5fps（高刷屏满速）。
(async () => {
  const el = document.createElement('div');
  el.style.cssText = 'position:fixed;left:0;top:40%;width:120px;height:60px;background:#0f766e;color:#fff;display:flex;align-items:center;justify-content:center;z-index:9999;will-change:transform;';
  el.textContent = 'FPS probe';
  document.body.appendChild(el);
  const style = document.createElement('style');
  style.textContent = '@keyframes probeSlide { from { transform: translateX(0); } to { transform: translateX(600px); } }';
  document.head.appendChild(style);
  el.style.animation = 'probeSlide 2s linear';
  let frames = 0;
  let minDelta = 1e9, maxDelta = 0;
  let last = performance.now();
  const t0 = last;
  const tick = () => {
    const now = performance.now();
    const d = now - last;
    if (d > 0) { if (d < minDelta) minDelta = d; if (d > maxDelta) maxDelta = d; }
    last = now;
    frames++;
    if (now - t0 < 2000) requestAnimationFrame(tick);
  };
  await new Promise(r => requestAnimationFrame(() => { requestAnimationFrame(tick); r(); }));
  await new Promise(r => setTimeout(r, 2100));
  el.remove(); style.remove();
  return JSON.stringify({ frames_in_2s: frames, fps: (frames / 2).toFixed(1), min_frame_ms: +minDelta.toFixed(2), max_frame_ms: +maxDelta.toFixed(2), visibility: document.visibilityState });
})()
