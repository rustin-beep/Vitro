/* raytracer.c —— 迷你光线追踪器
 *
 * 编译: gcc -Wall -O2 -o raytracer raytracer.c -lm
 * 运行: ./raytracer [输出文件] [宽] [高] [采样数]
 *
 * 渲染内容:
 *   - 地面（棋盘格）
 *   - 5 个材质各异的球体（哑光、金属、透明）
 *   - 一个点光源 + 环境光
 *   - 每个像素多采样抗锯齿
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <stdint.h>

/* ================================================================
 * 1. 三维向量
 * ================================================================ */
typedef struct { double x, y, z; } Vec3;

static Vec3 v(double x, double y, double z) { return (Vec3){x, y, z}; }
static Vec3 vadd(Vec3 a, Vec3 b)   { return v(a.x+b.x, a.y+b.y, a.z+b.z); }
static Vec3 vsub(Vec3 a, Vec3 b)   { return v(a.x-b.x, a.y-b.y, a.z-b.z); }
static Vec3 vmul(Vec3 a, double t) { return v(a.x*t, a.y*t, a.z*t); }
static Vec3 vmulv(Vec3 a, Vec3 b)  { return v(a.x*b.x, a.y*b.y, a.z*b.z); }
static double vdot(Vec3 a, Vec3 b) { return a.x*b.x + a.y*b.y + a.z*b.z; }

static Vec3 vcross(Vec3 a, Vec3 b)
{
    return v(a.y*b.z - a.z*b.y,
             a.z*b.x - a.x*b.z,
             a.x*b.y - a.y*b.x);
}

static double vlen(Vec3 a)      { return sqrt(vdot(a, a)); }
static Vec3   vnorm(Vec3 a)     { double l = vlen(a); return l > 1e-12 ? vmul(a, 1.0/l) : a; }

/* ================================================================
 * 2. 材质 & 物体
 *
 *    每种材质三个参数:
 *      color     : 漫反射颜色
 *      reflect   : 反射强度（0=哑光，1=完美镜面）
 *      checkered : 棋盘格纹理（只对地面用）
 * ================================================================ */
typedef struct {
    Vec3   color;
    double reflect;
    int    checkered;
} Material;

typedef struct {
    Vec3     center;
    double   radius;
    Material mat;
} Sphere;

#define MAX_SPHERES 32
static Sphere g_spheres[MAX_SPHERES];
static int    g_nspheres;

static void add_sphere(Vec3 c, double r, Vec3 color,
                       double reflect, int checkered)
{
    if (g_nspheres >= MAX_SPHERES) return;
    Sphere *s = &g_spheres[g_nspheres++];
    s->center = c;
    s->radius = r;
    s->mat.color     = color;
    s->mat.reflect   = reflect;
    s->mat.checkered = checkered;
}

/* ================================================================
 * 3. 光线 & 交点
 * ================================================================ */
typedef struct { Vec3 origin, dir; } Ray;

typedef struct {
    double t;          /* 距离，-1 表示没交点 */
    Vec3   point;      /* 交点坐标 */
    Vec3   normal;     /* 交点处的法线 */
    Material mat;
} Hit;

static Hit ray_sphere(Ray ray, const Sphere *s)
{
    Hit h = { .t = -1 };

    Vec3   oc = vsub(ray.origin, s->center);
    double a  = vdot(ray.dir, ray.dir);
    double b  = 2.0 * vdot(oc, ray.dir);
    double c  = vdot(oc, oc) - s->radius * s->radius;
    double disc = b*b - 4*a*c;

    if (disc < 0) return h;

    double sq = sqrt(disc);
    double t1 = (-b - sq) / (2*a);
    double t2 = (-b + sq) / (2*a);

    /* 取最近的正根 */
    double t = (t1 > 1e-6) ? t1 : ((t2 > 1e-6) ? t2 : -1);
    if (t < 0) return h;

    h.t      = t;
    h.point  = vadd(ray.origin, vmul(ray.dir, t));
    h.normal = vnorm(vsub(h.point, s->center));
    h.mat    = s->mat;
    return h;
}

/* 遍历所有球，返回最近的交点 */
static Hit trace(Ray ray)
{
    Hit best = { .t = -1 };
    for (int i = 0; i < g_nspheres; i++) {
        Hit h = ray_sphere(ray, &g_spheres[i]);
        if (h.t > 0 && (best.t < 0 || h.t < best.t))
            best = h;
    }
    return best;
}

/* 判断某点能否"看到"光源 */
static int in_shadow(Vec3 point, Vec3 light_pos)
{
    Vec3  dir = vnorm(vsub(light_pos, point));
    Ray   r   = { vadd(point, vmul(dir, 1e-4)), dir };

    for (int i = 0; i < g_nspheres; i++) {
        Hit h = ray_sphere(r, &g_spheres[i]);
        if (h.t > 0 && h.t < vlen(vsub(light_pos, point)))
            return 1;   /* 有物体挡在中间 */
    }
    return 0;
}

