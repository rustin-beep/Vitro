// gen_api_help 规则真相源（#67 api help 生成器化，2026-10-11）。
// 修改本文件后再生下游 .json：jsonmbt build --pretty 本文件（禁手改 .json）。
// 分工：方法清单与 params 形状**不在本表**——权威源 = gateway dispatch
// （protocol.mbt）与 serve_param_err 调用点（#68 落的机器可读 expected），
// 生成器双向对账锁；本表只承载手写补充面：每方法一句简介 + 示例 params
// （dispatch 新增方法而本表未配 → 生成器 fail loud 红）。
///|
pub struct Rules {
  schema : Int
  expected_method_count : Int
  methods : Array[MethodHelp]
}

///|
pub struct MethodHelp {
  method : String
  brief : String
  example : String
}

///|
pub let rules : Rules = Rules::{
  schema: 1,
  expected_method_count: 27,
  methods: [
    MethodHelp::{method: "ping", brief: "心跳连通性探针", example: "{}"},
    MethodHelp::{method: "session.create", brief: "创建/重建会话（清空重建同一实例；argv/输入模式回默认）", example: "{}"},
    MethodHelp::{method: "session.reset", brief: "重置编译/运行状态（保留会话级配置：隔离预算/deterministic/argv）", example: "{}"},
    MethodHelp::{method: "session.destroy", brief: "销毁会话（进程存活；回收进程用 shutdown）", example: "{}"},
    MethodHelp::{method: "shutdown", brief: "关停 serve 进程（响应帧携带 shutdown:true）", example: "{}"},
    MethodHelp::{method: "config.get", brief: "读会话配置", example: "{}"},
    MethodHelp::{method: "config.set", brief: "写会话配置（max_steps/call_depth_limit/deterministic/quarantine_budget）", example: "{\"max_steps\":100000}"},
    MethodHelp::{method: "capabilities", brief: "能力清单（语言/协议面）", example: "{}"},
    MethodHelp::{method: "error_catalog", brief: "错误码目录（E/W/H 码 + 教学文案 + icon id）", example: "{}"},
    MethodHelp::{method: "semantic_labels", brief: "语义标签表（算法/事件中文标注）", example: "{}"},
    MethodHelp::{method: "contracts", brief: "schema 契约与字段台账（StepPayload 冻结面）", example: "{}"},
    MethodHelp::{method: "icons.get", brief: "图标资产按 id 下发（缺省=全量；值域=icons/index.tsv）", example: "{\"ids\":[\"uaf\"]}"},
    MethodHelp::{method: "compile", brief: "编译（覆盖式语义：files 数组=当前完整编译单元集合，非追加）", example: "{\"files\":[{\"filename\":\"main.c\",\"source\":\"int main(){return 0;}\"}]}"},
    MethodHelp::{method: "run", brief: "执行已编译单元（batch_input=输入耗尽即 EOF；argv 全量含 argv[0]）", example: "{\"argv\":[\"main.c\"]}"},
    MethodHelp::{method: "input.feed", brief: "交互续跑喂输入（waiting_input 时续跑）", example: "{\"text\":\"42\\n\"}"},
    MethodHelp::{method: "output.delta", brief: "拉增量输出（stream=display/stdout/stderr/note；判分取 stdout）", example: "{\"cursor\":0,\"stream\":\"stdout\"}"},
    MethodHelp::{method: "memory.regions", brief: "内存区域快照（堆/栈/全局）", example: "{}"},
    MethodHelp::{method: "memory.dump", brief: "1MB 内存映像 base64（--dump-memory 通道）", example: "{}"},
    MethodHelp::{method: "step.begin", brief: "开启步进会话（采集步帧；断点须 begin 后下发）", example: "{}"},
    MethodHelp::{method: "step.next", brief: "推进 N 步（返回帧数组）", example: "{\"frames\":10}"},
    MethodHelp::{method: "payload.get", brief: "取步载荷帧（游标式；回放/断点消费面）", example: "{\"cursor\":0}"},
    MethodHelp::{method: "seek", brief: "跳至目标步（会话须已 step.begin）", example: "{\"step\":3}"},
    MethodHelp::{method: "breakpoints.set", brief: "下发断点集合（行号数组）", example: "{\"lines\":[5,10]}"},
    MethodHelp::{method: "ast.dump", brief: "AST 导出（静态 dump 族——无需会话）", example: "{\"source\":\"int main(){return 0;}\"}"},
    MethodHelp::{method: "typeck.dump", brief: "类型检查导出（静态 dump 族）", example: "{\"source\":\"int main(){return 0;}\"}"},
    MethodHelp::{method: "symbols.dump", brief: "符号表导出（静态 dump 族）", example: "{\"source\":\"int main(){return 0;}\"}"},
    MethodHelp::{method: "diagnostics_probe", brief: "诊断探针（补全/悬停位——M15 无实现面 fail loud）", example: "{\"source\":\"int main(){return 0;}\"}"},
  ],
}
