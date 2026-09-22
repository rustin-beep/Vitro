// Package canonicalize 差分锚的 JSON 归一器（单源）。
//
// 用途：E1/E4 等 B 级锚的对拍——Rust 侧（serde_json）与 MoonBit 侧（显式
// emitter）的 JSON 输出**同经本包归一**后逐字节比对。归一规则：
//
//  1. 对象键按字典序排序（数组顺序保持——数组是有序结构，排序会销毁信息）；
//  2. 数字形态保持（json.Number 直通——1、1.0、1e2 不互相改写；两侧若对
//     同一数值写出不同形态，属于 emitter 侧要修的差异，不是本包的归一职责）；
//  3. 字符串转义统一（解码后按 Go 标准编码重转义，HTML 转义关闭）；
//  4. 缩进固定 2 空格 + 尾随换行。
//
// 形态约定（scripts 通行纪律）：零第三方依赖 / fail loud（非法 JSON 返回
// 错误，由调用方拒绝输出，禁止静默 default）/ **不打印、不 os.Exit**——本包
// 不替调用方决定呈现方式（CLI 走 fatal，驱动走各自 fail）。J9 埋雷锚见
// scripts/canonicalize/canonicalize_test.go。
//
// 抽库动因（一手实测，2026-09-22）：本逻辑原为 scripts/canonicalize 的
// package main 本体，各 diff 驱动每次归一都 exec.Command 起一个新进程——旧 CLI
// 单次实测 **224.6ms**（基本即进程创建成本）；typeck_diff 四语料 600 文件 ×
// 每文件 2 次 = 1200 次进程创建（按单次 224.6ms 自洽 ≈ 270s），且调用点在逐
// 文件循环内**串行**执行，32 线程机上只占 1 核（"CPU 几乎没占用"的成因）。
// 改为进程内调用后单次实测 **4.6ms / 225KB 载荷**——省下的是进程创建，不是
// "归零"。
//
// 已知取舍（进程内化付出的代价）：归一器与驱动**同进程**后，失去了原子进程
// 隔离——原本归一器 panic / 挂死不会打死驱动。评估为可接受：Bytes 是纯内存
// JSON 变换（输入为已读入内存的字节，无 I/O、无外部输入驱动的循环），panic 面
// 极窄；真出问题时驱动以非 0 崩溃，仍满足 fail loud（红），仅失去子进程那份
// "错误消息更友好"。若将来本包引入 I/O 或复杂解析，应重新评估退回子进程隔离。
//
// scripts/canonicalize 保留为 CLI 壳（stdin 进 stdout 出 / --check 锚定模式）
// ——**不可删**：冻结区 native/tests/ast_dump_test.rs 仍以
// `go run ../scripts/canonicalize` 子进程调用它（stdin→stdout 契约），删壳或
// 改 CLI 契约会直接打断冻结区测试。CLI 只做壳，判定单源在本包。
package canonicalize

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
)

// Bytes：原始 JSON 字节 → 规范形字节（尾随换行含）。非法输入返回错误。
func Bytes(raw []byte) ([]byte, error) {
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.UseNumber() // 数字保形：1 / 1.0 / 1e2 直通，不改写
	var v interface{}
	if err := dec.Decode(&v); err != nil {
		return nil, fmt.Errorf("非法 JSON: %w", err)
	}
	// 尾随内容拒绝（两份 JSON 拼接是锚数据错误，不是可猜的输入）。
	// 审阅处置（2026-09-19）：区分"多个 JSON 值"与"尾随非 JSON 垃圾"——
	// 同为拒绝、判定无损，仅消息精确化。
	if err := dec.Decode(new(json.RawMessage)); err != io.EOF {
		if err == nil {
			return nil, fmt.Errorf("输入含多个 JSON 值（锚数据必须是单值）")
		}
		return nil, fmt.Errorf("首个 JSON 值后存在尾随内容（%v）；锚数据必须是单值", err)
	}
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false) // HTML 转义差异（&<>）属 emitter 差异，归一层关闭
	enc.SetIndent("", "  ")
	if err := enc.Encode(v); err != nil {
		return nil, fmt.Errorf("重编码失败: %w", err)
	}
	return buf.Bytes(), nil
}
