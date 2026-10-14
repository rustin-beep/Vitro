# 冻结判据快照（Windows / PowerShell）
#
# 用途：把判据（native exe + wasm 壳 + wasm.wasm）复制成一个**自足目录**，
#       使判据不受"工作区里那个 exe 被别人重建"的影响（多会话共写同一工作区的实锤对策）。
#
# 为什么这样复制：
#   - vitro.exe 自足（导入仅系统 DLL）⇒ 放哪都能跑
#   - main.js 用 REPO = path.join(__dirname,"..","..") 定位 wasm.wasm，
#     并 require("./api_help.json") ⇒ **必须按原相对布局**摆
#
# 用法：改 $Repo / $Out 后运行；每换一次基线就换一个新目录（_judge_v2/_judge_v3…），
#       不要就地覆盖——否则历史结果的 judge_id 失去归属。

$Repo = "D:\code\Vitro"
$Out  = "D:\code\Vitro\tmp\review\_judge_v1"

$native = Join-Path $Repo "moonbit\_build\native\release\build\cmd\vitro\vitro.exe"
$wasm   = Join-Path $Repo "moonbit\_build\wasm-gc\release\build\gateway\wasm\wasm.wasm"
$cli    = Join-Path $Repo "scripts\vitro_cli"

if (-not (Test-Path $native)) { Write-Error "native exe 不存在：$native（先重建）"; exit 1 }
if (-not (Test-Path $wasm))   { Write-Error "wasm.wasm 不存在：$wasm"; exit 1 }

New-Item -ItemType Directory -Force -Path "$Out\scripts\vitro_cli" | Out-Null
New-Item -ItemType Directory -Force -Path "$Out\moonbit\_build\wasm-gc\release\build\gateway\wasm" | Out-Null

Copy-Item $native "$Out\vitro.exe" -Force
Copy-Item "$cli\main.js","$cli\api_help.json" "$Out\scripts\vitro_cli\" -Force
Copy-Item $wasm "$Out\moonbit\_build\wasm-gc\release\build\gateway\wasm\wasm.wasm" -Force

# 指纹：各产物 sha256 + 当时 repo 基线
$rec = [ordered]@{
  frozen_at  = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
  repo_head  = (git -C $Repo rev-parse HEAD)
  repo_dirty = (git -C $Repo status --short | Measure-Object).Count
}
foreach ($rel in @("vitro.exe","scripts\vitro_cli\main.js","scripts\vitro_cli\api_help.json",
                   "moonbit\_build\wasm-gc\release\build\gateway\wasm\wasm.wasm")) {
  $p = Join-Path $Out $rel
  $rec[$rel] = @{ size = (Get-Item $p).Length; sha256 = (Get-FileHash $p -Algorithm SHA256).Hash.ToLower() }
}
$rec | ConvertTo-Json -Depth 5 | Out-File "$Out\judge_fingerprint.json" -Encoding utf8

Write-Host "冻结完成：$Out" -ForegroundColor Green
Write-Host ("vitro.exe sha256[:12] = " + $rec["vitro.exe"].sha256.Substring(0,12)) -ForegroundColor Green

# 自检：拿一个真实语料，双臂各跑一次 —— 判定应一致（双端强制）
$probe = Join-Path $Repo "corpus\baseline\array_bounds_safe.c"
if (Test-Path $probe) {
  Write-Host "`n自检用例：$probe" -ForegroundColor Cyan
  Write-Host "--- native 臂 ---"
  & "$Out\vitro.exe" compile $probe --json 2>$null | Write-Host
  Write-Host "--- wasm 臂（需 node 在 PATH）---"
  & node "$Out\scripts\vitro_cli\main.js" compile $probe --json 2>$null | Write-Host
  Write-Host "两臂判定不一致 ⇒ 快照有问题，先查 wasm.wasm 的复制布局。"
} else {
  Write-Host "（未找到自检用例 $probe，跳过自检）" -ForegroundColor Yellow
}
