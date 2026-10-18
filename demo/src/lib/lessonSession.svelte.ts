// Vitro · 当前课/当前源码/当前叙述的单点（2026-10-18 前端改造）。
//
// 旧 App.svelte 里的 onPickLesson（点课 = 载源码 + 建 currentCase + 懒加载
// 叙述 + 自动采集）迁到此层：入口态「在实验台打开」、参考态「在实验台复现」、
// 首访落地、继续上次四条入口共用同一动作，避免四份近似实现漂移。
//
// 职责边界：
//   - 本层写 lessonSession.source / session.currentCase / progress / ui.screen；
//   - 不碰编辑器实例（source 经 prop 下发，CM6 自会同步）；
//   - 工作区守卫走 ensureClosedForLesson（dirty 时 confirm 保存）。
"use strict";

import { DEMO_CASES } from "virtual:demo-globals";
import { collect, resetSession, seek, session } from "../session.svelte.ts";
import { ui } from "../ui.svelte.ts";
import { DEFAULT_PROGRAM } from "../program.ts";
import { defaultLesson, findLesson, noteKeyOf, type CourseLesson } from "./courseIndex.ts";
import { loadLessonNote } from "./lessonNotes.ts";
import type { Block } from "./lessonMd.ts";
import { progress } from "./progress.svelte.ts";
import { ensureClosedForLesson } from "./workspace.svelte.ts";

export interface OpenOpts {
  /** 采集完是否自动播放（首访/继续上次 = false：预载一帧、暂停）。 */
  autoplay?: boolean;
  /** 采集后定位帧（继续上次）。 */
  frame?: number;
  /** 采集完成后回调（首访中段帧定位用——帧流就绪前 frames=0 无从定位）。 */
  onCollected?: () => void;
}

class LessonSessionState {
  /** 编辑器源码（唯一真源；CM6 bind 双向同步）。 */
  source = $state(DEFAULT_PROGRAM);
  /** 当前课叙述（course/<chap>/<id>/lesson.md 懒加载产物；null = 无叙述）。 */
  note = $state<{ title: string; blocks: Block[] } | null>(null);
  /** 当前课（null = 分享还原的自由代码/默认示例）。 */
  lesson = $state<CourseLesson | null>(null);
  /** 课名与章名（面包屑 / kicker；分享代码时是「分享的代码」）。 */
  title = $state("分享的代码");
  chapLabel = $state("");
  /** 课稿原始源码（重置按钮回到这里；null = 自由代码）。 */
  original = $state<string | null>(null);

  /** 载入一课：守卫 → 源码/用例/叙述 → 工作态 → 采集（可选暂停 + 定位帧）。 */
  async open(l: CourseLesson, opts: OpenOpts = {}): Promise<boolean> {
    if (!(await ensureClosedForLesson())) return false;
    this.lesson = l;
    this.title = l.title;
    this.chapLabel = l.chapLabel;
    this.original = l.source;
    this.source = l.source;
    // 用例锚（golden / configHint / argv / 多文件）：同 id 优先 case 类
    // （算法章与基础章可能同 id——case 才有 Clang golden 预置真值）
    const base = DEMO_CASES.find((k) => k.id === l.id) ?? null;
    session.currentCase = base
      ? {
          id: base.id,
          label: base.label,
          source: base.source,
          referenceOutput: base.referenceOutput as string | undefined,
          referenceTrap: base.referenceTrap as string | undefined,
          referenceKind: base.referenceKind as string | undefined,
          configHint: base.configHint as Record<string, unknown> | undefined,
          argv: base.argv as string[] | undefined,
          files: base.files as Array<{ filename: string; source: string }> | undefined,
        }
      : { id: l.id, label: l.title, source: l.source };
    // 叙述懒加载（无此课叙述 = null，诚实空态——不渲染假课文）
    const doc = await loadLessonNote(noteKeyOf(l));
    this.note = doc ? { title: l.title, blocks: doc.blocks } : null;
    ui.screen = "work";
    ui.mode = "exec";
    progress.markDone(l.id);
    progress.rememberLesson(l.id, l.chapId, l.title);
    // 采集后台化（2026-10-19 首开性能批 A，用户拍板）：老框架「点开即显、
    // 采集页面内转」的体感回归——曾 await collect 挡住 App 首访的 ui.ready
    //（载入遮罩等首课采集完成才撤，弱网/移动端首开巨慢的主构成段）。现在
    // 元数据+源码就位即返回，帧流后台渐进填充（状态行「采集中…」诚实可见）。
    // collect 自带 epoch 迟到丢弃与诊断带错误面，后台化不引入新竞态面；
    // 完成后动作（定位帧/onCollected）链在完成点。
    void collect(this.source, [], { autoplay: opts.autoplay !== false })
      .then(() => {
        if (opts.frame != null && opts.frame > 0) seek(opts.frame);
        opts.onCollected?.();
      })
      .catch(() => { /* collect 错误已进诊断带/status；此处兜底防 unhandled rejection */ });
    return true;
  }

  /** 首访落地：继续上次（同课且未改帧）或默认 bubble。 */
  async openInitial(): Promise<void> {
    const last = progress.last;
    const hit = last ? findLesson(last.lessonId, last.chapId) : null;
    const target = hit ?? defaultLesson();
    if (!target) return;
    // 真首访（无上次记录）：采集后停在**中段帧**——设计说明 §2.3 的首访动线
    // 要求「第一眼就看到代码 + 数组 + 时间轴」，帧 0 往往还在序言（数组全 0、
    // 变量表空）。中段帧是真实执行状态，状态行明示「已暂停 · 第 N / M 帧」。
    // （采集后台化后本函数不再被采集挡住；中段帧定位链在采集完成点。）
    await this.open(target.lesson, {
      autoplay: false,
      frame: hit ? last.frame : 0,
      onCollected: hit
        ? undefined
        : () => {
            const n = session.viewFrames.length;
            if (n > 2) seek(Math.round((n - 1) / 2));
          },
    });
  }

  /** 「继续上次」卡：回到上次课与帧（不自动播放）。 */
  async resumeLast(): Promise<void> {
    const last = progress.last;
    const hit = last ? findLesson(last.lessonId, last.chapId) : null;
    if (!hit) return;
    await this.open(hit.lesson, { autoplay: false, frame: last.frame });
  }

  /** 参考态「在实验台复现」/ 相关课程：按课 id 打开。 */
  async openById(id: string, chapId = ""): Promise<void> {
    const hit = findLesson(id, chapId);
    if (!hit) return;
    await this.open(hit.lesson, { autoplay: true });
  }

  /** 分享链接还原（自由代码：无课锚、无叙述、无 golden）。
   *  **不自动运行**（README §链接分享的既定承诺）：`#` 内容是不可信输入，
   *  只落到编辑器 + 清空旧帧流；用户点「运行」才编译。 */
  setShared(source: string): void {
    this.lesson = null;
    this.title = "分享的代码";
    this.chapLabel = "分享";
    this.original = null;
    this.source = source;
    this.note = null;
    session.currentCase = null;
    session.liveSource = source;
    resetSession();
    ui.screen = "work";
    ui.mode = "exec";
  }

  /** 重置：源码回到课稿原文（仪器清场由 resetSession 负责）。 */
  restoreOriginal(): void {
    if (this.original != null) this.source = this.original;
  }
}

export const lessonSession = new LessonSessionState();
