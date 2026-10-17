// vite ?raw 资产导入类型（course/*.md 真源内联；vite/client 类型未挂时手工声明）
declare module "*?raw" {
  const src: string;
  export default src;
}

// vite ?url 资产导入类型（engine.worker 的 wasm 资产，#139——构建期资产
// 缺失即 build 红 fail loud，取代 new URL 形态的「缺失静默退化为运行时
// 相对路径 → Pages 404」）
declare module "*?url" {
  const src: string;
  export default src;
}

// 语言包懒加载模块（#130 批② demo 接线：MoonBit js target 构建产物，
// texts_json() 返回 payload JSON 文本——texts.install params.payload 同
// schema 的 string）
declare module "*/teaching/langpack/langpack.js" {
  export function texts_json(): string;
}

