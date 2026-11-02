// desktop/tools/page/demo_matrix.js —— 页内表达式（经 cdp_probe @file 注入）：
// 命令层矩阵端到端（PR #417 审阅 P2-3）——直接 invokeOp 四命令（零编辑器
// DOM 依赖：demo 编辑器是 CodeMirror，textarea 注入不可行；命令层四分支
// 正是零覆盖对象）：① versions ② invoke 透传（config.get）③ collect argv
// 透传（arg=alpha/beta；引擎契约=数组含 argv[0]，故首元素给程序名）④
// collect→waiting_input→feed 续跑（got 42）⑤ collect 断点停采（bp_lines ⇒
// paused）。返回逐项 {pass, detail}。
//
// ⚠ 已知引擎缺陷（登记 #451，两臂同命中）：input.feed 的 stdin 残留跨
// step.begin 且跨 session.create（其头注声称 runtime 域全清）——同会话内
// feed 过一次后，再 collect 同款 scanf 程序不再等待、直接消费旧文本。
// smoke 每次全新 app 进程跑一轮矩阵（feed 案即干净 stdin），单轮内自洽。
(async () => {
  const invokeOp = window.__MoonBit__.core.invokeOp;
  const R = {};
  const J = (v) => JSON.stringify(v);

  // ① versions
  try {
    const v = await invokeOp('app:vitro_versions', {});
    R.versions = { pass: typeof v.engine === 'string' && typeof v.protocol === 'string', detail: J(v) };
  } catch (e) { R.versions = { pass: false, detail: String(e) }; }

  // ② invoke 透传（config.get——网关单口原样转发）
  try {
    const r = await invokeOp('app:vitro_invoke', { api: 'config.get', params: {} });
    R.invoke = { pass: r.ok === true && 'result' in r, detail: (r.result && J(r.result).slice(0, 60)) || J(r).slice(0, 80) };
  } catch (e) { R.invoke = { pass: false, detail: String(e) }; }

  // ③ collect argv 透传——引擎契约：数组即完整 argv（含 argv[0]，
  //    serve_run.mbt:98 argc=runtime_argv.length()；CLI/demo 同口径），
  //    故 argv[0] 显式给程序名
  const argvSrc = '#include <stdio.h>\nint main(int argc, char **argv) {\n  for (int i = 1; i < argc; i++) printf("arg=%s\\n", argv[i]);\n  return 0;\n}';
  try {
    const c = await invokeOp('app:vitro_collect', { source: argvSrc, cap: 20000, bp_lines: [], cfg: {}, argv: ['probe', 'alpha', 'beta'] });
    R.argv = { pass: c.compileOk === true && (c.outputs.stdout || '').includes('arg=alpha') && (c.outputs.stdout || '').includes('arg=beta'), detail: `${c.run && c.run.status}/${(c.outputs.stdout || '').trim().slice(0, 40)}` };
  } catch (e) { R.argv = { pass: false, detail: String(e) }; }

  // ④ feed：scanf ⇒ waiting_input ⇒ 喂 42 ⇒ 续采完成
  try {
    const scanfSrc = '#include <stdio.h>\nint main(void) {\n  int x;\n  if (scanf("%d", &x) != 1) { printf("read fail\\n"); return 1; }\n  printf("got %d\\n", x);\n  return 0;\n}';
    const c1 = await invokeOp('app:vitro_collect', { source: scanfSrc, cap: 20000, bp_lines: [], cfg: {}, argv: [] });
    const waiting = c1.run && c1.run.waiting_input === true;
    const f = await invokeOp('app:vitro_feed', { text: '42', cap: 20000 });
    R.feed = {
      pass: waiting === true && (f.outputs.stdout || '').includes('got 42') && f.run && f.run.waiting_input !== true,
      detail: `wait=${waiting}/after=${f.run && f.run.status}/${(f.outputs.stdout || '').trim().slice(0, 40)}`,
    };
  } catch (e) { R.feed = { pass: false, detail: String(e) }; }

  // ⑤ 断点停采：bp_lines 指向循环体 ⇒ paused
  const bpSrc = '#include <stdio.h>\nint main(void) {\n  int s = 0;\n  for (int i = 1; i <= 9; i++) s += i;\n  printf("sum=%d\\n", s);\n  return 0;\n}';
  try {
    const c = await invokeOp('app:vitro_collect', { source: bpSrc, cap: 20000, bp_lines: [4], cfg: {}, argv: [] });
    R.breakpoint = { pass: (c.stopped || '').includes('断点'), detail: (c.stopped || '').slice(0, 60) };
  } catch (e) { R.breakpoint = { pass: false, detail: String(e) }; }

  return JSON.stringify(R);
})()