/* ================================================================
 * 4. 着色
 *
 *    核心思想：把光分成三部分相加
 *      环境光  = 常量底色，避免暗部全黑
 *      漫反射  = 光照强度 × 法线方向与光方向夹角的余弦
 *      镜面反射 = 反射光线方向上再发一条射线，递归求颜色
 * ================================================================ */
static Vec3 background(Ray ray)
{
    /* 天空渐变：从顶部淡蓝到地平线灰白 */
    double t = 0.5 * (ray.dir.y + 1.0);
    Vec3   sky   = v(0.5, 0.7, 1.0);
    Vec3   white = v(1.0, 1.0, 1.0);
    return vadd(vmul(white, 1.0 - t), vmul(sky, t));
}

static Vec3 shade(Ray ray, int depth)
{
    if (depth > 6) return background(ray);

    Hit h = trace(ray);
    if (h.t < 0) return background(ray);

    /* 棋盘格纹理：用 x、z 做格子索引，奇偶决定颜色 */
    Vec3 base = h.mat.color;
    if (h.mat.checkered) {
        int cx = (int)floor(h.point.x);
        int cz = (int)floor(h.point.z);
        if ((cx + cz) & 1)
            base = vmul(base, 0.35);
    }

    Vec3 light_pos = v(8.0, 12.0, 5.0);
    Vec3 light_col = v(1.0, 0.95, 0.85);

    /* 环境光 */
    Vec3 color = vmul(base, 0.10);

    /* 阴影检测 */
    if (!in_shadow(h.point, light_pos)) {
        Vec3   L        = vnorm(vsub(light_pos, h.point));
        double dist     = vlen(vsub(light_pos, h.point));
        double atten    = 1.0 / (1.0 + 0.02 * dist + 0.001 * dist * dist);
        double diffuse  = vdot(h.normal, L);
        if (diffuse > 0) {
            color = vadd(color,
                vmulv(base, vmul(light_col, diffuse * atten)));

            /* 镜面高光（Blinn-Phong 半向量法） */
            Vec3   V    = vnorm(vmul(ray.dir, -1.0));
            Vec3   H    = vnorm(vadd(L, V));
            double spec = pow(vdot(h.normal, H), 64.0);
            color = vadd(color, vmul(light_col, spec * 0.5 * atten));
        }
    }

    /* 反射：只处理金属球，限制递归深度 */
    if (h.mat.reflect > 0 && depth < 5) {
        Vec3 R = vnorm(vsub(ray.dir,
                            vmul(h.normal, 2.0 * vdot(ray.dir, h.normal))));
        Ray  reflected = { vadd(h.point, vmul(R, 1e-4)), R };
        Vec3 ref_col   = shade(reflected, depth + 1);
        color = vadd(color, vmul(ref_col, h.mat.reflect));
    }

    return color;
}

/* ================================================================
 * 5. 相机 & 主渲染循环
 * ================================================================ */
typedef struct {
    Vec3 origin;
    Vec3 lower_left;
    Vec3 horizontal;
    Vec3 vertical;
} Camera;

