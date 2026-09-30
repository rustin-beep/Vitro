/* synth.c —— WAV 合成器，生成《小星星》
 *
 * 编译: gcc -Wall -O2 -o synth synth.c -lm
 * 运行: ./synth [波形] [输出文件]
 *
 * 波形:
 *   0 = 正弦波（柔和，默认）
 *   1 = 方波（电子游戏风）
 *   2 = 三角波（介于两者之间）
 *   3 = 锯齿波（明亮、尖锐）
 *
 * 示例:
 *   ./synth 0 twinkle.wav
 *   ./synth 1 chiptune.wav
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <stdint.h>

#define SAMPLE_RATE 44100
#define PI  3.14159265358979323846
#define TAU (2.0 * PI)

/* ================================================================
 * 1. WAV 文件写入（小端序）
 *
 *    WAV = RIFF 容器 + fmt 块 + data 块
 *    我们写的是 16-bit PCM 单声道，格式固定，够简单
 * ================================================================ */
static void put_u16le(FILE *fp, uint16_t v)
{
    fputc( v       & 0xff, fp);
    fputc((v >> 8) & 0xff, fp);
}

static void put_u32le(FILE *fp, uint32_t v)
{
    fputc( v        & 0xff, fp);
    fputc((v >>  8) & 0xff, fp);
    fputc((v >> 16) & 0xff, fp);
    fputc((v >> 24) & 0xff, fp);
}

static void write_wav_header(FILE *fp, int num_samples)
{
    int data_bytes = num_samples * 2;

    fwrite("RIFF", 1, 4, fp);
    put_u32le(fp, (uint32_t)(36 + data_bytes));
    fwrite("WAVE", 1, 4, fp);

    /* fmt 块：16 字节 */
    fwrite("fmt ", 1, 4, fp);
    put_u32le(fp, 16);                          /* 块大小 */
    put_u16le(fp, 1);                           /* 编码 = PCM */
    put_u16le(fp, 1);                           /* 声道数 = 1 */
    put_u32le(fp, SAMPLE_RATE);                 /* 采样率 */
    put_u32le(fp, SAMPLE_RATE * 2);             /* 字节率 = 采样率 × 块对齐 */
    put_u16le(fp, 2);                           /* 块对齐 = 声道 × 位深/8 */
    put_u16le(fp, 16);                          /* 位深 */

    /* data 块 */
    fwrite("data", 1, 4, fp);
    put_u32le(fp, (uint32_t)data_bytes);
}

/* ================================================================
 * 2. 波形生成
 *
 *    输入 phase（已经累加到某个值，可以是小数），输出 -1 ~ +1
 *    关键是先 phase -= floor(phase)，把它规约到 [0,1)，
 *    这样频率再高也不会漂移
 * ================================================================ */
static double osc(int type, double phase)
{
    phase -= floor(phase);      /* 规约到 [0, 1) */

    switch (type) {
    case 0:  /* 正弦波：最干净的音色 */
        return sin(TAU * phase);

    case 1:  /* 方波：只有 +1 / -1，谐波丰富 */
        return phase < 0.5 ? 1.0 : -1.0;

    case 2:  /* 三角波：线性上下 */
        return 4.0 * fabs(phase - 0.5) - 1.0;

    case 3:  /* 锯齿波：0 → +1 → -1 跳变 */
        return 2.0 * phase - 1.0;

    default:
        return 0.0;
    }
}

/* ================================================================
 * 3. MIDI 音高 → 频率
 *
 *    MIDI 69 = A4 = 440Hz，每 ±1 就 × 2^(±1/12)
 * ================================================================ */
static double midi_freq(int midi)
{
    return 440.0 * pow(2.0, (midi - 69) / 12.0);
}

/* ================================================================
 * 4. ADSR 包络
 *
 *    A（Attack）  ：从 0 快速升到 1
 *    D（Decay）   ：从 1 降到 sustain 电平
 *    S（Sustain） ：保持
 *    R（Release） ：末尾降到 0
 *
 *    这里用简化版：只做 A 和 R，中间直接保持 1
 *    这足够避免开头/结尾的"咔嗒"声
 * ================================================================ */
static double envelope(double t, double dur)
{
    const double ATK = 0.008;   /* 8ms */
    const double REL = 0.10;    /* 100ms */

    if (t < ATK)         return t / ATK;
    if (t > dur - REL)   return (dur - t) / REL;
    return 1.0;
}

/* ================================================================
 * 5. 曲谱结构
 * ================================================================ */
typedef struct {
    int    midi;    /* MIDI 音符编号 */
    double beats;   /* 时长（拍） */
} Note;

/* ================================================================
 * 6. 合成：把曲谱渲染成浮点采样
 *
 *    为什么用 double 而不是直接写 int16？
 *    - 多个音符可能重叠（和弦/混响），double 做中间缓冲不会截断
 *    - 最后再统一归一化 + 转 int16
 * ================================================================ */
