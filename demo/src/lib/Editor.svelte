<script lang="ts">
  // 编辑器组件（F4 殿后批终版：CodeMirror 6 minimal，2026-10-16 用户拍板
  // 「CM6 min（legacy clike 正则 mode + 行号 + 历史）——demo 作为展示怎么
  // 轻松怎么来」）：CM6 白送面（旧栈手搓全清）：行号 gutter + **断点 gutter
  // 真实可点**（审阅 B-P0-1 死 UI 在 CM6 gutter 机制下结构性不存在）、
  // undo/redo 历史（内置——旧栈切文件丢撤销的病可救）、IME 成熟处理
  // （B-P1-5）、clike 正则高亮（legacy mode，用户指定）、当前行高亮内置。
  // 数据流：source $bindable ↔ CM6（外部设码 dispatch / 内部编辑 updateListener）；
  // 断点：session.breakpoints（行号数组单源）↔ CM6 gutter marker（$effect 同步
  //   dispatch StateEffect）；采集下发：getBpLines()（App 采集按钮调）。
  // 高度：theme height auto + scroller overflow hidden（随代码自动增高，
  //   不内滚——对齐 field-sizing 诉求）。
  // 高亮面注意：clike 是 legacy 正则 mode（用户指定）——非 Lezer 语法树高亮。
  import { EditorState, StateEffect, StateField } from "@codemirror/state";
  import { EditorView, gutter, GutterMarker, keymap, highlightActiveLine, highlightActiveLineGutter, lineNumbers, Decoration, type DecorationSet } from "@codemirror/view";
  import { defaultKeymap, history, historyKeymap, insertNewlineAndIndent, indentMore, indentLess } from "@codemirror/commands";
  import { StreamLanguage, syntaxHighlighting, HighlightStyle, foldGutter } from "@codemirror/language";
  import { tags } from "@lezer/highlight";
  import { closeBrackets, closeBracketsKeymap, autocompletion, completionKeymap } from "@codemirror/autocomplete";
  import { highlightSelectionMatches, searchKeymap, search } from "@codemirror/search";
  import { c as clikeC } from "@codemirror/legacy-modes/mode/clike";
  import { session, toggleBreakpoint } from "../session.svelte.ts";

  let { source = $bindable(""), disabled = false }: { source?: string; disabled?: boolean } = $props();

  let hostEl: HTMLDivElement | undefined = $state();
  let view: EditorView | null = $state(null);

  // ── 断点 gutter（CM6 官方 breakpoint example 形态）────────────────
  const setBpEffect = StateEffect.define<number[]>(); // 全量替换断点行集
  // ⚠️ Map value 恒 null（Set 化用法）——lineMarker 必须用 .has() 判在否；
  // 曾写 .get() 真值判断：get 命中也返回 null（falsy）→ 点永不渲染
  // （2026-10-16 E2E S4 四层连抓的最后一层）。
  const bpField = StateField.define<Map<number, null>>({
    create: () => new Map(),
    update(bps, tr) {
      let next = bps;
      for (const e of tr.effects) {
        if (e.is(setBpEffect)) {
          next = new Map();
          for (const ln of e.value) next.set(ln, null);
        }
      }
      return next;
    },
  });
  class BpMarker extends GutterMarker {
    toDOM() {
      const s = document.createElement("span");
      s.textContent = "●";
      s.className = "bp-dot";
      return s;
    }
  }
  const bpMarker = new BpMarker();
  const bpGutter = gutter({
    class: "cm-bpgutter",
    // ⚠️ lineMarker 的 line 是 BlockInfo（行块，无 .number——TS 类型面
    // 2026-10-16 svelte-check 实锤；运行时取 .number 得 undefined 致点
    // 不渲染）。行号须经 doc.lineAt(line.from).number 换算；bpField 键 =
    // 行号（session.breakpoints 语义，曾错用 line.from 字符位置查表）。
    lineMarker(view, line) {
      return view.state.field(bpField, false)?.has(view.state.doc.lineAt(line.from).number) ? bpMarker : null;
    },
    initialSpacer: () => bpMarker,
    // ⚠️ lineMarker 形态必须配 lineMarkerChange——否则 gutter 只认 markers
    // RangeSet 变化（我们用 bpField + lineMarker，markers 恒空），断点状态
    // 变化永不触发重排（E2E S4 实锤：点有反应、装饰有反应、gutter 点不渲染）。
    // 判据 = bpField 引用变化（每次 setBpEffect 全量替换 Map——引用比较即够，
    // 同行号 gutter 的 facet 恒等判据同形态）。
    lineMarkerChange: (u) => u.startState.field(bpField, false) !== u.state.field(bpField, false),
    domEventHandlers: {
      mousedown(view, line) {
        // ⚠️ 本回调的 line 是 lineBlockAtHeight 的 LineBlock——只有 .from
        // （字符位置）没有 .number；行号须经 doc.lineAt(from).number 换算
        // （曾错写 line.from + 1：仅第 1 行碰巧正确，其余行全飘）。
        // 只改单源（session.breakpoints）——视图同步统一走下方 $effect
        // （F4 残留④：双通道易互相掩盖不同步问题，单源单通道可证伪）
        toggleBreakpoint(view.state.doc.lineAt(line.from).number);
        return true;
      },
    },
  });

  // ── 断点行装饰（F4 残留④：旧栈 #editor-hl .cl.bp-on 的新栈等价）─────
  // 旧栈 hl 层对断点行 = danger 粗体行号 + 左侧点；CM6 栈的行装饰语言：
  // 行底淡染 cm-bpline（仅 --danger-tint 无 inset 边）+ bp gutter 点。
  // 与诊断跳转行 cm-diagline 的区分：诊断 = 瞬时指引（tint + inset danger
  // 边），断点 = 持久标记（仅 tint）——同色系不同形，两态不混。
  //
  // **原 F4-10 挂账的架构性消解**：挂账形态 = 旧栈 deco 生成回调经跨模块
  // 普通函数间接读断点单源，Svelte 5 对该嵌套回调内的信号读取不跟踪
  // （四形态复现、mutations=0 铁证）。CM6 化后 deco 回调形态不复存在；
  // 同步改走 $effect **直接在 effect 体内读 session.breakpoints**（教科书
  // 式可跟踪读法——非嵌套回调间接读），全量 dispatch 两个字段。原「兜底」
  // 升正：外部变更（清空/分享还原/未来批量面）同样触发，不再依赖 gutter
  // mousedown 单通道。
  const setBpLinesEffect = StateEffect.define<number[]>();
  const bpLineField = StateField.define<DecorationSet>({
    create: () => Decoration.none,
    update(decos, tr) {
      decos = decos.map(tr.changes);
      for (const e of tr.effects) {
        if (e.is(setBpLinesEffect)) {
          const ranges = e.value
            .filter((ln) => ln >= 1 && ln <= tr.state.doc.lines)
            .map((ln) => Decoration.line({ class: "cm-bpline" }).range(tr.state.doc.line(ln).from));
          decos = Decoration.set(ranges, true);
        }
      }
      return decos;
    },
    provide: (f) => EditorView.decorations.from(f),
  });

  // ── 诊断跳转行高亮（F4 残留①：诊断卡 jumpy 行 click → revealLine）─────
  // StateField 持行装饰集（cm-diagline 类 = 左侧 danger 边 + 淡底），经
  // setDiagLineEffect 全量替换；与断点 bpField 同形态、互不干涉。
  const setDiagLineEffect = StateEffect.define<number[]>();
  const diagLineField = StateField.define<DecorationSet>({
    create: () => Decoration.none,
    update(decos, tr) {
      decos = decos.map(tr.changes);
      for (const e of tr.effects) {
        if (e.is(setDiagLineEffect)) {
          const ranges = e.value.map((ln) => {
            const n = Math.min(Math.max(ln, 1), tr.state.doc.lines);
            return Decoration.line({ class: "cm-diagline" }).range(tr.state.doc.line(n).from);
          });
          decos = Decoration.set(ranges, true);
        }
      }
      return decos;
    },
    provide: (f) => EditorView.decorations.from(f),
  });

  // ── 语法高亮（V1/V2，#141）：token→tokens.css 主题变量——五主题语法色
  // 随 data-theme 切换，规格对齐旧栈 style.css:221-225 五类映射（关键词/
  // 类型并入 --kw；字符串 --str；数字 --num；注释 --cmt 斜体；预处理行
  // meta 并入 --num 暖橙）。替代 CM6 内置 defaultHighlightStyle 固定色板
  // （其 keyword 在 Vitro 深底上对比度不足且恒不随主题——「关键字零着色」
  // 用户实测根因）。
  const vitroHighlight = HighlightStyle.define([
    { tag: tags.keyword, color: "var(--kw)" },
    { tag: tags.atom, color: "var(--kw)" },
    { tag: tags.typeName, color: "var(--kw)" },
    { tag: tags.number, color: "var(--num)" },
    { tag: tags.string, color: "var(--str)" },
    { tag: tags.comment, color: "var(--cmt)", fontStyle: "italic" },
    { tag: tags.meta, color: "var(--num)" },
    { tag: tags.operator, color: "var(--t1)" },
    { tag: tags.punctuation, color: "var(--t1)" },
  ]);

  // ── 回放跟随行染（A13，#140）：帧 code_line 驱动的中性 accent 淡染——
  // 与诊断跳转（danger 边 + tint）和断点行（danger tint）同构不同色，三态
  // 不混。scrollIntoView nearest：行在视口内不滚动（播放时不晕）。
  const setFollowLineEffect = StateEffect.define<number[]>();
  const followLineField = StateField.define<DecorationSet>({
    create: () => Decoration.none,
    update(decos, tr) {
      decos = decos.map(tr.changes);
      for (const e of tr.effects) {
        if (e.is(setFollowLineEffect)) {
          const ranges = e.value
            .filter((ln) => ln >= 1 && ln <= tr.state.doc.lines)
            .map((ln) => Decoration.line({ class: "cm-followline" }).range(tr.state.doc.line(ln).from));
          decos = Decoration.set(ranges, true);
        }
      }
      return decos;
    },
    provide: (f) => EditorView.decorations.from(f),
  });

  // ── vis_events 左缘标记（A14，#140）：当前帧 vis_events 行集 → 行左缘
  // accent 竖条（旧栈 .cl.vis-on::before 同形态）。session.visLines 派生
  // 驱动（此前死派生——呈现面在此接线）。
  const setVisLinesEffect = StateEffect.define<number[]>();
  const visLineField = StateField.define<DecorationSet>({
    create: () => Decoration.none,
    update(decos, tr) {
      decos = decos.map(tr.changes);
      for (const e of tr.effects) {
        if (e.is(setVisLinesEffect)) {
          const ranges = e.value
            .filter((ln) => ln >= 1 && ln <= tr.state.doc.lines)
            .map((ln) => Decoration.line({ class: "cm-visline" }).range(tr.state.doc.line(ln).from));
          decos = Decoration.set(ranges, true);
        }
      }
      return decos;
    },
    provide: (f) => EditorView.decorations.from(f),
  });

  // ── 扩展集 ──────────────────────────────────────────────────────────
  // ⚠️ 每个 StateField 都必须在此登记才存在——bpField 曾漏登记（gutter 里
  // field(bpField, false) 静默取 undefined，断点never渲染；E2E S4 2026-10-16
  // 实锤）。字段：bpField（gutter 点）/ bpLineField（断点行染）/
  // diagLineField（诊断跳转行染）/ followLineField（回放跟随行染）/
  // visLineField（vis_events 左缘标记）。
  function buildExtensions(): any[] {
    return [
      lineNumbers(),
      bpField,
      bpGutter,
      bpLineField,
      diagLineField,
      followLineField,
      visLineField,
      highlightActiveLineGutter(),
      highlightActiveLine(),
      history(),
      keymap.of([...closeBracketsKeymap, ...defaultKeymap, ...searchKeymap, ...historyKeymap, ...completionKeymap]),
      // ⚠️ 必须用预配置导出 c——此前误写 clike({ name: "text/x-csrc" })：工厂
      // 拿到空配置，keywords/types 词表全 undefined，关键字/类型永不产出
      // token（裸文本，语法高亮名存实亡的直接根因，V1 #141）。
      StreamLanguage.define(clikeC),
      syntaxHighlighting(vitroHighlight),
      keymap.of([{ key: "Enter", run: insertNewlineAndIndent }, { key: "Tab", run: indentMore, shift: indentLess }]),
      foldGutter(),
      closeBrackets(),
      autocompletion({ activateOnTyping: false }),
      highlightSelectionMatches(),
      search({ top: true }),
      EditorView.lineWrapping,
      EditorView.updateListener.of((u) => {
        if (u.docChanged) source = u.state.doc.toString();
      }),
      EditorState.readOnly.of(disabled),
    ];
  }

  // ── 挂载 / 销毁 ─────────────────────────────────────────────────────
  $effect(() => {
    if (!hostEl) return;
    const v = new EditorView({
      state: EditorState.create({ doc: source ?? "", extensions: buildExtensions() }),
      parent: hostEl,
    });
    view = v;
    return () => {
      v.destroy();
      view = null;
    };
  });

  // ── 外部设码（点课载入/分享还原）：doc 全量替换 ────────────────────
  $effect(() => {
    if (!view || source === undefined) return;
    if (view.state.doc.toString() !== source) {
      view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: source } });
    }
  });

  // ── 断点单源 → 视图（F4 残留④）：$effect 直接读 session.breakpoints
  // （可跟踪），全量替换 gutter 点字段 + 行装饰字段。首挂载/外部变更/
  // gutter 点击同一通道——单源单通道，不同步即可证伪。 ──
  $effect(() => {
    if (!view) return;
    const bps = [...session.breakpoints];
    view.dispatch({ effects: [setBpEffect.of(bps), setBpLinesEffect.of(bps)] });
  });

  export function getDoc(): string {
    return view?.state.doc.toString() ?? "";
  }
  export function getBpLines(): number[] {
    return view ? [...view.state.field(bpField, false)?.keys() ?? []] : [];
  }
  /** 诊断跳转（F4 残留①）：高亮目标行 + 光标落行首 + 滚动居中 + 1.2s
   *  闪烁后自动清除（A27，#140——旧栈 line-flash 同语义：瞬时指引非持久
   *  标记；行号越界钳制；编辑器未挂载时空操作）。 */
  export function revealLine(line: number): void {
    if (!view) return;
    const n = Math.min(Math.max(Math.round(line), 1), view.state.doc.lines);
    const pos = view.state.doc.line(n).from;
    view.dispatch({
      selection: { anchor: pos },
      effects: [setDiagLineEffect.of([n]), EditorView.scrollIntoView(pos, { y: "center" })],
    });
    view.focus();
    window.setTimeout(() => {
      // 只清自己发起的那次（若期间有新跳转，新 effect 全量替换后此处再清
      // 会闪断——比对当前行集是否仍是本行）
      if (view && view.state.field(diagLineField, false)?.size === 1) {
        view.dispatch({ effects: [setDiagLineEffect.of([])] });
      }
    }, 1200);
  }

  /** 回放跟随（A13，#140）：帧 code_line 驱动——中性 accent 淡染 + 行出
   *  视口时就近滚动（不强制居中、不抢焦点——播放节奏不被打断）。 */
  export function followLine(line: number): void {
    if (!view) return;
    const n = Math.min(Math.max(Math.round(line), 1), view.state.doc.lines);
    const pos = view.state.doc.line(n).from;
    view.dispatch({
      effects: [setFollowLineEffect.of([n]), EditorView.scrollIntoView(pos, { y: "nearest" })],
    });
  }

  /** vis_events 左缘标记（A14，#140）：当前帧事件行集全量替换（session
   *  visLines 派生经 App $effect 下发）。 */
  export function setVisLines(lines: number[]): void {
    if (!view) return;
    view.dispatch({ effects: [setVisLinesEffect.of(lines)] });
  }
