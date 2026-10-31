// 回放播放头（D3，refs #122）：plan（relayPlan.ts）的执行端，只做视觉补间。
//
// 三条纪律：
//   1. **不撒谎**：pos 是浮点帧坐标，只用于指针/进度条的连续运动；读数、
//      画面帧、幕切换一律仍以整数 session.idx 为准（补间中间态不承载语义）。
//   2. **表驱动**：播放中的单帧移动时长取自计划表（planRelay 的 pointer
//      beat.travel）；暂停时的 seek 用 base token 短滑；直接操作（scrub）、
//      批量推进、动效关闭/系统 reduced 一律瞬时。
//   3. **可观测**：moves 计数器记录 pos 的真实变更次数——E2E 断「有没有
//      补间」用计数，不靠 sleep 赌时序。
//
// 常驻 rAF 循环（空转只做一次数值比较）：idx 变化可能来自播放定时器、
// 键盘/滑条/点幕，统一在这里汇合；页面隐藏时浏览器自动暂停 rAF。
"use strict";

import { session } from "../session.svelte.ts";
import { motion, motionMs, setBeatGate } from "./motion.svelte.ts";
import { planRelay, scalePlan, type RelayEvent, type RelayPlan } from "./relayPlan.ts";

function easeOutCubic(t: number): number {
  return 1 - (1 - t) * (1 - t) * (1 - t);
}

class Playhead {
  /** 运行环境是否有 rAF（SSR / E-08 快照渲染没有——此时指针退化为整数帧）。 */
  readonly supported = typeof requestAnimationFrame === "function";
  /** 指针浮点帧坐标（0..n-1）；只服务视觉补间。 */
  pos = $state(0);
  /** pos 实际变更次数（E2E 观测面）。 */
  moves = 0;
  /** 本轮补间时长（ms；0 = 瞬时到位）。 */
  travelMs = 0;

  /** 读取当前指针坐标：无 rAF 环境直接读整数帧（SSR 快照与真值一致）。 */
  get at(): number {
    return this.supported ? this.pos : session.idx;
  }

  private raf = 0;
  private from = 0;
  private to = 0;
  private t0 = 0;
  private plan: RelayPlan | null = null;
  private planKey = "";
  private planFps = 0;
  /** 指针 beat 的 travel 按帧索引（缓存——不依赖 beats 前 n 位的排列假设）。 */
  private pointerTravels: number[] = [];
  private lastEpoch = -1;
  /** 本周目已放行的事件拍（kind|key|frame）——同帧同键只放行一次。 */
  private fired = new Set<string>();
  private wasPlaying = false;

  start(): void {
    if (this.raf || typeof requestAnimationFrame !== "function") return;
    this.raf = requestAnimationFrame(this.tick);
  }

  private tick = (now: number): void => {
    this.raf = requestAnimationFrame(this.tick);
    this.step(now);
  };

  /** 单帧推进（正常路径由 rAF 驱动；单测/诊断可直接调）。 */
  step(now: number): void {
    if (session.playing && !this.wasPlaying) this.fired.clear(); // 新一周目重新计拍
    this.wasPlaying = session.playing;
    const n = session.viewFrames.length;
    const target = n > 0 ? Math.max(0, Math.min(n - 1, session.idx)) : 0;
    // 换课/重采集（epoch 变）→ 指针瞬时落到新时间轴，不从旧课的帧位置滑入。
    if (session.epoch !== this.lastEpoch) {
      this.lastEpoch = session.epoch;
      this.pos = target;
      this.to = target;
      this.from = target;
      this.travelMs = 0;
      this.t0 = now;
    }
    // 播放中落后超过 1.5 帧（标签页节流/长任务）→ 瞬时对齐，不拖尾。
    const stale = n > 0 && session.playing && Math.abs(this.pos - target) > 1.5;
    if (target !== this.to || stale) {
      this.to = target;
      this.from = stale ? target : this.pos;
      this.t0 = now;
      this.travelMs = stale ? 0 : this.travelFor(target);
    }
    const p = this.travelMs <= 0 ? 1 : Math.min(1, (now - this.t0) / this.travelMs);
    const next = p >= 1 ? this.to : this.from + (this.to - this.from) * easeOutCubic(p);
    if (next !== this.pos) {
      this.pos = next;
      this.moves += 1;
    }
  }

