// demo_smoke 协议契约常量（独立模块：单测导入不得触发 main.mts 顶层的产物检查）。
// ArraySnapshot 必填键清单（PR #521 审阅 P2-2）：与生成字段表
// `moonbit/bindings/ts/fields.mjs` 和 demo DTO `demo/js/types.ts` 三向对账
// （main.test.mts）——wire 新增字段漏收即红。
export const ARRAY_SNAPSHOT_KEYS = ["name", "element_ty", "elements", "truncated", "dims"] as const;
