// conv_specs.test.mts —— 抽取器纯函数 + C11 全集 + 真实仓库判定 + J9 内存注入红路
import { test } from "node:test";
import assert from "node:assert/strict";
import path from "node:path";
import { spawnSync } from "node:child_process";
import {
  C11_PRINTF,
  C11_SCANF,
  extractLetters,
  loadRules,
  sliceByAnchors,
  stripLineComments,
  allFaces,
  verdict,
} from "./main.mts";
import { projectRoot } from "../../internal/capi.mts";

const MAIN = path.join(import.meta.dirname, "main.mts");

test("stripLineComments：剥 // 之后；保留字符串内与行首 // 之前内容", () => {
  assert.equal(stripLineComments("let a = 1 // 'x' 'y' 注释臂不算\n"), "let a = 1 \n");
  assert.equal(stripLineComments("// 'd' | 'i' 全注释\nnext"), "\nnext");
  // 边界（如实记录）：字符串字面量内的 // 也会被剥——本仓四消费面的判据臂
  // 均无含 // 的字符串字面量（warning 文案走 \{} 插值），不为此做字符串感知解析
  assert.equal(stripLineComments("let s = \"a//b\""), "let s = \"a");
});

test("sliceByAnchors：anchor_end 命中 / 缺锚 / 下一顶层 fn 收尾", () => {
  const spec = { file: "f", anchor_start: "fn target(", anchor_end: "", kind: "match_char_arms" };
  assert.equal(sliceByAnchors("fn target()\n  'a'\nfn next()\n  'b'\n", spec).body, ")\n  'a'\n");
  assert.match(sliceByAnchors("no anchor", spec).error ?? "", /anchor_start 未命中/);
  const spec2 = { file: "f", anchor_start: "BEGIN", anchor_end: "END", kind: "match_char_arms" };
  assert.equal(sliceByAnchors("xx BEGIN 'a' END yy", spec2).body, " 'a' ");
});

test("extractLetters：三种 kind 各自成形 + marker 附加", () => {
  const cp = extractLetters("c == 100 || c == 120 || c == 88", "", { file: "f", anchor_start: "", anchor_end: "", kind: "codepoint_eq_chain" });
  assert.deepEqual([...cp].sort(), ["X", "d", "x"]);
  const arms = extractLetters("'d' | 'i' | 'u' => 1\ncase 'f' => 2\n'%\\{spec}'", "", { file: "f", anchor_start: "", anchor_end: "", kind: "match_char_arms" });
  assert.deepEqual([...arms].sort(), ["d", "f", "i", "u"]); // 插值串不命中
  const consts = extractLetters("const SCANF_D = 100\nconst SCANF_N = 110", "ScanfItem::Scanset(", {
    file: "f",
    anchor_start: "",
    anchor_end: "",
    kind: "scanf_consts",
    extra_by_marker: [{ marker: "ScanfItem::Scanset(", letter: "[" }],
  });
  assert.deepEqual([...consts].sort(), ["[", "d", "n"]);
  // 常量集注释行里的字母说明不算（剥离后）
  const consts2 = extractLetters("// 说明 e/g\nconst SCANF_D = 100", "", { file: "f", anchor_start: "", anchor_end: "", kind: "scanf_consts" });
  assert.deepEqual(consts2, ["d"]);
});

test("C11 全集常量：printf 18 / scanf 19（含 scanset [）", () => {
  assert.equal(C11_PRINTF.length, 18);
  assert.equal(C11_SCANF.length, 19);
  assert.ok(C11_SCANF.includes("["));
});

test("真实仓库：四面抽取非空、彼此与声明一致（verdict 绿）", () => {
  const rd = loadRules();
  const faces = allFaces(rd);
  for (const f of Object.values(faces)) assert.ok(f.letters.length > 0, f.name);
  assert.equal(verdict(rd, faces), true, "真实四面应满足五判据");
});

test("J9 红：内存注入四面漂移各一路必红", () => {
  const rd = loadRules();
  const faces = allFaces(rd);
  // 面①：host 面多出未声明字母
  {
    const f2 = { ...faces };
    const hf = f2["printf_host"]!;
    f2["printf_host"] = { ...hf, letters: [...hf.letters, "q"], set: new Set([...hf.letters, "q"]) };
    assert.equal(verdict(rd, f2), false);
  }
  // 面②：host 面空集（锚点失效形态）
  {
    const f2 = { ...faces };
    f2["scanf_typeck"] = { name: "scanf_typeck", letters: [], set: new Set<string>(), srcPath: "(fixture)" };
    assert.equal(verdict(rd, f2), false);
  }
  // 面③：僵尸 divergence（两面一致却带 reason）
  {
    const rd2 = JSON.parse(JSON.stringify(rd)) as typeof rd;
    const d = rd2.families["printf"]!.letters["d"]!;
    d.divergence = "僵尸探针";
    assert.equal(verdict(rd2, faces), false);
  }
  // 面④：分叉无 reason
  {
    const rd2 = JSON.parse(JSON.stringify(rd)) as typeof rd;
    const d = rd2.families["scanf"]!.letters["e"]!;
    delete d.divergence;
    assert.equal(verdict(rd2, faces), false);
  }
});

test("子进程：-check rc=0 / --selftest rc=0 / 未知参数 rc=2", () => {
  const run = (args: string[]): number => {
    const r = spawnSync(process.execPath, [MAIN, ...args], { cwd: projectRoot() });
    return r.status ?? -1;
  };
  assert.equal(run(["-check"]), 0);
  assert.equal(run(["--selftest"]), 0);
  assert.equal(run(["--bogus"]), 2);
});
