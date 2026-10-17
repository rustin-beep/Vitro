// vite import.meta.glob 最小面（course/*.md 懒加载交付格式——import.meta.glob
// ?url；vite/client 类型未挂，循 vite-env.d.ts 的 ?raw 手工声明同缘由）。
// 签名只收本仓用到的形态：泛型值 + query/import/eager 三选项。
//
// ⚠️ 两处结构纪律（2026-10-16 实测踩坑）：
//   ① 本文件必须是**模块**（尾 export {}）——global 增强只许直接嵌在外部
//      模块里；且 skipLibCheck 会吞掉「global 增强位置非法」的报错使增强
//      静默失效，错很难定位；
//   ② 通配模块声明（*?raw）只许在**全局脚本** .d.ts——故与 vite-env.d.ts
//      分文件，勿合并（合并则 export {} 使通配声明失效，?raw 导入全红）。
declare global {
  interface ImportMeta {
    glob<T = unknown>(
      pattern: string,
      options?: { query?: string; import?: string; eager?: boolean },
    ): Record<string, T>;
  }
}

export {};
