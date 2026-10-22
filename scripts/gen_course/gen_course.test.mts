// gen_course.test.mts —— frontmatter 解析与确定性发射契约（#273 批二）。
import { test } from "node:test";
import assert from "node:assert/strict";
import { emit, parseFrontmatter } from "./main.mts";

test("parseFrontmatter：key: value + 引号剥离 + CRLF 归一", () => {
  const { fm, body } = parseFrontmatter("---\r\nid: hello\r\nkind: \"case\"\r\norder: 3\r\n---\r\n正文\n");
  assert.equal(fm.get("id"), "hello");
  assert.equal(fm.get("kind"), "case");
  assert.equal(fm.get("order"), "3");
  // 与 Go 版同口径：收栏行的换行保留（end+4 落在收栏后的 \n 上）
  assert.equal(body, "\n正文\n");
});

test("parseFrontmatter：缺开栏/收栏 fail loud", () => {
  assert.throws(() => parseFrontmatter("id: x\n"), /缺 frontmatter 开栏/);
  assert.throws(() => parseFrontmatter("---\nid: x\n"), /缺 frontmatter 收栏/);
  assert.throws(() => parseFrontmatter("---\nnot a pair\n---\n"), /非 key: value/);
});

test("emit：Go 兼容 JSON 转义 + 可选字段省略 + 末项无逗号", () => {
  const out = emit([
    { id: "a", kind: "case", chap: "c1", order: 1, famId: "", stdin: "", html: "<b>&</b>", dir: "" },
    { id: "b", kind: "variant", chap: "c1", order: 2, famId: "f", stdin: "42\n", html: "x", dir: "" },
  ]);
  assert.match(out, /id: "a"/);
  assert.match(out, /order: 1,/);
  assert.match(out, /html: "\\u003cb\\u003e\\u0026\\u003c\/b\\u003e"/);
  assert.match(out, /famId: "f"/);
  assert.match(out, /stdin: "42\\n"/);
  assert.ok(out.endsWith("  }\n];\n"));
  assert.ok(out.includes('  },\n  {\n    id: "b"'));
  assert.ok(emit([]).endsWith("export const LESSON_NOTES: LessonNote[] = [\n];\n"));
});

test("emit 幂等（同一输入两次字节一致）", () => {
  const lessons = [{ id: "a", kind: "case", chap: "c", order: 1, famId: "", stdin: "", html: "<p>x</p>", dir: "" }];
  assert.equal(emit(lessons), emit(lessons));
});
