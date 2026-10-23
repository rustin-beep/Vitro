// host_route_coverage.test.mts —— 覆盖判据与白名单双向对账（hermetic fixture）。
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { check } from "./main.mts";
import { projectRoot } from "../../internal/capi.mts";

interface Fixture {
  /** 无实现且不在白名单（应红） */
  unwired?: string[];
  /** 无实现但登记白名单（应放行） */
  waived?: string[];
  /** 有实现却仍在白名单（应红：过期条目） */
  stale?: string[];
  aliasTarget?: string;
}

function fixture(opts: Fixture = {}): string {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "vitro-route-"));
  fs.mkdirSync(path.join(root, "scripts/moonbit"), { recursive: true });
  fs.mkdirSync(path.join(root, "moonbit/bytecode"), { recursive: true });
  fs.mkdirSync(path.join(root, "moonbit/host"), { recursive: true });

  const names = Array.from({ length: 100 }, (_, i) => `r${i}`);
  const routes = [...names, "aliasroute"];
  fs.writeFileSync(
    path.join(root, "moonbit/bytecode/host_func_id_gen.mbt"),
    routes.map((n) => `  "${n}" => 1,\n`).join("")
  );
  const missing = new Set([...(opts.unwired ?? []), ...(opts.waived ?? [])]);
  fs.writeFileSync(
    path.join(root, "moonbit/host/impl.mbt"),
    names
      .filter((n) => !missing.has(n))
      .map((n) => `pub fn host_${n}() -> Unit = ()\n`)
      .join("")
  );
  fs.writeFileSync(path.join(root, "moonbit/host/impl_test.mbt"), "pub fn host_ignored() -> Unit = ()\n");

  const vm = [...(opts.stale ?? []), ...(opts.waived ?? [])];
  fs.writeFileSync(
    path.join(root, "scripts/moonbit/host_route_rules.json"),
    JSON.stringify({ aliases: { aliasroute: opts.aliasTarget ?? "r0" }, vm_whitelist: vm })
  );
  return root;
}

test("真实仓库：全部路由有实现或已登记白名单", () => {
  const r = check(projectRoot());
  assert.equal(r.bad, 0, r.lines.join("\n"));
  assert.ok(r.total >= 100);
});

test("缺口：未实现且未白名单 → 红；别名目标缺失带提示", () => {
  // waived 项仅用于满足「vm_whitelist 非空」前置（r50 无实现且登记 → 放行）
  const r = check(fixture({ unwired: ["r5"], waived: ["r50"], aliasTarget: "r5" }));
  assert.equal(r.bad, 2);
  assert.ok(r.lines.some((l) => l.includes("未实现路由: r5")));
  assert.ok(r.lines.some((l) => l.includes("未实现路由: aliasroute") && l.includes("经别名 → r5")));
});

test("白名单双向：缺实现登记白名单放行；有实现仍在白名单 → 过期红", () => {
  assert.equal(check(fixture({ waived: ["r7"] })).bad, 0);
  const stale = check(fixture({ stale: ["r9"] }));
  assert.equal(stale.bad, 1);
  assert.match(stale.lines[0] ?? "", /过期白名单: r9/);
});

test("空 vm_whitelist fail loud", () => {
  const root = fixture();
  fs.writeFileSync(path.join(root, "scripts/moonbit/host_route_rules.json"), JSON.stringify({ aliases: {}, vm_whitelist: [] }));
  assert.throws(() => check(root), /vm_whitelist 为空/);
});
