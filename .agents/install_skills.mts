// Vitro Agent Skills 安装器——把 .agents/skills/ 下的项目专属 skill 装进各 AI 工具的 skill 目录。
// （#273 存量 Go 重写批 2026-10-25；原 install_skills.go，行为直译 + 自测件。）
//
// 用法（cwd 任意；脚本按自身位置定位同级 skills/）：
//
//	node .agents/install_skills.mts --list                    # 列出可装 skill 并做 frontmatter 校验
//	node .agents/install_skills.mts --all                     # 装到检测到用户目录的工具（用户级）
//	node .agents/install_skills.mts --tool claude             # 装到 ~/.claude/skills
//	node .agents/install_skills.mts --tool claude --scope project   # 装到 <仓库根>/.claude/skills
//	node .agents/install_skills.mts --tool zcode              # 装到 ~/.zcode/skills
//	node .agents/install_skills.mts --dest <dir>              # 装到任意目录（其他工具通用）
//	--force 覆盖已存在目标；默认跳过并提示。
//	--diff 逐文件比对源与安装副本（配合 --tool/--dest/--all 选目标），报告差异清单供升级决策——
//	        默认安装行为是「跳过已存在」（副本停在旧版），--force 是「整目录删了重拷」（丢本地演化），
//	        升级前先 --diff 看清两边差什么，把盲跳过/盲覆盖变成显式决策。报告工具不设红绿（恒 exit 0）。
//
// 注意：
//   - ZCode 用户无需安装：ZCode 直接扫描工作区 .agents/skills/。
//   - skill 格式为通用 Agent Skills 格式（目录 + SKILL.md + YAML frontmatter），不绑定具体工具；
//     安装物是普通目录复制（含 references/ 子目录），删除即卸载。
//   - 零第三方依赖；fail loud：SKILL.md 缺失 / frontmatter 缺 name 或 description /
//     name 与目录名不一致即整体 exit 1。
//   - 维护义务：改动对应流程或文档时连坐更新 SKILL.md；新增 skill 后跑一次 --list 确认校验绿。
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

interface Skill {
  name: string;
  dir: string;
  desc: string;
}

// fail loud：throw + main 顶层统一加前缀落 stderr + exit 1。对外行为与
// Go 版（os.Exit(1) + "[安装器] 错误:" 前缀）逐位一致；实现形态选 throw 是
// 为 fail 路径可被 node:test 直测（Go 测试无法覆盖 os.Exit 路径——登记的
// 有意口径演进）。
class InstallerError extends Error {}

function fail(format: string, ...args: unknown[]): never {
  // %q 按_go 版 fmt 语义渲染（带引号）——审阅修正：此前裸值替换使错误文案
  // 与 Go 版差一对引号（实锤：未知工具 "nosuch" vs nosuch）。
  const msg = format.replace(/%[vqsg]/g, () => {
    const a = args.shift();
    return typeof a === "string" ? '"' + a.replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"' : String(a);
  });
  throw new InstallerError(msg);
}

function homeDir(): string {
  try {
    return os.homedir();
  } catch (e) {
    return fail("无法定位用户主目录: %v", (e as Error).message);
  }
}

const META_LINE = /^([A-Za-z][\w-]*):[ \t]*(.+?)[ \t]*$/gm;

export function parseFrontmatterText(text0: string, srcLabel: string): Map<string, string> {
  // CRLF 兼容（2026-09-29 J9 证红抓出）：core.autocrlf=true 的 Windows clone
  // 工作区里 SKILL.md 是 CRLF，"---\r\n" 不匹配 "---\n" 前缀会误报缺
  // frontmatter——归一后再解析（.gitattributes 锁 .agents/** 为 LF 是双保险）。
  const text = text0.replaceAll("\r\n", "\n");
  if (!text.startsWith("---\n")) {
    fail("%s: SKILL.md 缺少 YAML frontmatter（--- 包头的 name/description）", srcLabel);
  }
  const end = text.indexOf("\n---", 4);
  if (end < 0) {
    fail("%s: frontmatter 未闭合", srcLabel);
  }
  const meta = new Map<string, string>();
  META_LINE.lastIndex = 0;
  for (const m of text.slice(4, end + 4).matchAll(META_LINE)) {
    meta.set(m[1]!, m[2]!);
  }
  return meta;
}

function parseFrontmatter(p: string): Map<string, string> {
  let b: string;
  try {
    b = fs.readFileSync(p, "utf8");
  } catch (e) {
    return fail("%s: 读取失败: %v", p, (e as Error).message);
  }
  return parseFrontmatterText(b, p);
}