static void render(const char *filename, int W, int H, int samples)
{
    /* 60° 视场角，用宽高比算出画布尺寸 */
    double aspect   = (double)W / H;
    double fov      = 60.0 * M_PI / 180.0;
    double half_h   = tan(fov / 2.0);
    double half_w   = aspect * half_h;

    Camera cam;
    cam.origin     = v(0, 2.0, 4.5);
    cam.horizontal = v(2 * half_w, 0, 0);
    cam.vertical   = v(0, 2 * half_h, 0);
    cam.lower_left = vadd(vadd(cam.origin, v(-half_w, -half_h, -1.0)),
                          v(0, 0, 0));

    /* ---- 打开 BMP 文件并写头 ---- */
    FILE *fp = fopen(filename, "wb");
    if (!fp) { perror(filename); return; }

    int row_stride = (W * 3 + 3) & ~3;
    uint32_t pixel_bytes = (uint32_t)row_stride * H;
    uint32_t file_size   = 54 + pixel_bytes;

    fwrite("BM", 1, 2, fp);
    uint32_t tmp;
    tmp = file_size;  fwrite(&tmp, 4, 1, fp);
    tmp = 0;          fwrite(&tmp, 2, 1, fp); fwrite(&tmp, 2, 1, fp);
    tmp = 54;         fwrite(&tmp, 4, 1, fp);
    tmp = 40;         fwrite(&tmp, 4, 1, fp);
    tmp = (uint32_t)W; fwrite(&tmp, 4, 1, fp);
    tmp = (uint32_t)H; fwrite(&tmp, 4, 1, fp);
    uint16_t tmp16;
    tmp16 = 1;   fwrite(&tmp16, 2, 1, fp);
    tmp16 = 24;  fwrite(&tmp16, 2, 1, fp);
    tmp = 0;      fwrite(&tmp, 4, 1, fp);
    tmp = pixel_bytes; fwrite(&tmp, 4, 1, fp);
    tmp = 2835;   fwrite(&tmp, 4, 1, fp);
    tmp = 2835;   fwrite(&tmp, 4, 1, fp);
    tmp = 0;      fwrite(&tmp, 4, 1, fp);
    tmp = 0;      fwrite(&tmp, 4, 1, fp);

    unsigned char *row = (unsigned char *)malloc((size_t)row_stride);
    double inv_samples = 1.0 / samples;

    fprintf(stderr, "渲染 %dx%d，每像素 %d 采样...\n", W, H, samples);

    for (int y = H - 1; y >= 0; y--) {
        if ((y % 20) == 0) {
            fprintf(stderr, "\r  进度 %3d%%", (H - 1 - y) * 100 / H);
            fflush(stderr);
        }
        memset(row, 0, (size_t)row_stride);

        for (int x = 0; x < W; x++) {
            Vec3 color = v(0, 0, 0);

            /* 抗锯齿：像素内随机撒点，取平均 */
            for (int s = 0; s < samples; s++) {
                double jx = (s == 0 && samples == 1) ? 0.5
                          : (double)rand() / RAND_MAX;
                double jy = (s == 0 && samples == 1) ? 0.5
                          : (double)rand() / RAND_MAX;

                double u = ((double)x + jx) / W;
                double vv = ((double)y + jy) / H;

                Vec3 target = vadd(cam.lower_left,
                    vadd(vmul(cam.horizontal, u), vmul(cam.vertical, vv)));

                Ray ray = { cam.origin, vnorm(vsub(target, cam.origin)) };
                color = vadd(color, shade(ray, 0));
            }

            color = vmul(color, inv_samples);

            /* 色调映射：防止过曝 → 纯白，稍暗 → 平滑过渡 */
            double r = color.x / (1.0 + color.x);
            double g = color.y / (1.0 + color.y);
            double b = color.z / (1.0 + color.z);

            /* 伽马校正：让亮度更接近人眼感受 */
            r = pow(r, 1.0 / 2.2);
            g = pow(g, 1.0 / 2.2);
            b = pow(b, 1.0 / 2.2);

            int off = x * 3;
            row[off + 0] = (unsigned char)(b * 255);
            row[off + 1] = (unsigned char)(g * 255);
            row[off + 2] = (unsigned char)(r * 255);
        }
        fwrite(row, 1, (size_t)row_stride, fp);
    }
    fputc('\r', stderr);
    fprintf(stderr, "  完成！已写入 %s\n", filename);

    free(row);
    fclose(fp);
}

/* ================================================================
 * 6. 场景搭建
 * ================================================================ */
static void build_scene(void)
{
    /* 地面：巨大的球，半径 1000，看起来像平面 */
    add_sphere(v(0, -1000, 0), 1000.0, v(0.9, 0.9, 0.9), 0.0, 1);

    /* 中央镜面球 */
    add_sphere(v( 0.0, 1.0, 0.0), 1.0, v(0.95, 0.95, 1.0), 0.85, 0);

    /* 左侧哑光球（珊瑚红） */
    add_sphere(v(-2.2, 0.8, -0.5), 0.8, v(0.9, 0.3, 0.25), 0.05, 0);

    /* 右侧哑光球（青绿） */
    add_sphere(v( 2.2, 0.8, -0.5), 0.8, v(0.2, 0.8, 0.5), 0.05, 0);

    /* 远处小镜面球 */
    add_sphere(v(-1.0, 0.5, -2.0), 0.5, v(1.0, 0.9, 0.6), 0.6, 0);
}

/* ================================================================
 * 7. main
 * ================================================================ */
int main(int argc, char **argv)
{
    const char *out = (argc > 1) ? argv[1] : "scene.bmp";
    int W           = (argc > 2) ? atoi(argv[2]) : 800;
    int H           = (argc > 3) ? atoi(argv[3]) : 600;
    int samples     = (argc > 4) ? atoi(argv[4]) : 4;

    if (W < 32 || H < 32 || W > 4000 || H > 4000) {
        fprintf(stderr, "尺寸非法（32~4000）\n");
        return 1;
    }
    if (samples < 1) samples = 1;
    if (samples > 64) samples = 64;

    srand(42);   /* 固定种子，每次渲染结果一致 */

    build_scene();
    render(out, W, H, samples);

    printf("\n用图片查看器打开: %s\n", out);
    printf("推荐尝试:\n");
    printf("  ./raytracer scene.bmp 1600 1200 8     # 高清 + 8x 抗锯齿\n");
    printf("  ./raytracer draft.bmp  400  300 1     # 快速预览\n");

    return 0;
}
