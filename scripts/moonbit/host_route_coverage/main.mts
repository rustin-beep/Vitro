#!/usr/bin/env node
// host_route_coverage：110 路由 ↔ host 实现覆盖闸（#273 存量 Go 重写批）。
//
// 判据：路由表每个名字必须解析到 moonbit/host 下的 `pub fn host_<name>`
// （或经 host_route_rules.json 的 aliases 命中实现名）；vm_whitelist 豁免但
// 双向对账（白名单条目一旦有实现即红，逼清理）。
//
//   node scripts/moonbit/host_route_coverage/main.mts -check
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { projectRoot } from "../../internal/capi.mts";

const RE_ROUTE = /"([a-z_][a-z_0-9]*)"/g;
const RE_IMPL = /pub fn host_([a-z_][a-z_0-9]*)/g;

interface Rules {
  aliases: Record<string, string>;
  vm_whitelist: string[];
}

export interface CheckResult {
  lines: string[];
  bad: number;
  total: number;
}

export function check(root: string): CheckResult {
  let rules: Rules;
  try {
    rules = JSON.parse(fs.readFileSync(path.join(root, "scripts/moonbit/host_route_rules.json"), "utf8")) as Rules;
  } catch (e) {
    throw new Error(`读规则失败：${e instanceof Error ? e.message : String(e)}`);
  }
  if (!Array.isArray(rules.vm_whitelist) || rules.vm_whitelist.length === 0) {
    throw new Error("vm_whitelist 为空——fail loud（空集不得绿）");
  }

  let genRaw: string;
  try {
    genRaw = fs.readFileSync(path.join(root, "moonbit/bytecode/host_func_id_gen.mbt"), "utf8");
  } catch (e) {
    throw new Error(`读路由表失败：${e instanceof Error ? e.message : String(e)}`);
  }
  const routes = new Set<string>();
  for (const m of genRaw.matchAll(RE_ROUTE)) routes.add(m[1] ?? "");
  if (routes.size < 100) throw new Error(`路由名解析异常（${routes.size} 个 < 100）——形态变更须先改本闸`);

  const hostDir = path.join(root, "moonbit/host");
  let hostFiles: string[];
  try {
    hostFiles = fs
      .readdirSync(hostDir)
      .filter((n) => n.endsWith(".mbt"))
      .map((n) => path.join(hostDir, n));
  } catch {
    hostFiles = [];
  }
  if (hostFiles.length === 0) throw new Error("host 包源码为空");
  const impls = new Set<string>();
  for (const f of hostFiles) {
    if (path.basename(f).includes("test")) continue;
    const data = fs.readFileSync(f, "utf8");
    for (const m of data.matchAll(RE_IMPL)) impls.add(m[1] ?? "");
  }

  const vmSet = new Set(rules.vm_whitelist);
  const names = [...routes].sort();
  const lines: string[] = [];
  let bad = 0;
  for (const n of names) {
    const key = rules.aliases?.[n] ?? n;
    const implemented = impls.has(key);
    const whitelisted = vmSet.has(n) || vmSet.has(key);
    if (implemented) {
      if (whitelisted) {
        lines.push(`过期白名单: ${n} 已有实现（host_${key}）——须从 vm_whitelist 清理`);
        bad++;
      }
      continue;
    }
    if (whitelisted) continue;
    const hint = key !== n ? `（经别名 → ${key}，该名亦无实现）` : "";
    lines.push(`未实现路由: ${n}${hint}`);
    bad++;
  }
  return { lines, bad, total: names.length };
}

function fatal(msg: string): never {
  process.stderr.write("host_route_coverage: " + msg + "\n");
  process.exit(2);
}

const invokedDirectly =
  process.argv[1] !== undefined && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invokedDirectly) {
  // -check 与无参同义（与 Go 形态一致：仅作调用形态统一）
  let r: CheckResult;
  try {
    r = check(projectRoot());
  } catch (e) {
    fatal(e instanceof Error ? e.message : String(e));
  }
  for (const l of r.lines) console.log(l);
  if (r.bad > 0) fatal(`host_route_coverage: ${r.bad} 条路由无实现或白名单过期`);
  console.log(`host_route_coverage: OK（${r.total} 条路由全部有实现或已登记 vm 白名单）`);
}