export function discover(skillsDir: string): Skill[] {
  let ents: fs.Dirent[];
  try {
    ents = fs.readdirSync(skillsDir, { withFileTypes: true });
  } catch {
    return fail("skill 源目录不存在: %s", skillsDir);
  }
  const out: Skill[] = [];
  for (const e of ents) {
    if (!e.isDirectory()) continue;
    const f = path.join(skillsDir, e.name, "SKILL.md");
    if (!fs.existsSync(f)) {
      fail("%s: 缺 SKILL.md", e.name);
    }
    const meta = parseFrontmatter(f);
    if (meta.get("name") === undefined || meta.get("name") === "" || meta.get("description") === undefined || meta.get("description") === "") {
      fail("%s: frontmatter 缺 name 或 description", e.name);
    }
    if (meta.get("name") !== e.name) {
      fail("%s: frontmatter name=%q 与目录名不一致", e.name, meta.get("name"));
    }
    out.push({ name: e.name, dir: path.join(skillsDir, e.name), desc: meta.get("description")! });
  }
  if (out.length === 0) {
    fail("%s 下没有可安装的 skill", skillsDir);
  }
  out.sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
  return out;
}

function copyDir(src: string, dst: string): void {
  const walk = (dir: string): void => {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      const p = path.join(dir, e.name);
      const target = path.join(dst, path.relative(src, p));
      if (e.isDirectory()) {
        fs.mkdirSync(target, { recursive: true });
        walk(p);
      } else {
        fs.copyFileSync(p, target);
      }
    }
  };
  fs.mkdirSync(dst, { recursive: true });
  walk(src);
}

function installOne(s: Skill, dest: string, force: boolean): void {
  if (fs.existsSync(dest)) {
    if (!force) {
      console.log(`  跳过 ${s.name}（已存在: ${dest}；--force 可覆盖）`);
      return;
    }
    try {
      fs.rmSync(dest, { recursive: true });
    } catch (e) {
      fail("覆盖 %s 失败: %v", dest, (e as Error).message);
    }
  }
  try {
    copyDir(s.dir, dest);
  } catch (e) {
    fail("安装 %s 失败: %v", s.name, (e as Error).message);
  }
  console.log(`  已装 ${s.name} → ${dest}`);
}

// diffOne：逐文件比对源 skill 目录与安装副本，打印差异清单。
// 返回是否存在差异（报告工具，不设红绿——升级决策由人做）。
export function diffOne(s: Skill, dest: string): boolean {
  if (!fs.existsSync(dest)) {
    console.log(`  ${s.name}: 未安装 → ${dest}`);
    return true;
  }
  const list = (root: string): Map<string, string> => {
    const m = new Map<string, string>();
    const walk = (dir: string): void => {
      for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
        const p = path.join(dir, e.name);
        if (e.isDirectory()) {
          walk(p);
          continue;
        }
        m.set(path.relative(root, p).split(path.sep).join("/"), p);
      }
    };
    walk(root);
    return m;
  };
  const src = list(s.dir);
  const dst = list(dest);
  const keys = [...src.keys()].sort();
  const dstOnly = [...dst.keys()].filter((k) => !src.has(k)).sort();
  let diff = false;
  for (const k of keys) {
    const sp = src.get(k)!;
    const dp = dst.get(k);
    if (dp === undefined) {
      console.log(`  ${s.name}: +${k}（源新增，重装可得）`);
      diff = true;
      continue;
    }
    const sb = fs.readFileSync(sp);
    const db = fs.readFileSync(dp);
    if (!sb.equals(db)) {
      console.log(`  ${s.name}: ~${k}（内容不同，源 ${sb.length} 字节 / 副本 ${db.length} 字节）`);
      diff = true;
    }
  }
  for (const k of dstOnly) {
    console.log(`  ${s.name}: *${k}（仅副本所有——本地演化，--force 重装会丢失）`);
    diff = true;
  }
  if (!diff) {
    console.log(`  ${s.name}: 一致`);
  }
  return diff;
}

// ─── Go flag 语义的小解析器（bool: 不吃值、=值 fail loud；value: -k v / -k=v）──
const BOOL_FLAGS = new Set(["-list", "--list", "-all", "--all", "-force", "--force", "-diff", "--diff"]);
const VALUE_FLAGS = new Set(["-tool", "--tool", "-scope", "--scope", "-dest", "--dest"]);

