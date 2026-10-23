#!/usr/bin/env node
// diff_gate —— 差分对拍驱动统一入口（#273 差分族重构批）。
//
// 族 A 五个 target 共用 internal/diffgate.mts 的骨架，本入口只做 target 分发。
// clang_direct **不在此族**（活真值源 + stdin 双通道 + known 白名单，性质不同），
// 单独迁移。
//
// 用法：
//   node scripts/diff_gate/main.mts <target> <corpus_dir> [--golden|--freeze-mb|--selftest]
//
//   target = lexer | parser | typeck | codegen | vm
//
// 三模式语义见 internal/diffgate.mts 头注。CI 双轨期仍跑 Go 版驱动，本入口
// 为对拍期并存形态。
import { pathToFileURL } from "node:url";
import path from "node:path";
import { runGate } from "../internal/diffgate.mts";
import { makeFail } from "../internal/genio.mts";
import { lexerTarget } from "./targets/lexer.mts";
import { parserTarget } from "./targets/parser.mts";
import { typeckTarget } from "./targets/typeck.mts";
import { vmTarget } from "./targets/vm.mts";
import type { DiffTarget } from "../internal/diffgate.mts";

/** 入口用法错的出口：exit 2（与 target 的判红码 1 分流）。 */
function usageFail(msg: string): never {
  return makeFail("diff_gate: ", 2)(msg);
}

const TARGETS: Record<string, DiffTarget> = {
  lexer: lexerTarget,
  typeck: typeckTarget,
  parser: parserTarget,
  vm: vmTarget,
};

const NAMES = Object.keys(TARGETS);

export function main(): void {
  const argv = process.argv.slice(2);
  const which = argv[0];
  if (which === undefined) {
    usageFail(
      `用法: node scripts/diff_gate/main.mts <target> <corpus_dir> [flags]（target: ${NAMES.join(" / ")}）`,
    );
  }
  const target = TARGETS[which];
  if (target === undefined) {
    usageFail(`未知 target ${JSON.stringify(which)}（可用: ${NAMES.join(" / ")}）`);
  }
  // target 判红走它自己的 fail（exit 1）；runGate 内部的用法错由它自己 fail
  runGate(target, argv.slice(1), usageFail);
}

// 入口守卫：被 node:test import 时只取导出，不落盘
if (
  process.argv[1] !== undefined &&
  pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url
) {
  main();
}
