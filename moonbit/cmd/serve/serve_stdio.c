// cmd/serve 的 stdin 行读取 stub（S7 批三号一段）。
// MoonBit core/x 生态无 stdin 读取能力（builtin console 仅输出向、x/sys
// 无 stdin、x/fs 是文件句柄族）——serve 是 JSON-lines 会话协议（每行一
// 请求），行读取经本 C stub（fgets——Windows MSVC 与 POSIX 通用；行上限
// 64KB，与 Rust 侧 bufio 默认量级同域）。
// 返回值：>0 = 行字节数（不含结尾 NUL，已剥 \n 与 \r\n）；0 = 空行；
// -1 = EOF（含立即 EOF）；-2 = 行超长（未消费完，视为协议错误）。
//
// serve_flush_stdout（2026-10-01 审阅 P1 rss 批销项实锤的交互死锁修复）：
// stdout 在管道/重定向形态下是全缓冲（MSVC CRT 无可靠行缓冲），批式
// 消费方（一次性喂 stdin）无感，**交互式消费方**（写一行读一行——
// serve_smoke rss 批/上游宿主）会死等首响应。Rust 侧 println! 自带行
// flush 无此形态。每响应行显式 fflush（频次 = 请求量级，开销可忽略）。

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <signal.h>

#ifdef _WIN32
#include <io.h>
#include <fcntl.h>
#endif

/* #357/#391 审阅 P2-2（2026-10-31）：崩溃路径防线——与 cmd/vitro|run|step
 * 的 stdout_stub.c 同款 SIGABRT handler（本文件是 ensure_binary_mode 的
 * 第四份独立实现，stdout_stub_copies 按文件名锁锁不到此处——连坐义务
 * 在 single_source rules.json 该条目注释登记）。UCRT 下 abort 不刷 stdio
 * 缓冲且 raise 形态走 _exit(3) 撞 step-limit 码（P1-1）——先刷全部输出
 * 流，恢复默认后 abort() 保 crash 形态（Windows 0xC0000409 / POSIX 134
 * + core）。锚 = vitro_cli_smoke B 组附 9。 */
static void serve_abort_flush(int sig) {
  (void)sig;
  fflush(NULL);
  signal(SIGABRT, SIG_DFL);
  abort();
}

/* #335（2026-10-27）：帧通道行尾治本——serve 的响应帧（println 出口）
 * 不走任何 write stub，Windows CRT 文本模式把每个 \n 静默改写 \r\n
 * （native 帧尾 0d 0a vs js/wasm 0a，NDJSON 线协议逐字节判分必红；
 * 与 cmd/vitro|run|step 的 stdout_stub.c 同款导出）。main.mbt 首行调用
 * （**不用 constructor**——moon test --target native 的 stub 编译链固定
 * MSVC 探测，GNU 属性 C2143 编译红，2026-10-27 实测）。stdin 不切——
 * fgets 行读取面维持 CRT 折行 + 下方手剥 \r\n 既有归一。POSIX 无此
 * 概念。幂等。#357（2026-10-31）：同点挂 SIGABRT handler（上方
 * serve_abort_flush——POSIX 侧函数体自此非空）。 */
void moonbit_vitro_ensure_binary_mode(void) {
  static int done = 0;
  if (!done) {
#ifdef _WIN32
    _setmode(_fileno(stdout), _O_BINARY);
    _setmode(_fileno(stderr), _O_BINARY);
#endif
    signal(SIGABRT, serve_abort_flush);
    done = 1;
  }
}

int moonbit_vitro_serve_read_line(char *buf, int cap) {
    if (buf == NULL || cap <= 0) {
        return -1;
    }
    if (fgets(buf, (size_t)cap, stdin) == NULL) {
        return -1;
    }
    size_t len = strlen(buf);
    // 行未被 cap 截断的判定：以 \n 收尾或已 EOF（最后一行无换行合法）
    if (len > 0 && buf[len - 1] != '\n' && !feof(stdin)) {
        return -2; // 超长行：剩余部分仍在流里，调用方应报协议错并退出
    }
    while (len > 0 && (buf[len - 1] == '\n' || buf[len - 1] == '\r')) {
        len--;
        buf[len] = '\0';
    }
    return (int)len;
}

void moonbit_vitro_serve_flush(void) {
    fflush(stdout);
}
