// D3 打包形态验证（2026-11-15 固化——README 下批清单「打包形态验证」项）：
// proton_cli package --release --format app 全链编排 + 五断言 + finally 还原。
//
// 为什么需要「镜像布局」workaround（上游边界实测）：proton_cli 0.6.0 的
// package 要求 bundle 输入在 base_dir（desktop/）内——本壳 frontend 跨目录
// （../demo，demo 与 desktop 并列），直打包即红：
//   error: bundle input must stay inside base_dir: D:\...\demo\dist
// 且 facade asset 串是**双语境镜像设计**（facade_entry.mbt resolve_asset_path：
// 相对路径 join runtime_resource_dir()）：dev/直跑形态按 cwd=desktop/ 解析
// `../demo/dist`；打包形态按 exe 旁 Resources/ 解析——跨目录打破镜像。
// 处方 = 打包期镜像：拷 demo/dist → desktop/web/dist + asset 临时改
// `web/dist/index.html`（Resources 相对）→ package → finally 还原双文件。
// 与 smoke.mts 形态 C 同款「临时改 + finally 还原 + 脏态自检」骨架。
//
// 五断言（fail loud，逐条 stderr 标注后 rc=1）：
//   pkg-plan   产物存在（vitro-desktop.exe + cef_process.exe）
//   pkg-entry  前端镜像装配就位（Resources/web/dist/index.html）
//   pkg-cdp    免四件套直跑 + CDP env 钉端口可达（/json/version 指纹——
//              release 产物 + env 翻转 debug 的 facade 语义在打包产物复验）
//   pkg-page   page target = https://proton.localhost/index.html + title
//              「Vitro · C 执行观察台」（镜像 asset 真装载，非白页）
//   pkg-e2e    页内驱动完整采集：transport=ipc + 编译 ✓ 运行 ✓ golden ✓
//              （引擎 native 同进程直调链在打包形态全通）
//
// 已知坑（内建处置）：
//   - TEMP 沙箱（agent 会话内工作区 exe 建 %TEMP%\proton-cef-* 拒绝访问）：
//     TEMP/TMP 覆写 _build/tmp（mkdir 兜底；正常环境无害——README 坑表同款处方）
//   - 直跑须 node spawn（MSYS bash 直 spawn 本产物 exe 报伪加载错——README 坑表）
//   - 免四件套验证点：打包内嵌元数据生效——env **不带** PROTON_RUNTIME_ROOT/
//     PROTON_HELPER_PATH/PROTON_PROJECT_CONFIG（只给 CDP 端口与 TEMP 处方）
//
// 用法：node tools/package_check.mts <cdpPort>（cwd=desktop/；demo/dist 须先
// 构建——缺失即 exit 2 fail loud）。退出码：0=全过；1=断言失败；2=用法/环境。
import { spawn, spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import process from "node:process";

const PORT = process.argv[2] ?? "";
if (!/^\d+$/.test(PORT) || Number(PORT) < 1024) {
  process.stderr.write("用法: node tools/package_check.mts <cdpPort>（1024..65535）\n");
  process.exit(2);
}

const MAIN = "app/main.mbt";
const CONF = "proton.project.json";
const MIRROR_DIR = "web";
const ASSET_DEV = '"../demo/dist/index.html"';
const ASSET_PKG = '"web/dist/index.html"';
const OUT_DIR = path.join("dist", "vitro-desktop");

let failures = 0;
function check(name: string, ok: boolean, detail: string): void {
  process.stderr.write(`${ok ? "PASS" : "FAIL"} ${name}: ${detail}\n`);
  if (!ok) failures++;
}

// ── 脏态自检（上次中断残留 fail loud——smoke 同款）────────────────────
const mainNow = fs.readFileSync(MAIN, "utf8");
const confNow = JSON.parse(fs.readFileSync(CONF, "utf8")) as { frontend?: { path?: string } };
if (mainNow.includes(ASSET_PKG) || confNow.frontend?.path !== "../demo") {
  process.stderr.write(
    `package_check: 脏态检出（${MAIN} 含 ${ASSET_PKG} 或 ${CONF} frontend.path 非 ../demo）——上次中断残留，先还原再跑\n`,
  );
  process.exit(2);
}
if (!fs.existsSync(path.join("..", "demo", "dist", "index.html"))) {
  process.stderr.write("package_check: demo/dist 缺（先 cd demo && npm run build——含 wasm.wasm/langpack/algorithms 资产）\n");
  process.exit(2);
}

// ── 前置：原生构建态确认（package 内部会 moon run --build-only，独立跑一次保失败可归因）──
console.log(`[pkg] 镜像拷贝 demo/dist -> ${MIRROR_DIR}/dist`);
fs.rmSync(MIRROR_DIR, { recursive: true, force: true });
fs.mkdirSync(MIRROR_DIR, { recursive: true });
fs.cpSync(path.join("..", "demo", "dist"), path.join(MIRROR_DIR, "dist"), { recursive: true });

let pkgPid: number | null = null;
let appPid = -1;

try {
  // 临时改双文件（finally 还原）
  fs.writeFileSync(MAIN, mainNow.replace(ASSET_DEV, ASSET_PKG));
  const conf = JSON.parse(fs.readFileSync(CONF, "utf8")) as {
    frontend: { path: string; dev_url: string; before_dev: string; before_build?: string; dist: string };
  };
  delete conf.frontend.before_build;
  conf.frontend.path = MIRROR_DIR;
  fs.writeFileSync(CONF, JSON.stringify(conf, null, 2) + "\n");

  console.log("[pkg] proton_cli package --release --format app");
  const pkg = spawnSync("proton_cli", ["package", "--release", "--format", "app"], {
    maxBuffer: 64 * 1024 * 1024,
    timeout: 600_000,
  });
  const pkgOut = ((pkg.stdout ?? "").toString() + (pkg.stderr ?? "").toString()).trim();
  if ((pkg.status ?? -1) !== 0) {
    check("pkg-plan", false, `package rc=${String(pkg.status)}：${pkgOut.slice(-300)}`);
    process.exit(1);
  }
  const exe = path.resolve(OUT_DIR, "vitro-desktop.exe");
  check(
    "pkg-plan",
    fs.existsSync(exe) && fs.existsSync(path.join(OUT_DIR, "cef_process.exe")),
    `exe=${fs.existsSync(exe)}（${pkgOut.split("\n").filter((l) => l.includes("Packaged")).join(" ") || "无 Packaged 行"}）`,
  );
  check("pkg-entry", fs.existsSync(path.join(OUT_DIR, "Resources", MIRROR_DIR, "dist", "index.html")), "Resources/web/dist/index.html");

  // 免四件套直跑（node spawn + TEMP 处方 + CDP env）
  fs.mkdirSync(path.join("_build", "tmp"), { recursive: true });
  const child = spawn(exe, [], {
    cwd: path.dirname(exe),
    env: {
      ...process.env,
      PROTON_REMOTE_DEBUGGING_PORT: PORT,
      TEMP: path.resolve(path.join("_build", "tmp")),
      TMP: path.resolve(path.join("_build", "tmp")),
    },
    detached: true,
    stdio: "ignore",
  });
  appPid = child.pid ?? -1;
  child.unref();
  pkgPid = appPid;

  // 等 CDP（release 冷启 + 临时 storage 初始化——首跑实测 ~5s，给 45s）
  let cdpOk = false;
  let pageOk = false;
  let e2eOk = false;
  let pageDetail = "";
  let e2eDetail = "";
  for (let i = 0; i < 45 && !e2eOk; i++) {
    await new Promise((r) => setTimeout(r, 1000));
    if (!cdpOk) {
      const v = spawnSync(process.execPath, ["tools/cdp_probe.mts", PORT], { maxBuffer: 8 * 1024 * 1024, timeout: 15_000 });
      const t = (v.stdout ?? "").toString();
      if (v.status === 0 && t.includes('"Protocol-Version"')) cdpOk = true;
      if (cdpOk) {
        const m = t.match(/"type":\s*"page",[\s\S]{0,200}?"url":\s*"([^"]+)"/);
        const mt = t.match(/"type":\s*"page",[\s\S]{0,300}?"title":\s*"([^"]*)"/);
        pageDetail = `url=${m?.[1] ?? "?"} title=${mt?.[1] ?? "?"}`;
        pageOk = (m?.[1] ?? "").startsWith("https://proton.localhost/") && (mt?.[1] ?? "").includes("Vitro");
      }
    }
    if (cdpOk && !e2eOk) {
      const r = spawnSync(process.execPath, ["tools/cdp_probe.mts", PORT, "@tools/page/demo_run.js"], {
        maxBuffer: 8 * 1024 * 1024,
        timeout: 60_000,
      });
      const t = (r.stdout ?? "").toString();
      const em = t.match(/"eval":\s*"(.*)"\n/);
      const emRaw = em?.[1];
      if (emRaw !== undefined) {
        try {
          const ev = JSON.parse(emRaw.replaceAll('\\"', '"').replaceAll("\\\\", "\\")) as Record<string, string>;
          e2eDetail = `transport=${ev["transport"]} status=${ev["status"]}`;
          e2eOk = ev["transport"] === "ipc" && (ev["status"] ?? "").includes("golden ✓");
        } catch {
          e2eDetail = `eval 解析失败：${emRaw.slice(0, 80)}`;
        }
      }
    }
  }
  check("pkg-cdp", cdpOk, cdpOk ? "/json/version 指纹可达（release+env 翻转在打包产物复验 ✓）" : `端口 ${PORT} 45s 未就绪`);
  check("pkg-page", pageOk, pageDetail || "page target 未出现");
  check("pkg-e2e", e2eOk, e2eDetail || "页内采集未完成");
} finally {
  // 杀树（含 cef_process 子进程）
  if (pkgPid !== null && pkgPid > 0) {
    spawnSync("taskkill", ["/F", "/T", "/PID", String(pkgPid)], { stdio: "ignore" });
  }
  // 还原双文件（git checkout——两文件均受 git 管，比手工重写稳：零格式漂移）
  // + 清理镜像与产物。git 不可用（未检出形态）时回落 mainNow 原文回写。
  try {
    const g = spawnSync("git", ["checkout", "--", MAIN, CONF], { stdio: "ignore" });
    if ((g.status ?? -1) !== 0) fs.writeFileSync(MAIN, mainNow);
    if ((g.status ?? -1) !== 0) {
      throw new Error("git checkout 失败且仅 main.mbt 原文回写成功——proton.project.json 须手工核对");
    }
  } catch (e) {
    process.stderr.write(`package_check: 还原异常（手工核对 ${MAIN}/${CONF}——${e instanceof Error ? e.message : String(e)}）\n`);
    failures++;
  }
  fs.rmSync(MIRROR_DIR, { recursive: true, force: true });
  console.log("[pkg] 还原双文件 + 清理镜像/产物完成");
}

process.stderr.write(failures === 0 ? "package_check: 5 断言全过 ✓\n" : `package_check: ${failures} 断言失败\n`);
process.exit(failures === 0 ? 0 : 1);
