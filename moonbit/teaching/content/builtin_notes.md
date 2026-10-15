<!--
teaching/content·builtin 参数错误文案（12 个函数）【真源】（#125 批 A，2026-10-15）。

管线（替代 #60 双出口：.json.mbt 真源 + jsonmbt 再生教师面 .json）：
  本文件（人写）→ moonbit/teaching/tools/content_parser.c（vitro 编译运行，
  自己吃自己狗粮）→
  moonbit/teaching/assets/builtin_notes_gen.mbt（@generated 禁手改）→ 引擎 import 面不变。

写作规则（生成器按**纯文本**切段，本文件不进渲染链；markdown 语法不生效）：
- 一节一函数：`## <builtin 名>`；
- `count_note:` 可选，空串 = 省略该行（沿用 generic「X 需要 N 个参数」）；
- `param_notes[i]:` 显式参数位（i 从 0 起）；**缺位即空串**——写哪个位就只对哪位生效；
- 索引越界/重复/非数字 = 生成器 fail loud。
-->

## fread

count_note: fread 需要四个参数（缓冲区、元素大小、元素数量、文件指针）
param_notes[0]: fread 第一个参数必须是指针或数组

## fwrite

count_note: fwrite 需要四个参数（缓冲区、元素大小、元素数量、文件指针）
param_notes[0]: fwrite 第一个参数必须是指针或数组
param_notes[3]: fwrite 第四个参数必须是文件指针

## fseek

count_note: fseek 需要三个参数（文件指针、偏移量、起始位置）
param_notes[0]: fseek 第一个参数必须是文件指针

## fgets

param_notes[0]: fgets 第一个参数必须是指针或数组
param_notes[1]: fgets 第二个参数必须是 int
param_notes[2]: fgets 第三个参数必须是文件指针

## fputc

count_note: fputc 需要两个参数（字符和文件指针）
param_notes[0]: fputc 第一个参数必须是 int
param_notes[1]: fputc 第二个参数必须是文件指针

## fputs

param_notes[0]: fputs 第一个参数必须是字符串
param_notes[1]: fputs 第二个参数必须是文件指针

## fopen

count_note: fopen 需要两个参数（路径和模式）

## fclose

param_notes[0]: fclose 参数必须是文件指针

## feof

param_notes[0]: feof 参数必须是文件指针

## fgetc

param_notes[0]: fgetc 参数必须是文件指针

## ftell

param_notes[0]: ftell 参数必须是文件指针

## rewind

param_notes[0]: rewind 参数必须是文件指针
