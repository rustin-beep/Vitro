// desktop/app：proton 窗口入口。UI = demo/（Svelte 5 + Vite）——frontend
// 产物/开发服务由 proton_cli 按 proton.project.json frontend 段托管：
//   dev：`proton_cli dev` 起 vite dev server 并以 PROTON_FRONTEND_URL 覆盖
//        entry（facade 的 proton_dev_url_override）；
//   打包形态：asset 指向构建产物（../demo/dist/index.html——跨目录打包
//        装配是下批验证面）。
// 命令注册走官方 app-owned 形态 `..commands()`（isomorphic 模板同款）；
// builder debug=true 缺省开 CDP（钉端口/翻开关矩阵见 desktop/README.md）。

///|
async fn main {
  @content_data.install_baked()
  @proton.asset(
    "Vitro Desktop",
    "../demo/dist/index.html",
    width=1280,
    height=820,
    debug=true,
  )
  ..config(@proton.load_config())
  ..commands(fn(registrar) raise { register_engine_commands(registrar) })
  .run_or_abort()
}
