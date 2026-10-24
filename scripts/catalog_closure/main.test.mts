// catalog_closure 闸的 J9 埋雷证红测试（#256——五规则各注入一路突变，
// 证「闸真的会红」；绿态锚用真实真源数据走一遍全绿）。
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { checkClosure, scanProduction } from "./main.mts" with { type: "file" };

interface ArmEntry {
  name: string;
  code: number;
}
interface CatalogEntry {
  code: number;
}
interface Rules {
  prod_no_card_whitelist: Record<string, string>;
  card_no_prod_whitelist: Record<string, string>;
}

const mkCodes = (arms: ArmEntry[]): { arms: ArmEntry[] } => ({ arms });
const mkCatalog = (codes: number[]): { entries: CatalogEntry[] } => ({
  entries: codes.map((code) => ({ code })),
});
const mkRules = (): Rules => ({
  prod_no_card_whitelist: {},
  card_no_prod_whitelist: {},
});

test("绿态锚：三码对齐（生产=卡=臂）零违例", () => {
  const codes = mkCodes([
    { name: "E1001_A", code: 1001 },
    { name: "W1002_B", code: 1002 },
  ]);
  const catalog = mkCatalog([1001, 1002]);
  const prod = new Map([
    ["E1001", ["x.mbt:1"]],
    ["W1002", ["x.mbt:2"]],
  ]);
  assert.deepEqual(checkClosure(codes, catalog, mkRules(), prod), []);
});

test("R1 埋雷：引擎生产码无卡即红", () => {
  const codes = mkCodes([{ name: "E1001_A", code: 1001 }]);
  const catalog = mkCatalog([]); // 卡缺失
  const prod = new Map([["E1001", ["lexer/x.mbt:9"]]]);
  const viol = checkClosure(codes, catalog, mkRules(), prod);
  assert.ok(viol.some((v) => v.rule === "R1-forward" && v.message.includes("E1001")));
});

test("R2 埋雷：卡零生产点即红（退役面）", () => {
  const codes = mkCodes([{ name: "E1001_A", code: 1001 }]);
  const catalog = mkCatalog([1001]);
  const prod = new Map(); // 零生产点
  const viol = checkClosure(codes, catalog, mkRules(), prod);
  assert.ok(viol.some((v) => v.rule === "R2-reverse" && v.message.includes("E1001")));
});

test("R3 埋雷：同号异前缀双臂撞键即红", () => {
  const codes = mkCodes([
    { name: "E3086_BoundsArray", code: 3086 },
    { name: "W3086_FutureWarn", code: 3086 },
  ]);
  const catalog = mkCatalog([3086]);
  const prod = new Map([["E3086", ["vm/x.mbt:1"]], ["W3086", ["vm/x.mbt:2"]]]);
  const viol = checkClosure(codes, catalog, mkRules(), prod);
  assert.ok(viol.some((v) => v.rule === "R3-prefix" && v.message.includes("3086")));
});

test("R4 埋雷：幽灵卡（码无臂）即红", () => {
  const codes = mkCodes([{ name: "E1001_A", code: 1001 }]);
  const catalog = mkCatalog([1001, 9999]); // 9999 无臂
  const prod = new Map([["E1001", ["x.mbt:1"]]]);
  const viol = checkClosure(codes, catalog, mkRules(), prod);
  assert.ok(viol.some((v) => v.rule === "R4-arm" && v.message.includes("9999")));
});

test("R5 埋雷：白名单僵尸条目（零命中）即红", () => {
  const codes = mkCodes([{ name: "E1001_A", code: 1001 }]);
  const catalog = mkCatalog([1001]);
  const prod = new Map([["E1001", ["x.mbt:1"]]]);
  const rules: Rules = {
    prod_no_card_whitelist: { E3099: "已清偿的债（生产点已消失）" },
    card_no_prod_whitelist: { E3098: "已清偿的债（卡已删）" },
  };
  const viol = checkClosure(codes, catalog, rules, prod);
  assert.ok(viol.filter((v) => v.rule === "R5-stale-whitelist").length === 2);
});

test("白名单豁免通道：带 reason 条目不红（但零命中红）", () => {
  const codes = mkCodes([{ name: "E0_Unknown", code: 0 }]);
  const catalog = mkCatalog([0]);
  const prod = new Map(); // E0 数值构造盲区
  const rules: Rules = {
    prod_no_card_whitelist: {},
    card_no_prod_whitelist: { E0: "ErrorCode::Unknown 数值构造盲区" },
  };
  assert.deepEqual(checkClosure(codes, catalog, rules, prod), []);
});

test("scanProduction 形态锚：变体引用与字面量双形态各命中，排除面不误收", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "catcl-"));
  try {
    fs.mkdirSync(path.join(dir, "moonbit", "vm"), { recursive: true });
    fs.writeFileSync(
      path.join(dir, "moonbit", "vm", "a.mbt"),
      [
        "fn f() { report(E3086_BoundsArray) }",
        'self.trap(msg, 0, 0, code="E3088")',
      ].join("\n"),
    );
    // 排除面：_gen.mbt 与 wbtest 不收
    fs.writeFileSync(
      path.join(dir, "moonbit", "vm", "b_gen.mbt"),
      "E3099_ShouldNotCount",
    );
    fs.writeFileSync(
      path.join(dir, "moonbit", "vm", "c_wbtest.mbt"),
      '"E3098"',
    );
    const prod = scanProduction(dir);
    assert.deepEqual([...prod.keys()].sort(), ["E3086", "E3088"]);
    assert.ok((prod.get("E3086") ?? [])[0]?.endsWith("a.mbt:1"));
    assert.ok((prod.get("E3088") ?? [])[0]?.endsWith("a.mbt:2"));
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});
