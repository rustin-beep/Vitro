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
  import { EditorView, gutter, GutterMarker, keymap, highlightActiveLine, highlightActiveLineGutter, lineNumbers } from "@codemirror/view";
  import { defaultKeymap, history, historyKeymap, insertNewlineAndIndent, indentMore, indentLess } from "@codemirror/commands";
  import { StreamLanguage, syntaxHighlighting, defaultHighlightStyle, foldGutter } from "@codemirror/language";
  import { closeBrackets, closeBracketsKeymap, autocompletion, completionKeymap } from "@codemirror/autocomplete";
  import { highlightSelectionMatches, searchKeymap, search } from "@codemirror/search";
  import { clike } from "@codemirror/legacy-modes/mode/clike";
  import { session, toggleBreakpoint } from "../session.svelte.ts";

  let { source = $bindable(""), disabled = false }: { source?: string; disabled?: boolean } = $props();

  let hostEl: HTMLDivElement | undefined = $state();
  let view: EditorView | null = $state(null);

  // ── 断点 gutter（CM6 官方 breakpoint example 形态）────────────────
  const setBpEffect = StateEffect.define<number[]>(); // 全量替换断点行集
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
    lineMarker(view, line) {
      return view.state.field(bpField, false)?.get(line.from) ? bpMarker : null;
    },
    initialSpacer: () => bpMarker,
    domEventHandlers: {
      mousedown(view, line) {
        const ln = line.from + 1;
        toggleBreakpoint(ln);
        view.dispatch({ effects: setBpEffect.of([...session.breakpoints]) });
        return true;
      },
    },
  });

  // ── 扩展集 ──────────────────────────────────────────────────────────
  function buildExtensions(): any[] {
    return [
      lineNumbers(),
      bpGutter,
      highlightActiveLineGutter(),
      highlightActiveLine(),
      history(),
      keymap.of([...closeBracketsKeymap, ...defaultKeymap, ...searchKeymap, ...historyKeymap, ...completionKeymap]),
      StreamLanguage.define(clike({ name: "text/x-csrc" })),
      syntaxHighlighting(defaultHighlightStyle),
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

  export function getDoc(): string {
    return view?.state.doc.toString() ?? "";
  }
  export function getBpLines(): number[] {
    return view ? [...view.state.field(bpField, false)?.keys() ?? []] : [];
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
</style>
