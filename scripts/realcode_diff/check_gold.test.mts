// check_gold 闸红绿矩阵：合规绿 + 九类 fail-loud 形态（子进程跑 CLI，验 exit 2）。
import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, writeFileSync, rmSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const script = path.join(here, "main.mts");

const ENTRY = {
  clang_ok: true,
  gcc_ok: true,
  vitro_errs: 0,
  vitro_warns: 0,
  codes: {},
  layer: "ok",
  run: "",
};

function meta(total: number, bothGreen: number): Record<string, unknown> {
  return {
    source_fork: "fork",
    source_commit: "commit",
    total,
    buckets: { clang_red: 0, both_green: bothGreen, vitro_red: 0 },
  };
}

function fixture(): string {
  const root = mkdtempSync(path.join(tmpdir(), "rc-check-"));
  const rd = path.join(root, "scripts", "realcode_diff");
  mkdirSync(path.join(rd, "corpus", "fx"), { recursive: true });
  writeFileSync(path.join(rd, "corpus", "fx", "a.c"), "");
  writeFileSync(
    path.join(rd, "gold_signatures.json"),
    JSON.stringify({ _meta: meta(1, 1), files: { "sig.c": ENTRY } }),
  );
  writeFileSync(path.join(rd, "gold_fx.json"), JSON.stringify({ _meta: meta(1, 1), files: { "a.c": ENTRY } }));
  writeFileSync(
    path.join(rd, "corpora.json"),
    JSON.stringify({
      corpora: { fx: { gold: "gold_fx.json", license: "MIT", upstream_commit: "x", total: 1 } },
    }),
  );
  return root;
}

function run(root: string): { status: number; out: string; err: string } {
  const p = spawnSync(process.execPath, ["--experimental-strip-types", script, "-check"], {
    encoding: "utf8",
    cwd: root,
    env: { ...process.env, VITRO_ROOT: root },
  });
  return { status: p.status ?? -1, out: p.stdout ?? "", err: p.stderr ?? "" };
}

interface GoldFixture {
  _meta: { total: number; buckets: Record<string, number>; [k: string]: unknown };
  files: Record<string, Record<string, unknown>>;
}

interface CorporaFixture {
  corpora: Record<
    string,
    { gold: string; license: string; upstream_commit: string; total: number; license_file?: string; [k: string]: unknown }
  >;
}

function mutateGold(root: string, fn: (g: GoldFixture) => void): void {
  const p = path.join(root, "scripts", "realcode_diff", "gold_fx.json");
  const g = JSON.parse(readFileSync(p, "utf8")) as GoldFixture;
  fn(g);
  writeFileSync(p, JSON.stringify(g));
}

function mutateCorpora(root: string, fn: (g: CorporaFixture) => void): void {
  const p = path.join(root, "scripts", "realcode_diff", "corpora.json");
  const g = JSON.parse(readFileSync(p, "utf8")) as CorporaFixture;
  fn(g);
  writeFileSync(p, JSON.stringify(g));
}

test("合规绿：两金样本 + 登记表三向一致 → exit 0", () => {
  const root = fixture();
  const r = run(root);
  assert.equal(r.status, 0, r.err);
  assert.match(r.err, /gold_fx\.json 合规 OK: 1 文件条目/);
  assert.match(r.err, /金样本多文件扫描完成: 2 个文件、2 条目/);
  rmSync(root, { recursive: true, force: true });
});

const redCases: Array<{ name: string; apply: (root: string) => void; needle: RegExp }> = [
  {
    name: "码计数求和失账（ΣE != vitro_errs）",
    apply: (root) =>
      mutateGold(root, (g) => {
        g.files["a.c"] = { ...ENTRY, vitro_errs: 2, codes: { E2005: 1 } };
      }),
    needle: /求和失账：Σ\(E码\)=1 != vitro_errs=2/,
  },
  {
    name: "诊断文案透传（schema 白名单外键）",
    apply: (root) =>
      mutateGold(root, (g) => {
        g.files["a.c"] = { ...ENTRY, message: "leak" };
      }),
    needle: /未知键 "message".*疑透传诊断文案/,
  },
  {
    name: "码形态非法",
    apply: (root) =>
      mutateGold(root, (g) => {
        g.files["a.c"] = { ...ENTRY, codes: { BAD: 1 } };
      }),
    needle: /键非诊断码形态/,
  },
  {
    name: "_meta.total 与 files 计数不符",
    apply: (root) =>
      mutateGold(root, (g) => {
        g._meta.total = 2;
      }),
    needle: /_meta\.total 2 != files 计数 1/,
  },
  {
    name: "_meta.buckets 与重算不符",
    apply: (root) =>
      mutateGold(root, (g) => {
        g._meta.buckets.both_green = 0;
      }),
    needle: /_meta\.buckets\.both_green = 0 != files 重算 1/,
  },
  {
    name: "语料 unit 漏冻（存在但不在金样本）",
    apply: (root) => {
      writeFileSync(path.join(root, "scripts", "realcode_diff", "corpus", "fx", "b.c"), "");
    },
    needle: /语料 unit fx\/b\.c 不在金样本 gold_fx\.json 键集（漏冻）/,
  },
  {
    name: "金样本僵尸条目（键无对应语料）",
    apply: (root) =>
      mutateGold(root, (g) => {
        g.files["b.c"] = ENTRY;
      }),
    needle: /键 "b\.c" 无对应语料（僵尸条目）/,
  },
  {
    name: "corpora.total 与实际 units 不符",
    apply: (root) =>
      mutateCorpora(root, (g) => {
        const fx = g.corpora["fx"];
        if (fx === undefined) throw new Error("fixture 缺 fx");
        fx.total = 2;
      }),
    needle: /corpora\.fx\.total = 2 != 实际 units 1/,
  },
  {
    name: "license_file 悬空",
    apply: (root) =>
      mutateCorpora(root, (g) => {
        const fx = g.corpora["fx"];
        if (fx === undefined) throw new Error("fixture 缺 fx");
        fx.license_file = "corpus/fx/LICENSE";
      }),
    needle: /license_file 不存在/,
  },
  {
    name: "登记语料僵尸（目录不存在）",
    apply: (root) =>
      mutateCorpora(root, (g) => {
        g.corpora.ghost = { gold: "gold_fx.json", license: "MIT", upstream_commit: "x", total: 1 };
      }),
    needle: /登记的语料批 ghost 目录不存在（僵尸登记）/,
  },
  {
    name: "语料目录悬空（未登记）",
    apply: (root) => {
      mkdirSync(path.join(root, "scripts", "realcode_diff", "corpus", "unreg"), { recursive: true });
    },
    needle: /语料批 unreg 存在但未在 corpora\.json 登记（悬空）/,
  },
  {
    name: "corpora.gold 指向的金样本缺失",
    apply: (root) =>
      rmSync(path.join(root, "scripts", "realcode_diff", "gold_fx.json"), { force: true }),
    needle: /gold 指向的金样本不存在/,
  },
];

test("check_gold 红矩阵：任一失守 exit 2 且文案点名", async (t) => {
  for (const c of redCases) {
    await t.test(c.name, () => {
      const root = fixture();
      c.apply(root);
      const r = run(root);
      assert.equal(r.status, 2, `应 exit 2，实得 ${r.status}\n${r.err}`);
      assert.match(r.err, c.needle);
      rmSync(root, { recursive: true, force: true });
    });
  }
});
