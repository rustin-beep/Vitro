// vite ?raw 资产导入类型（course/*.md 真源内联；vite/client 类型未挂时手工声明）
declare module "*?raw" {
  const src: string;
  export default src;
}
