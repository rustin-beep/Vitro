/* mandelbrot.c —— 生成曼德博集合 BMP 图像
 *
 * 编译: gcc -Wall -O2 -o mandelbrot mandelbrot.c -lm
 * 用法: ./mandelbrot [输出文件] [宽] [高] [迭代上限] [缩放] [中心x] [中心y] [调色板]
 * 示例: ./mandelbrot fractal.bmp 1920 1080 800 1 -0.5 0 0
 *
 * 调色板: 0=火焰 1=海洋 2=黑白
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <stdint.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

/* ---------------- BMP 小端写入工具 ---------------- */
static void put_u16le(FILE *fp, uint16_t v)
{
    fputc(v & 0xff, fp);
    fputc((v >> 8) & 0xff, fp);
}

static void put_u32le(FILE *fp, uint32_t v)
{
    fputc( v        & 0xff, fp);
    fputc((v >>  8) & 0xff, fp);
    fputc((v >> 16) & 0xff, fp);
    fputc((v >> 24) & 0xff, fp);
}

/* 写 24 位 BMP 头，返回每行字节数（已按 4 字节对齐） */
static int write_bmp_header(FILE *fp, int width, int height)
{
    int row_stride      = (width * 3 + 3) & ~3;   /* 4 字节对齐 */
    uint32_t pixel_bytes = (uint32_t)row_stride * height;
    uint32_t file_size   = 14 + 40 + pixel_bytes;

    /* BITMAPFILEHEADER (14 字节) */
    fputc('B', fp);
    fputc('M', fp);
    put_u32le(fp, file_size);
    put_u16le(fp, 0);           /* reserved */
    put_u16le(fp, 0);
    put_u32le(fp, 54);          /* 像素数据偏移 */

    /* BITMAPINFOHEADER (40 字节) */
    put_u32le(fp, 40);          /* header 大小 */
    put_u32le(fp, (uint32_t)width);
    put_u32le(fp, (uint32_t)height);
    put_u16le(fp, 1);           /* planes */
    put_u16le(fp, 24);          /* 每像素位数 */
    put_u32le(fp, 0);           /* 不压缩 */
    put_u32le(fp, pixel_bytes);
    put_u32le(fp, 2835);        /* 水平 DPI (72dpi = 2835 px/m) */
    put_u32le(fp, 2835);
    put_u32le(fp, 0);           /* 调色板颜色数 */
    put_u32le(fp, 0);           /* 重要颜色数 */

    return row_stride;
}

/* ---------------- 调色板 ---------------- */
typedef void (*PaletteFn)(double t, uint8_t *r, uint8_t *g, uint8_t *b);

/* 余弦调色板：只需改相位就能生成各种配色，Inigo Quilez 的经典技巧 */
static void palette_fire(double t, uint8_t *r, uint8_t *g, uint8_t *b)
{
    *r = (uint8_t)(255 * (0.5 + 0.5 * cos(2 * M_PI * (t + 0.00))));
    *g = (uint8_t)(255 * (0.5 + 0.5 * cos(2 * M_PI * (t + 0.15))));
    *b = (uint8_t)(255 * (0.5 + 0.5 * cos(2 * M_PI * (t + 0.30))));
}

static void palette_ocean(double t, uint8_t *r, uint8_t *g, uint8_t *b)
{
    *r = (uint8_t)(255 * (0.5 + 0.5 * cos(2 * M_PI * (t + 0.60))));
    *g = (uint8_t)(255 * (0.5 + 0.5 * cos(2 * M_PI * (t + 0.45))));
    *b = (uint8_t)(255 * (0.5 + 0.5 * cos(2 * M_PI * (t + 0.10))));
}

static void palette_mono(double t, uint8_t *r, uint8_t *g, uint8_t *b)
{
    t = fmod(t, 1.0);
    uint8_t v = (uint8_t)(255 * (0.5 + 0.5 * cos(2 * M_PI * t)));
    *r = *g = *b = v;
}

