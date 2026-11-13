// 一次性 rebase 冲突解：moonbit/README{,.mbt}.md 的 75c4980c 冲突块
// ——theirs（本地批注链）为主体，js 句补 master 独有的 REHOST 1c 段；
// 数字留 theirs 中间态（终值由最后提交实测刷）。
import { readFileSync, writeFileSync } from 'node:fs';

const C1C = '；2026-11-13 REHOST 批 1c +4 裸域（bytecode wasm_project 投影锚 4——triples 保序/EmitCtx 装配/装载核对双通道边界/Reserved 拒载定位，js/native 双域）';

function strip(s) {
  for (;;) {
    const a = s.indexOf('<<<<<<< HEAD\n');
    if (a < 0) break;
    const b = s.indexOf('\n=======\n', a);
    const c = s.indexOf('\n>>>>>>> ', b);
    const d = s.indexOf('\n', c + 1);
    if (b < 0 || c < 0 || d < 0) throw new Error('标记结构异常');
    s = s.slice(0, a) + s.slice(b + '\n=======\n'.length, c) + s.slice(d + 1);
  }
  return s;
}

for (const p of ['moonbit/README.md', 'moonbit/README.mbt.md']) {
  let s = strip(readFileSync(p, 'utf8'));
  // js 句插 1c 段：锚 = #486 处置段尾（两文件 theirs 均含）
  const anchor = 'strtod 零尾数/hex 零尾数上溢两锚）';
  const i = s.indexOf(anchor);
  if (i < 0) throw new Error(`${p}: #486 锚未找到`);
  if (s.indexOf(anchor, i + 1) >= 0) throw new Error(`${p}: #486 锚不唯一`);
  if (!s.includes('REHOST 批 1c')) {
    s = s.slice(0, i + anchor.length) + C1C + s.slice(i + anchor.length);
  }
  if (/^<{7}|^={7}$|^>{7}/m.test(s)) throw new Error(`${p}: 仍残留标记`);
  writeFileSync(p, s);
  console.log('OK', p);
}
