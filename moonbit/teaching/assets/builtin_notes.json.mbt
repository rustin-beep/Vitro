// teaching/assets·builtin 参数错误文案【真源】（issue #60 批三段二，2026-10-10）。
//
// 契约：键 = builtin 函数名；值 = BuiltinNote { count_note（count 错误的
// 静态释义整句，空串 = 沿用 generic「X 需要 N 个参数」）；param_notes
//（参数位的静态中文数字整句，与参数位对位，空串 = 该位沿用现行为）}。
// **边界**：只收静态整句——含插值的循环/特判句（「第 \{i + 1} 个参数
// 必须是 int」族）与检查逻辑强耦合，留代码；FILE*/字符串位的特判逻辑
// 本身不可表驱动（病 11 收编边界 = 骨架 P/I/D 臂，异构臂维持专臂 +
// 本处文案外置）。消费方 typeck（L5，同层依赖合法——层值 5 拍板）。
///|
pub struct BuiltinNote {
  count_note : String
  param_notes : Array[String]
}

///|
pub let builtin_notes : Map[String, BuiltinNote] = {
  "fread": BuiltinNote::{
    count_note: "fread 需要四个参数（缓冲区、元素大小、元素数量、文件指针）",
    param_notes: ["fread 第一个参数必须是指针或数组"],
  },
  "fwrite": BuiltinNote::{
    count_note: "fwrite 需要四个参数（缓冲区、元素大小、元素数量、文件指针）",
    param_notes: [
      "fwrite 第一个参数必须是指针或数组", "", "", "fwrite 第四个参数必须是文件指针",
    ],
  },
  "fseek": BuiltinNote::{
    count_note: "fseek 需要三个参数（文件指针、偏移量、起始位置）",
    param_notes: ["fseek 第一个参数必须是文件指针"],
  },
  "fgets": BuiltinNote::{
    count_note: "",
    param_notes: [
      "fgets 第一个参数必须是指针或数组", "fgets 第二个参数必须是 int",
      "fgets 第三个参数必须是文件指针",
    ],
  },
  "fputc": BuiltinNote::{
    count_note: "fputc 需要两个参数（字符和文件指针）",
    param_notes: [
      "fputc 第一个参数必须是 int", "fputc 第二个参数必须是文件指针",
    ],
  },
  "fputs": BuiltinNote::{
    count_note: "",
    param_notes: [
      "fputs 第一个参数必须是字符串", "fputs 第二个参数必须是文件指针",
    ],
  },
  "fopen": BuiltinNote::{
    count_note: "fopen 需要两个参数（路径和模式）",
    param_notes: [],
  },
  "fclose": BuiltinNote::{
    count_note: "",
    param_notes: ["fclose 参数必须是文件指针"],
  },
  "feof": BuiltinNote::{
    count_note: "",
    param_notes: ["feof 参数必须是文件指针"],
  },
  "fgetc": BuiltinNote::{
    count_note: "",
    param_notes: ["fgetc 参数必须是文件指针"],
  },
  "ftell": BuiltinNote::{
    count_note: "",
    param_notes: ["ftell 参数必须是文件指针"],
  },
  "rewind": BuiltinNote::{
    count_note: "",
    param_notes: ["rewind 参数必须是文件指针"],
  },
}