/* ---------------- 曼德博迭代 ---------------- */
/* 返回平滑迭代值；若落在集合内部则返回负值 */
static double mandelbrot(double cx, double cy, int max_iter)
{
    double x = 0.0, y = 0.0;
    int i;

    for (i = 0; i < max_iter; i++) {
        double x2 = x * x;
        double y2 = y * y;
        if (x2 + y2 > 4.0) break;          /* 逃逸 */
        double xt = x2 - y2 + cx;
        y = 2.0 * x * y + cy;
        x = xt;
    }

    if (i == max_iter) return -1.0;        /* 收敛，在集合内 */

    /* 平滑着色：消除"色带"条纹 */
    double log_zn = log(x * x + y * y) * 0.5;
    double nu     = log(log_zn / log(2.0)) / log(2.0);
    return (double)i + 1.0 - nu;
}

/* ---------------- 主程序 ---------------- */
int main(int argc, char **argv)
{
    const char *out   = "mandelbrot.bmp";
    int    width      = 1200;
    int    height     = 900;
    int    max_iter   = 500;
    double zoom       = 1.0;
    double cx         = -0.5;
    double cy         =  0.0;
    PaletteFn palette = palette_fire;

    if (argc > 1) out      = argv[1];
    if (argc > 2) width    = atoi(argv[2]);
    if (argc > 3) height   = atoi(argv[3]);
    if (argc > 4) max_iter = atoi(argv[4]);
    if (argc > 5) zoom     = atof(argv[5]);
    if (argc > 6) cx       = atof(argv[6]);
    if (argc > 7) cy       = atof(argv[7]);
    if (argc > 8) {
        int p = atoi(argv[8]);
        if      (p == 0) palette = palette_fire;
        else if (p == 1) palette = palette_ocean;
        else if (p == 2) palette = palette_mono;
    }

    if (width < 1 || height < 1 || max_iter < 1 || zoom <= 0) {
        fprintf(stderr, "参数非法\n");
        return 1;
    }

    FILE *fp = fopen(out, "wb");
    if (!fp) { perror("无法创建文件"); return 1; }

    int row_stride = write_bmp_header(fp, width, height);

    /* 视口：先按缩放算跨度，再按宽高比算高度，最后以 (cx,cy) 居中 */
    double span_x = 3.5 / zoom;
    double aspect = (double)width / height;
    double span_y = span_x / aspect;
    double x_min  = cx - span_x / 2.0;
    double x_max  = cx + span_x / 2.0;
    double y_min  = cy - span_y / 2.0;
    double y_max  = cy + span_y / 2.0;

    fprintf(stderr,
        "渲染 %dx%d 迭代=%d 缩放=%.3g 中心=(%.8f, %.8f)\n",
        width, height, max_iter, zoom, cx, cy);

    unsigned char *row = (unsigned char *)malloc((size_t)row_stride);
    if (!row) { fclose(fp); return 1; }

    for (int py = 0; py < height; py++) {
        if ((py & 15) == 0) {
            fprintf(stderr, "\r  进度 %3d%%", py * 100 / height);
            fflush(stderr);
        }

        /* BMP 自下而上存储：文件第一行 = 图像底部 */
        double y = y_min + (y_max - y_min) * py / (height - 1);
        memset(row, 0, (size_t)row_stride);

        for (int px = 0; px < width; px++) {
            double x  = x_min + (x_max - x_min) * px / (width - 1);
            double sm = mandelbrot(x, y, max_iter);

            uint8_t r = 0, g = 0, b = 0;
            if (sm >= 0.0) {
                /* sqrt 压缩分布，让远处色彩过渡更自然 */
                double t = sqrt(sm) / 6.0;
                palette(t, &r, &g, &b);
            }

            /* BMP 是 BGR 顺序 */
            int off = px * 3;
            row[off + 0] = b;
            row[off + 1] = g;
            row[off + 2] = r;
        }
        fwrite(row, 1, (size_t)row_stride, fp);
    }

    fprintf(stderr, "\r  进度 100%%    \n");
    free(row);
    fclose(fp);
    fprintf(stderr, "完成: %s\n", out);
    return 0;
}