  /** 观测面（E2E/诊断）：当前计划表里的事件目标键（去重，如 swap:a / swap:b）。
   *  多数组课两个键都必须在——按 kind 抽稀会让第二个实体整类消失（P2-1）。 */
  get planKeys(): string[] {
    return [...new Set(this.planFor().beats.filter((b) => b.kind !== "pointer").map((b) => b.key))];
  }

  /** 播放期事件拍门（motion.allowPulse 的判定端）：只有计划表排进本帧、
   *  同 kind 已按 minGap 抽稀、且本周目尚未放行的拍才放行一次。
   *  非播放态由 motion.allowPulse 直接放行，不经过这里。 */
  allowBeat(kind: string, key: string): boolean {
    if (!session.playing) return true;
    const idx = session.idx;
    const plan = this.planFor();
    const id = `${kind}|${key}|${idx}`;
    if (this.fired.has(id)) return false;
    const hit = plan.beats.some((b) => b.kind === kind && b.key === `${kind}:${key}` && b.frame === idx);
    if (!hit) return false;
    this.fired.add(id);
    return true;
  }

  private travelFor(target: number): number {
    if (session.viewFrames.length === 0) return 0;
    if (!motion.allowed || motion.scrubbing || session.batching) return 0;
    if (!session.playing) return motionMs("base");
    this.planFor();
    return this.pointerTravels[target] ?? 0;
  }

  private planFor(): RelayPlan {
    const n = session.viewFrames.length;
    const slow = motionMs("slow");
    // key 覆盖 plan 的全部输入面：采集代号（事件内容随 epoch 变）、帧数、
    // 运行期 token 时长；fps 不进 key——变速走整表乘系数（见 rescaleForFps）。
    const key = `${session.epoch}@${n}@${slow}`;
    if (this.planKey === key && this.plan) {
      this.rescaleForFps();
      return this.plan;
    }
    // 事件轨道本批只喂 swap（ty=2，D1 的主事件）：播放期脉冲由 minGap 抽稀后
    // 按帧放行。变量脉冲（VarsList）播放中仍让位——每帧几乎都有值变化，
    // 抽稀后仍是噪声，留待单独评估；树过渡只在换采集时发生，不参与。
    const events: RelayEvent[] = [];
    for (let i = 0; i < n; i += 1) {
      for (const ev of session.eventsAt(i)) {
        if (ev.ty !== 2) continue;
        // extras 只有下标没有数组名；context 形如 `a[j]:a[j + 1]`，取 `[` 前段。
        const name = (ev.context ?? "").split("[")[0] ?? "";
        events.push({ frame: i, kind: "swap", key: `swap:${name}` });
      }
    }
    const plan = planRelay({
      frames: n,
      fps: session.fps,
      events,
      eventMs: slow,
      travelMaxMs: slow,
      minGapMs: slow,
    });
    this.plan = plan;
    this.planFps = session.fps;
    this.planKey = key;
    this.syncPointerTravels();
    return plan;
  }

  /** 变速 = 对现有表整表乘系数（节奏保持，不重排）。这是唯一的变速执行
   *  路径：plan 只在 epoch / 帧数 / token 时长变化时重建（PR #395 审阅 P2-3）。 */
  private rescaleForFps(): void {
    if (!this.plan || this.planFps <= 0 || this.planFps === session.fps) {
      this.planFps = session.fps;
      return;
    }
    this.plan = scalePlan(this.plan, this.planFps / session.fps);
    this.planFps = session.fps;
    this.syncPointerTravels();
  }

  private syncPointerTravels(): void {
    this.pointerTravels = (this.plan?.beats ?? []).filter((b) => b.kind === "pointer").map((b) => b.travel);
  }
}

export const playhead = new Playhead();
setBeatGate((kind, key) => playhead.allowBeat(kind, key));
playhead.start();
