// render.test.mts —— docs 站渲染契约（#273 批二：承接 mdrender 回归用例的语义面）。
//
// 每条对应用测试过的行为坑（历史 markdown_test.go 七组 + 批二新增的 GFM 越界面），
// 换成 marked 实现后仍须成立；不锁块级 HTML 的逐字节形态（渲染器差异已记录）。
import { test } from "node:test";
import assert from "node:assert/strict";
import { extractOutline, renderInline, renderMarkdown, slugify } from "./render.mts";

test("行内强调：粗体 / 斜体 / 删除线", () => {
  assert.equal(renderInline("**abc**"), "<strong>abc</strong>");
  assert.equal(renderInline("*abc*"), "<em>abc</em>");
  assert.equal(renderInline("~~abc~~"), "<del>abc</del>");
});

test("强调边界：全角标点收尾可闭合，下划线词内不强调", () => {
  // marked 对文本引号输出 &quot;（mdrender 输出裸引号）——可见文本一致，锁实体形态
  assert.equal(renderInline('**如实标注为"待办"**；'), "<strong>如实标注为&quot;待办&quot;</strong>；");
  assert.equal(renderInline("next_local_offset 与 a_b_c"), "next_local_offset 与 a_b_c");
});

test("GFM 越界面：单波浪号不构成删除线（批一~批五 是正文）", () => {
  assert.equal(renderInline("批一~批五"), "批一~批五");
  assert.equal(renderInline("2026-10-05~07"), "2026-10-05~07");
});

test("行内 HTML 检测：比较符不当标签，合法标签透传", () => {
  assert.equal(renderInline("RSS 增量 <1MB 且 >50 检查点"), "RSS 增量 &lt;1MB 且 &gt;50 检查点");
  assert.equal(renderInline("写 <br> 换行"), "写 <br> 换行");
});

test("代码块转义裸文本：<u32> / <class T> 不得成为真标签", () => {
  const out = renderMarkdown("```cpp\nOption<u32> f(vector<class T>& v);\n```\n");
  assert.doesNotMatch(out, /<u32>|<class T>/);
  assert.match(out, /&lt;u32&gt;/);
  assert.match(out, /pre class="code-hl" data-lang="cpp"/);
  assert.match(out, /tok-t/);
});

test("无语言围栏 = code-plain", () => {
  assert.match(renderMarkdown("```\nplain & <raw>\n```\n"), /pre class="code-plain"><code>plain &amp; &lt;raw&gt;<\/code><\/pre>/);
});

test("表格：列数不一致不成立；正常表格加 table-wrap；可打断段落", () => {
  const mismatch = renderMarkdown("| a | b |\n|---|------|---|\n| 1 | 2 | 3 |\n");
  assert.doesNotMatch(mismatch, /<table>/);
  const ok = renderMarkdown("| a | b |\n|---|---|\n| 1 | 2 |\n");
  assert.match(ok, /<div class="table-wrap"><table>/);
  const para = renderMarkdown("**标题**:\n| a | b |\n|---|---|\n| 1 | 2 |\n");
  assert.match(para, /<table>/);
  assert.match(para, /<p>/);
});

test("列表打断段落：有序列表须以 1 开头，空列表项不打断", () => {
  assert.doesNotMatch(renderMarkdown("第二批（CI 门禁，1 天）\n7. E-P0-1：补 exit code\n"), /<ol|<li/);
  assert.match(renderMarkdown("第二批（CI 门禁，1 天）\n1. E-P0-1：补 exit code\n"), /<ol/);
  assert.doesNotMatch(renderMarkdown("说明如下\n- \n"), /<ul/);
});

test("标题锚点：GitHub slug 规则 + 同页去重", () => {
  const html = renderMarkdown("## §14 JIT trace 路径 P0 静默错值\n");
  assert.match(html, /id="14-jit-trace-路径-p0-静默错值"/);
  const html2 = renderMarkdown("#### 定位、路线与架构（含 C++/CLI）\n");
  assert.match(html2, /id="定位路线与架构含-ccli"/);
  const dup = renderMarkdown("# Same\n\n# Same\n");
  assert.match(dup, /id="same"/);
  assert.match(dup, /id="same-1"/);
  assert.equal(slugify("定位、路线"), "定位路线");
});

test("链接改写只作用于链接目标，代码块内容不参与", () => {
  const rewrite = (dest: string): string => (dest === "a.md" ? "a.html" : dest);
  const html = renderMarkdown("[x](a.md)\n\n`[y](a.md)`\n\n```\n[z](a.md)\n```\n", { rewrite, rel: "d/x.md" });
  assert.match(html, /<a href="a\.html">x<\/a>/);
  assert.match(html, /\[y\]\(a\.md\)/);
  assert.match(html, /\[z\]\(a\.md\)/);
});

test("GFM 自动链接：裸 URL 保留，裸邮箱不 mailto", () => {
  const html = renderMarkdown("见 https://x.com/a 与 moonbitlang/x@0.5.5\n");
  assert.match(html, /<a href="https:\/\/x\.com\/a">/);
  assert.doesNotMatch(html, /mailto:/);
});

test("大纲抽取：h1–h3 且带 id，剥标签与实体", () => {
  const html = renderMarkdown("# T\n\n## `code` & <b>bold</b>\n\n#### 深\n");
  const outline = extractOutline(html, 3);
  assert.deepEqual(outline, [
    { l: 1, i: "t", t: "T" },
    { l: 2, i: "code--bboldb", t: "code & bold" },
  ]);
});
