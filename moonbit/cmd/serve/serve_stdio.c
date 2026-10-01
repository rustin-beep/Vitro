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