</script>

<div class="editor-stack" bind:this={hostEl}></div>

<style>
  .editor-stack { background: var(--editor-bg); border: 1px solid var(--hairline); border-radius: 8px; overflow: hidden; }
  /* CM6 主题：tokens 变量适配五主题；高度自适应（随代码自动增高，不内滚） */
  .editor-stack :global(.cm-editor) { background: var(--editor-bg); color: var(--code-text); font: var(--ed-fs, 14px)/1.5 var(--mono); height: auto; font-variant-ligatures: none; font-feature-settings: "liga" 0, "calt" 0; }
  .editor-stack :global(.cm-editor.cm-focused) { outline: none; }
  .editor-stack :global(.cm-scroller) { overflow: visible; font-family: inherit; line-height: 1.5; }
  .editor-stack :global(.cm-gutters) { background: var(--editor-bg); border-right: 1px solid var(--hairline); color: var(--t3); }
  .editor-stack :global(.cm-activeLineGutter) { background: var(--accent-tint); color: var(--accent-strong); }
  .editor-stack :global(.cm-activeLine) { background: var(--accent-tint); }
  .editor-stack :global(.cm-bpgutter) { width: 14px; }
  .editor-stack :global(.bp-dot) { color: var(--danger); font-size: 10px; }
  /* 断点行（F4 残留④）：行底淡染仅 tint——与 cm-diagline（tint + inset 边）区分形 */
  .editor-stack :global(.cm-bpline) { background: var(--danger-tint); }
  /* 诊断跳转行（F4 残留①）：左侧 danger 边 + 令牌淡底 + 1.2s 闪烁（A27
     旧栈 line-flash 同款节奏）——与 bp-dot 同色系不同形 */
  .editor-stack :global(.cm-diagline) { background: var(--danger-tint); box-shadow: inset 3px 0 0 var(--danger); animation: diag-flash 1.2s ease-out; }
  @keyframes diag-flash { 0% { background: transparent; } 12%, 45% { background: var(--accent-tint); } 70% { background: var(--danger-tint); } 82% { background: var(--accent-tint); } 100% { background: var(--danger-tint); } }
  /* 回放跟随行（A13）：中性 accent 淡染——与断点/诊断的 danger 系区分 */
  .editor-stack :global(.cm-followline) { background: var(--accent-tint); }
  /* vis_events 左缘标记（A14）：行左缘 accent 竖条（旧栈 vis-on::before 同形态） */
  .editor-stack :global(.cm-visline) { box-shadow: inset 3px 0 0 var(--accent); }
</style>
