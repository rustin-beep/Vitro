// realcode_diff 共享类型（字段名 = result.json 键，Go 版结构体标签单源）。

export interface Diag {
  severity: string;
  code: string;
  line: number;
  column: number;
  message: string;
}

/** 与 Go `FileResult` 逐字段同构；omitempty 字段用可选属性表达。 */
export interface FileResult {
  path: string;
  clang_ok: boolean;
  gcc_ok: boolean;
  clang_errors: number;
  clang_warnings: number;
  clang_first_error?: string;
  vitro_diags?: Diag[];
  vitro_errors: number;
  vitro_warnings: number;
  vitro_layer?: string;
  stripped_try: boolean;
  strip_layer?: string;
  strip_errors?: number;
  run_compare?: string;
  run_detail?: string;
}

/** 多文件工程（目录内 .c 一起编译，.h 仅经 include 展开）。 */
export interface Project {
  name: string;
  dir: string;
  files: string[];
  units: string[];
}

export interface CompileFile {
  /** 送入引擎的 filename（绝对路径 → base_dir 候选链的锚）。 */
  path: string;
}