static double *synth(const Note *notes, int n, double bpm,
                     int wave, int *out_len)
{
    double beat_sec = 60.0 / bpm;

    /* 先算总样本数 */
    long total = 0;
    for (int i = 0; i < n; i++)
        total += (long)(notes[i].beats * beat_sec * SAMPLE_RATE);

    *out_len = (int)total;

    double *buf = (double *)calloc((size_t)total, sizeof(double));
    if (!buf) { perror("calloc"); exit(1); }

    long pos = 0;
    for (int i = 0; i < n; i++) {
        double dur     = notes[i].beats * beat_sec;
        int    samples = (int)(dur * SAMPLE_RATE);
        double f       = midi_freq(notes[i].midi);

        for (int j = 0; j < samples; j++) {
            double t   = (double)j / SAMPLE_RATE;
            double env = envelope(t, dur);
            double s   = osc(wave, f * t) * env;

            if (pos + j < total)
                buf[pos + j] += s;       /* 累加，为以后的复音做准备 */
        }
        pos += samples;
    }
    return buf;
}

/* ================================================================
 * 7. 简单混响
 *
 *    原理：把信号延迟一小段，衰减后叠加回原信号。
 *    多个不同延迟时间叠加，就能得到自然的空间感。
 * ================================================================ */
static void reverb(double *buf, int n)
{
    /* 三个不同延迟，模拟房间里的多次反射 */
    struct { int div; double gain; } taps[] = {
        { 12, 0.25 },   /* ~83ms */
        {  9, 0.18 },   /* ~110ms */
        { 23, 0.10 },   /* ~43ms */
    };

    for (size_t k = 0; k < sizeof(taps)/sizeof(taps[0]); k++) {
        int d = SAMPLE_RATE / taps[k].div;
        for (int i = d; i < n; i++)
            buf[i] += buf[i - d] * taps[k].gain;
    }
}

/* ================================================================
 * 8. 写文件：归一化 + 转 int16
 * ================================================================ */
static void write_wav(const char *file, const double *buf, int n)
{
    FILE *fp = fopen(file, "wb");
    if (!fp) { perror(file); exit(1); }

    write_wav_header(fp, n);

    /* 找最大振幅 */
    double max = 0.0;
    for (int i = 0; i < n; i++) {
        double a = fabs(buf[i]);
        if (a > max) max = a;
    }
    if (max < 1e-9) max = 1.0;

    /* 留 15% 峰值余量，避免削波 */
    double scale = 0.85 / max;

    for (int i = 0; i < n; i++) {
        double v = buf[i] * scale;
        if (v >  1.0) v =  1.0;
        if (v < -1.0) v = -1.0;

        int16_t s = (int16_t)(v * 32767.0);
        put_u16le(fp, (uint16_t)s);
    }
    fclose(fp);
}

/* ================================================================
 * 9. 曲谱：《小星星》
 *
 *    C 大调，1=C4（MIDI 60），120 BPM
 *    四分音符 = 1 拍，二分音符 = 2 拍
 * ================================================================ */
static const Note TWINKLE[] = {
    /* 一闪一闪亮晶晶 */
    {60,1},{60,1},{67,1},{67,1},{69,1},{69,1},{67,2},
    /* 满天都是小星星 */
    {65,1},{65,1},{64,1},{64,1},{62,1},{62,1},{60,2},
    /* 挂在天空放光明 */
    {67,1},{67,1},{65,1},{65,1},{64,1},{64,1},{62,2},
    /* 好像许多小眼睛 */
    {67,1},{67,1},{65,1},{65,1},{64,1},{64,1},{62,2},
    /* 一闪一闪亮晶晶 */
    {60,1},{60,1},{67,1},{67,1},{69,1},{69,1},{67,2},
    /* 满天都是小星星 */
    {65,1},{65,1},{64,1},{64,1},{62,1},{62,1},{60,2},
};

/* ================================================================
 * 10. main
 * ================================================================ */
static const char *wave_name(int w)
{
    static const char *names[] = { "正弦波", "方波", "三角波", "锯齿波" };
    return (w >= 0 && w <= 3) ? names[w] : "未知";
}

int main(int argc, char **argv)
{
    int wave = (argc > 1) ? atoi(argv[1]) : 0;
    const char *out = (argc > 2) ? argv[2] : "twinkle.wav";

    if (wave < 0 || wave > 3) {
        fprintf(stderr, "波形必须是 0-3\n");
        return 1;
    }

    printf("=== WAV 合成器 ===\n");
    printf("  波形:   %s\n", wave_name(wave));
    printf("  采样率: %d Hz / 16-bit / 单声道\n", SAMPLE_RATE);
    printf("  速度:   120 BPM\n");
    printf("  输出:   %s\n\n", out);

    int n;
    double *buf = synth(TWINKLE,
                        (int)(sizeof(TWINKLE) / sizeof(TWINKLE[0])),
                        120.0, wave, &n);

    printf("  合成完成: %d 样本 (%.2f 秒)\n", n, (double)n / SAMPLE_RATE);

    reverb(buf, n);
    printf("  已添加混响\n");

    write_wav(out, buf, n);
    printf("  已写入: %s\n", out);

    free(buf);

    printf("\n用任意播放器打开即可（也可复制到手机）。\n");
    printf("macOS:   afplay %s\n", out);
    printf("Linux:   aplay %s\n", out);
    printf("Windows: start %s\n", out);

    return 0;
}
