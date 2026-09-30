# demo 页（浏览器直调 wasm-gc gateway）

本目录是 Vitro 引擎的静态单页展示面——**零 npm 依赖、零后端**，浏览器内直接调
[`vitro/engine/gateway`](../moonbit/gateway/) 的 wasm-gc 产物（NDJSON 帧协议 v0.1）。

## 在线版

push 到 master 后由 [pages.yml](../.github/workflows/pages.yml) 自动部署：
<https://rustin-beep.github.io/Vitro/>（首次发布前需在仓库 Settings → Pages 把
Source 设为 "GitHub Actions"——`GITHUB_TOKEN` 无法自动启用 Pages）。

## 本地预览

`wasm.wasm` 是构建产物，**不入库**；且页面用 `fetch` 加载它，`file://` 直开
`index.html` 会被浏览器拒绝——必须走静态服务器：

```bash
# 1. 构建 wasm（或已有产物可跳过）
cd moonbit && moon build --release --target wasm-gc gateway/wasm && cd ..

# 2. 拷产物到 demo/
cp moonbit/_build/wasm-gc/release/build/gateway/wasm/wasm.wasm demo/

# 3. 起静态服务器（任选其一）
cd demo && python -m http.server 8931   # http://127.0.0.1:8931/
# 或：npx serve demo（不装依赖也可以用 python）
```

浏览器要求：支持 wasm-gc 与 js-string builtins 的现代内核（Chrome/Edge 130+、
Firefox 134+），加载失败页面会显示降级提示。

## 门禁

`go run` 之外本页有一条 node 判定闸：`node scripts/demo_smoke/main.js`——
对 `cases.js` 每个预置用例实跑协议链并逐字节比对 golden，同时断言渲染所需的
响应字段存在（已接线 CI core，篡改 golden 或页面引用字段名漂移即红）。

## 诚实边界

- 渲染逻辑暂放宿主页内 JS（门面定位，非架构件）；MoonBit SVG 渲染纯函数包
  落地后由其接管（总计划既定路线）。
- Clang golden 参考值为预置真值（CI shadow 防线持续对拍），页面内无实时
  交叉编译。
- 时间旅行（step 流回放）等 S8 协议面落地后接入——见页面「引擎与协议」视图
  的预留台账。
