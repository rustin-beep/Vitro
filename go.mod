module vitro

go 1.27

// #132 声明层 pin。生效机制勘正（2026-11-01 审阅 v2 S13b-P5）：本仓 CI 无
// setup-go 步（原注释「CI setup-go go-version-file 读本行」为幻觉）——实际
// 由 runner 预装 go 以 GOTOOLCHAIN=auto（默认）读本行隐式切换到该版本；
// 若未来 runner 预装版过低或 GOTOOLCHAIN 政策收紧，`go vet ./scripts/...`
// 会环境性红（届时补 setup-go with: go-version-file: go.mod 兑现显式消费）。
// 版本推进 = 本地升级 + 全闸背书后改此行，单点变更。
toolchain go1.27.1