function parseFlags(argv: string[]): { has: (n: string) => boolean; value: (n: string) => string | undefined } {
  const bools = new Set<string>();
  const values = new Map<string, string>();
  const args: string[] = [];
  let i = 0;
  for (; i < argv.length; i++) {
    const a = argv[i]!;
    // Go flag：`--` 终止解析且**被吃掉**（2026-10-25 审阅修正：此前 break 停在
    // "--" 上、slice(i) 把它带进位置参数——与 Go Args() 语义差一个元素）。
    if (a === "--") {
      i++;
      break;
    }
    if (!a.startsWith("-")) break; // Go flag：第一个位置参数停止
    const eq = a.indexOf("=");
    const name = eq >= 0 ? a.slice(0, eq) : a;
    if (BOOL_FLAGS.has(name)) {
      if (eq >= 0) fail("布尔 flag %s 不接受值（收到 %s）", name, a);
      bools.add(name);
    } else if (VALUE_FLAGS.has(name)) {
      if (eq >= 0) {
        values.set(name, a.slice(eq + 1));
      } else {
        const v = argv[i + 1];
        if (v === undefined) fail("%s 缺值", name);
        values.set(name, v);
        i++;
      }
    } else {
      fail("flag provided but not defined: %s", name);
    }
  }
  args.push(...argv.slice(i));
  void args; // 本工具不消费位置参数；保留收集以对齐 Go flag 语义（供未来子命令）
  return { has: (n) => bools.has(n), value: (n) => values.get(n) };
}

function main(): void {
  try {
    runMain();
  } catch (e) {
    if (e instanceof InstallerError) {
      process.stderr.write("[安装器] 错误: " + e.message + "\n");
      process.exit(1);
    }
    throw e;
  }
}

function runMain(): void {
  const self = path.dirname(fileURLToPath(import.meta.url));
  const repoRoot = path.dirname(self);
  const skillsDir = path.join(self, "skills");

  const list = parseFlags(process.argv.slice(2));
  const fl = list.has("-list") || list.has("--list");
  const all = list.has("-all") || list.has("--all");
  const force = list.has("-force") || list.has("--force");
  const diff = list.has("-diff") || list.has("--diff");
  const tool = list.value("-tool") ?? list.value("--tool") ?? "";
  const scope = list.value("-scope") ?? list.value("--scope") ?? "user";
  const dest = list.value("-dest") ?? list.value("--dest") ?? "";

  const userSkills = (name: string): string => path.join(homeDir(), "." + name, "skills");
  const tools: [string, string][] = [
    ["claude", userSkills("claude")],
    ["zcode", userSkills("zcode")],
  ];

  const skills = discover(skillsDir);

  console.log(`Vitro 项目 skills（${skills.length} 个，frontmatter 校验通过）:`);
  for (const s of skills) {
    console.log(`  - ${s.name}: ${s.desc}`);
  }
  if (fl) return;
  if (!all && tool === "" && dest === "") {
    if (diff) {
      fail("--diff 需要目标：--all（自动检测）/ --tool claude|zcode / --dest <dir>");
    }
    console.log("\n未指定目标: 用 --all（自动检测）/ --tool claude|zcode / --dest <dir>。ZCode 用户无需安装（工作区自动扫描）。");
    return;
  }

  const targets: { label: string; dir: string }[] = [];
  if (dest !== "") {
    targets.push({ label: "dest", dir: dest });
  } else {
    if (tool !== "") {
      const userDir = tools.find(([n]) => n === tool)?.[1];
      if (userDir === undefined) {
        fail("未知工具 %q（可选: claude, zcode）", tool);
      }
      if (scope === "user") {
        targets.push({ label: tool + "(user)", dir: userDir });
      } else {
        targets.push({ label: tool + "(project)", dir: path.join(repoRoot, "." + tool, "skills") });
      }
    }
    if (all) {
      for (const [name, userDir] of tools) {
        const parent = path.dirname(userDir);
        if (fs.existsSync(parent) && fs.statSync(parent).isDirectory()) {
          targets.push({ label: name + "(user)", dir: userDir });
        }
      }
    }
    if (targets.length === 0) {
      fail("--all 未检测到任何工具用户目录；请显式 --tool 或 --dest");
    }
  }

  const action = diff ? "比对" : "安装到";
  for (const t of targets) {
    console.log(`\n${action} ${t.label}（${t.dir}）:`);
    let anyDiff = false;
    for (const s of skills) {
      const d = path.join(t.dir, s.name);
      if (diff) {
        if (diffOne(s, d)) anyDiff = true;
        continue;
      }
      installOne(s, d, force);
    }
    if (diff && anyDiff) {
      console.log("  → 更新 = --force 重装（丢失「*」标记的本地演化）；保留 = 不动");
    }
  }
  if (all) {
    console.log("\n提示: ZCode 本身直接扫描工作区 .agents/skills/，无需安装到 ~/.zcode 即可生效。");
  }
}

// 主模块守卫：TS 直跑没有 Go 的 main 包隔离——被 node:test import 时不得
// 执行安装流程（Go 版 main() 仅在 go run/build 入口生效，此处为同语义复刻）。
if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  main();
}
