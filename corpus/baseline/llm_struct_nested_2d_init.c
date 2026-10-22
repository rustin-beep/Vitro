// @category: llm_regression
// #179 红锚：struct 内嵌多维数组初始化错位（图像卷积题）
// 来源：LLM 探针批 8 gemma426b/LONG11_s1（208 行，2026-10-21 入库；clang golden 由 clang_direct 现场生成）
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <ctype.h>

#define WIDTH 8
#define HEIGHT 8
#define KERNEL_SIZE 3
#define HIST_BINS 8
#define BIN_SIZE 32

typedef struct {
    unsigned char data[HEIGHT][WIDTH];
} Image;

typedef struct {
    int counts[HIST_BINS];
    double percentages[HIST_BINS];
} Histogram;

void print_image_hex(const Image* img) {
    for (int y = 0; y < HEIGHT; y++) {
        for (int x = 0; x < WIDTH; x++) {
            printf("%02X ", img->data[y][x]);
        }
        printf("\n");
    }
}

void print_image_val(const Image* img) {
    for (int y = 0; y < HEIGHT; y++) {
        for (int x = 0; x < WIDTH; x++) {
            printf("%3d ", (int)img->data[y][x]);
        }
        printf("\n");
    }
}

unsigned long long calculate_sum(const Image* img) {
    unsigned long long sum = 0;
    for (int y = 0; y < HEIGHT; y++) {
        for (int x = 0; x < WIDTH; x++) {
            sum += img->data[y][x];
        }
    }
    return sum;
}

void mean_filter(const Image* src, Image* dst) {
    for (int y = 0; y < HEIGHT; y++) {
        for (int x = 0; x < WIDTH; x++) {
            int sum = 0;
            for (int ky = -1; ky <= 1; ky++) {
                for (int kx = -1; kx <= 1; kx++) {
                    int py = y + ky;
                    int px = x + kx;
                    if (py < 0) py = 0;
                    if (py >= HEIGHT) py = HEIGHT - 1;
                    if (px < 0) px = 0;
                    if (px >= WIDTH) px = WIDTH - 1;
                    sum += src->data[py][px];
                }
            }
            dst->data[y][x] = (unsigned char)(sum / 9);
        }
    }
}

void convolution(const Image* src, Image* dst, const int kernel[3][3]) {
    for (int y = 0; y < HEIGHT; y++) {
        for (int x = 0; x < WIDTH; x++) {
            int sum = 0;
            for (int ky = -1; ky <= 1; ky++) {
                for (int kx = -1; kx <= 1; kx++) {
                    int py = y + ky;
                    int px = x + kx;
                    if (py < 0) py = 0;
                    if (py >= HEIGHT) py = HEIGHT - 1;
                    if (px < 0) px = 0;
                    if (px >= WIDTH) px = WIDTH - 1;
                    sum += (int)src->data[py][px] * kernel[ky + 1][kx + 1];
                }
            }
            if (sum < 0) sum = 0;
            if (sum > 255) sum = 255;
            dst->data[y][x] = (unsigned char)sum;
        }
    }
}

void sobel_edge(const Image* src, Image* magnitude, Image* binary, int threshold) {
    int Gx[3][3] = {{-1, 0, 1}, {-2, 0, 2}, {-1, 0, 1}};
    int Gy[3][3] = {{-1, -2, -1}, {0, 0, 0}, {1, 2, 1}};

    for (int y = 0; y < HEIGHT; y++) {
        for (int x = 0; x < WIDTH; x++) {
            float sumX = 0;
            float sumY = 0;
            for (int ky = -1; ky <= 1; ky++) {
                for (int kx = -1; kx <= 1; kx++) {
                    int py = y + ky;
                    int px = x + kx;
                    if (py < 0) py = 0;
                    if (py >= HEIGHT) py = HEIGHT - 1;
                    if (px < 0) px = 0;
                    if (px >= WIDTH) px = WIDTH - 1;
                    float val = (float)src->data[py][px];
                    sumX += val * (float)Gx[ky + 1][kx + 1];
                    sumY += val * (float)Gy[ky + 1][kx + 1];
                }
            }
            float mag = sqrt(sumX * sumX + sumY * sumY);
            if (mag > 255.0f) mag = 255.0f;
            magnitude->data[y][x] = (unsigned char)mag;
            if (mag >= (float)threshold) {
                binary->data[y][x] = 255;
            } else {
                binary->data[y][x] = 0;
            }
        }
    }
}

void compute_histogram(const Image* img, Histogram* hist) {
    for (int i = 0; i < HIST_BINS; i++) {
        hist->counts[i] = 0;
    }
    for (int y = 0; y < HEIGHT; y++) {
        for (int x = 0; x < WIDTH; x++) {
            int val = (int)img->data[y][x];
            int bin = val / BIN_SIZE;
            if (bin >= HIST_BINS) bin = HIST_BINS - 1;
            hist->counts[bin]++;
        }
    }
    for (int i = 0; i < HIST_BINS; i++) {
        hist->percentages[i] = (double)hist->counts[i] * 100.0 / (WIDTH * HEIGHT);
    }
}

void print_histogram(const Histogram* hist) {
    printf("Bin | Count | Percent\n");
    printf("----|-------|--------\n");
    for (int i = 0; i < HIST_BINS; i++) {
        printf("%3d | %5d | %5.1f%%\n", i * BIN_SIZE, hist->counts[i], hist->percentages[i]);
    }
}

int main() {
    Image input = {{
        {50, 55, 60, 60, 60, 60, 55, 50},
        {55, 200, 210, 210, 210, 210, 200, 55},
        {60, 210, 255, 255, 255, 255, 210, 60},
        {60, 210, 255, 255, 255, 255, 210, 60},
        {60, 210, 255, 255, 255, 255, 210, 60},
        {55, 200, 210, 210, 210, 210, 200, 55},
        {50, 55, 60, 60, 60, 60, 55, 50},
        {40, 45, 50, 50, 50, 50, 45, 40}
    }};

    Image mean_img;
    Image sharp_img;
    Image sobel_mag;
    Image sobel_bin;
    Histogram hist_orig, hist_sharp;

    int sharpen_kernel[3][3] = {
        {0, -1, 0},
        {-1, 5, -1},
        {0, -1, 0}
    };

    printf("--- Original Image (Hex) ---\n");
    print_image_hex(&input);
    printf("Sum: %llu\n\n", calculate_sum(&input));

    printf("--- Mean Filtered Image ---\n");
    mean_filter(&input, &mean_img);
    print_image_val(&mean_img);
    printf("Sum: %llu\n\n", calculate_sum(&mean_img));

    printf("--- Sharpened Image ---\n");
    convolution(&input, &sharp_img, sharpen_kernel);
    print_image_val(&sharp_img);
    printf("Sum: %llu\n\n", calculate_sum(&sharp_img));

    printf("--- Sobel Magnitude ---\n");
    sobel_edge(&input, &sobel_mag, &sobel_bin, 100);
    print_image_val(&sobel_mag);
    printf("Sum: %llu\n\n", calculate_sum(&sobel_mag));

    printf("--- Sobel Binary (Threshold 100) ---\n");
    print_image_val(&sobel_bin);
    printf("Sum: %llu\n\n", calculate_sum(&sobel_bin));

    printf("--- Histogram (Original) ---\n");
    compute_histogram(&input, &hist_orig);
    print_histogram(&hist_orig);
    printf("\n");

    printf("--- Histogram (Sharpened) ---\n");
    compute_histogram(&sharp_img, &hist_sharp);
    print_histogram(&hist_sharp);
    printf("\n");

    return 0;
}
