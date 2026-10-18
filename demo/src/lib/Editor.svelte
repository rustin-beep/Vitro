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
  import { untrack } from "svelte";
  import { Compartment, EditorState, StateEffect, StateField } from "@codemirror/state";
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

  // ── 语法高亮（V1/V2，#141）：token→app.css 的 --vr-* 主题变量——五主题语法色
  // 随 data-theme 切换，规格对齐旧栈 style.css:221-225 五类映射（关键词/
  // 类型并入 --kw；字符串 --str；数字 --num；注释 --cmt 斜体；预处理行
  // meta 并入 --num 暖橙）。替代 CM6 内置 defaultHighlightStyle 固定色板
  // （其 keyword 在 Vitro 深底上对比度不足且恒不随主题——「关键字零着色」
  // 用户实测根因）。
  const vitroHighlight = HighlightStyle.define([
    { tag: tags.keyword, color: "var(--vr-kw)", fontWeight: "600" },
    { tag: tags.atom, color: "var(--vr-kw)" },
    { tag: tags.typeName, color: "var(--vr-ty)", fontStyle: "italic" },
    { tag: tags.number, color: "var(--vr-num)" },
    { tag: tags.string, color: "var(--vr-str)" },
    { tag: tags.comment, color: "var(--vr-cmt)", fontStyle: "italic" },
    { tag: tags.meta, color: "var(--vr-num)" },
    { tag: tags.operator, color: "var(--vr-ink)" },
    { tag: tags.punctuation, color: "var(--vr-ink)" },
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
            .map((ln) => Decoration.line({ class: "cm-vrline" }).range(tr.state.doc.line(ln).from));
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
  // 采集期只读（2026-10-18 改造批补）：CM6 的 readOnly 只在创建时生效——原实现
  // 把 disabled 写进 create 状态，属性后续变化不重配（首访自动采集期间仍可编辑）。
  // Compartment 让 disabled 真正成为可重配面。
  const readOnlyComp = new Compartment();
  $effect(() => {
    if (!view) return;
    view.dispatch({ effects: readOnlyComp.reconfigure(EditorState.readOnly.of(disabled)) });
  });

  function buildExtensions(): any[] {
    return [
      // 断点 gutter 在行号左侧（设计稿「空心琥珀点」在行号槽外缘）
      bpField,
      bpGutter,
      // 行号数字区点击同设/清断点（#185 拍板组合案①）：教学用户直觉是点行号
      // 数字，13px 无提示窄列 3 次自然尝试全失败——行号槽整列统一交互。
      // ⚠️ line 同为 BlockInfo（只 .from），行号经 doc.lineAt 换算（同上坑注）。
      lineNumbers({
        domEventHandlers: {
          mousedown(view, line) {
            toggleBreakpoint(view.state.doc.lineAt(line.from).number);
            return true;
          },
        },
      }),
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
      // 设计说明 §9-6：390 代码横向滚动而不换行（保行号与语句边界）——
      // 不挂 EditorView.lineWrapping；横向滚动条在 app.css 显式可感知。
      EditorView.updateListener.of((u) => {
        if (u.docChanged) source = u.state.doc.toString();
      }),
      readOnlyComp.of(EditorState.readOnly.of(disabled)),
    ];
  }

  // ── 挂载 / 销毁 ─────────────────────────────────────────────────────
  // ⚠️ 本 effect 的重跑依据只有 hostEl——source 与 disabled 的初值读取必须
  // untrack（#190 根因）：曾直接读取致 effect 依赖 source+disabled，每次键入
  //（updateListener 回写 source）与每次采集翻态（disabled 翻转）都销毁重建
  // 整个 EditorView——CM6 destroy 先 blur content 再移除 DOM：焦点丢（后续
  // 逐键全落 BODY 丢失，实测首字符落地后 3ms 焦点即被赶走）+ history 随销毁
  // 清零（撤销/重做全废）+ selection 重置（光标跳变）。doc 后续同步走下方
  // 外部设码 effect、readOnly 重配走 readOnlyComp effect，职责各归其位。
  $effect(() => {
    if (!hostEl) return;
    const v = new EditorView({
      state: EditorState.create({ doc: untrack(() => source) ?? "", extensions: untrack(() => buildExtensions()) }),
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

  /** 回放跟随（A13，#140）：帧 code_line 驱动——琥珀行染 + 左缘竖条，
   *  行出视口时就近滚动（不强制居中、不抢焦点——播放节奏不被打断）。 */
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

<div class="vr-editor" bind:this={hostEl}></div>
