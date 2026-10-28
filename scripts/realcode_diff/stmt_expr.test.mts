// stmt_expr 纯函数单测：剥壳/语句表达式消解/层判定/输出归一。
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  firstLine,
  layerOf,
  normalize,
  splitLastStmt,
  stripStdbool,
  stripStmtExprs,
  vnEqualIgnoreDigits,
} from "./stmt_expr.mts";

test("stripStdbool：stdbool → 三行 #define（缩进保留）", () => {
  const r = stripStdbool('int main() {\n  #include <stdbool.h>\n}\n');
  assert.equal(r.changed, true);
  assert.match(r.src, /  #define bool int\n  #define true 1\n  #define false 0/);
  assert.equal(stripStdbool("int x;").changed, false);
});

test("stripStmtExprs：ASSERT 语句表达式→块语句（保值形态）", () => {
  const src = "ASSERT(8, ({ union { int a; } x; sizeof(x); }));\n";
  const r = stripStmtExprs(src);
  assert.equal(r.count, 1);
  assert.equal(r.src, "{ union { int a; } x; int __vitro_sx0 = sizeof(x); ASSERT(8, __vitro_sx0); };\n");
});

test("stripStmtExprs：多语句体与多处消解", () => {
  const src = "ASSERT(3, ({ union {int a,b;} x,y; x.a=3; y.a=5; y=x; y.a; }));\nASSERT(1, ({ 1; }));\n";
  const r = stripStmtExprs(src);
  assert.equal(r.count, 2);
  assert.match(r.src, /int __vitro_sx0 = y\.a;/);
  assert.match(r.src, /ASSERT\(3, __vitro_sx0\)/);
  assert.match(r.src, /ASSERT\(1, __vitro_sx1\)/);
});

test("stripStmtExprs：含控制流/末条声明的语句体不消解", () => {
  assert.equal(stripStmtExprs("ASSERT(1, ({ if (x) return 1; 2; }));").count, 0);
  assert.equal(stripStmtExprs("ASSERT(1, ({ int a = 1; int b = a; }));").count, 0);
  assert.equal(stripStmtExprs("int y = ({ 1; });").count, 0);
});

test("splitLastStmt：GNU 语句表达式取最后一条表达式", () => {
  assert.deepEqual(splitLastStmt("int i=0; while(i<10) i=i+1; i;"), {
    stmts: "int i=0; while(i<10) i=i+1;",
    last: "i",
    ok: true,
  });
  assert.deepEqual(splitLastStmt("1; {2;} 3;"), { stmts: "1; {2;}", last: "3", ok: true });
  assert.deepEqual(splitLastStmt(";;; 5;"), { stmts: ";;;", last: "5", ok: true });
  assert.equal(splitLastStmt("int a = 1;").ok, false);
  assert.equal(splitLastStmt("").ok, false);
});

test("layerOf：E1/E2/E3 层归并与顺序口径", () => {
  const d = (severity: string, code: string) => ({ severity, code, line: 1, column: 1, message: "" });
  assert.equal(layerOf([]), "ok");
  assert.equal(layerOf([d("warning", "W1018")]), "ok");
  // PR #350 审阅 P2-1 翻案（2026-10-28）：首层语义——旧断言锚「末错覆盖」
  //（E2 前置 E3 尾随 → typeck）与 codegen 闸 fail_stage:"parse" 对同一
  // 事实相反；首失败层在 parse（E2005 先到），期望改 parse
  assert.equal(layerOf([d("error", "E2005"), d("error", "E3003")]), "parse");
  assert.equal(layerOf([d("error", "E3003"), d("error", "E2005")]), "parse");
  assert.equal(layerOf([d("error", "E1005")]), "lex");
});

test("normalize：ANSI / EXIT 行 / Warning 块 / 行尾空白", () => {
  const raw = Buffer.from(
    [
      "\x1b[31mred\x1b[0m   ",
      "Warning: [1234] build noise",
      "╭─[x]",
      "│ detail",
      "╰─────╯",
      "keep\t",
      "// EXIT 3",
    ].join("\n"),
    "utf8",
  );
  // Go 真值：Warning 块删除后残留一个空行
  assert.equal(normalize(raw).toString("utf8"), "red\n\nkeep");
});

test("normalize：中文按字节保真；vnEqualIgnoreDigits 只抹数字", () => {
  const a = normalize(Buffer.from("结果=12\n", "utf8"));
  const b = normalize(Buffer.from("结果=34\n", "utf8"));
  assert.equal(Buffer.byteLength(a, "utf8"), Buffer.byteLength("结果=12", "utf8"));
  assert.equal(vnEqualIgnoreDigits(a, b), true);
  assert.equal(vnEqualIgnoreDigits(normalize(Buffer.from("a1", "utf8")), normalize(Buffer.from("a2b", "utf8"))), false);
});

test("firstLine：取首行并截断到 120 字节", () => {
  assert.equal(firstLine("  a\nb  "), "a");
  assert.equal(Buffer.byteLength(firstLine("x".repeat(200)), "utf8"), 120);
});
