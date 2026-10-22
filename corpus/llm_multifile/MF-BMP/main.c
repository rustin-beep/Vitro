#include <stdio.h>
#include <string.h>
#include "bmp.h"

#define IMAGE_WIDTH 8
#define IMAGE_HEIGHT 8

int main(void)
{
    unsigned char buffer[512];
    BmpPixel pixels[IMAGE_WIDTH * IMAGE_HEIGHT];
    BmpPixel parsed[IMAGE_WIDTH * IMAGE_HEIGHT];
    BmpPixel gray[IMAGE_WIDTH * IMAGE_HEIGHT];
    BmpPixel flipped[IMAGE_WIDTH * IMAGE_HEIGHT];
    BmpInfo info;
    int written;
    int rc;
    int row;
    int col;
    int identical;
    int i;

    printf("=== build image ===\n");
    for (row = 0; row < IMAGE_HEIGHT; row++) {
        for (col = 0; col < IMAGE_WIDTH; col++) {
            BmpPixel *pixel = &pixels[row * IMAGE_WIDTH + col];
            int in_square = (row >= 2 && row <= 4 && col >= 3 && col <= 5) ? 1 : 0;
            if (in_square) {
                pixel->r = 255;
                pixel->g = 255;
                pixel->b = 255;
            } else {
                pixel->r = (unsigned char)(row * 30);
                pixel->g = (unsigned char)(col * 30);
                pixel->b = (unsigned char)((row + col) * 15);
            }
        }
    }
    bmp_print_pixels(pixels, IMAGE_WIDTH * IMAGE_HEIGHT, 8);

    written = bmp_build(buffer, (int)sizeof buffer, pixels, IMAGE_WIDTH, IMAGE_HEIGHT);
    printf("  bmp_build returned %d bytes\n", written);

    printf("=== header fields ===\n");
    rc = bmp_parse(buffer, written, &info, parsed, IMAGE_WIDTH * IMAGE_HEIGHT);
    printf("  parse rc=%d\n", rc);
    printf("  file_size=%d data_offset=%d width=%d height=%d bpp=%d row_stride=%d\n",
           info.file_size, info.data_offset, info.width, info.height,
           info.bits_per_pixel, info.row_stride);

    printf("=== first 32 bytes ===\n");
    bmp_hex_dump(buffer, written, 32);

    printf("=== round trip ===\n");
    {
        unsigned char rebuilt[512];
        int rebuilt_len = bmp_build(rebuilt, (int)sizeof rebuilt, parsed,
                                    IMAGE_WIDTH, IMAGE_HEIGHT);
        int same = 0;
        if (rebuilt_len == written) {
            same = (memcmp(rebuilt, buffer, (size_t)written) == 0) ? 1 : 0;
        }
        identical = same;
        printf("  rebuilt_bytes=%d\n", rebuilt_len);
    }
    printf("  file_bytes_identical=%s\n", identical ? "yes" : "no");
    {
        int same = 1;
        for (i = 0; i < IMAGE_WIDTH * IMAGE_HEIGHT; i++) {
            if (pixels[i].r != parsed[i].r || pixels[i].g != parsed[i].g ||
                pixels[i].b != parsed[i].b) {
                same = 0;
            }
        }
        printf("  pixels_identical=%s\n", same ? "yes" : "no");
    }
    bmp_print_pixels(parsed, IMAGE_WIDTH * IMAGE_HEIGHT, 8);

    printf("=== grayscale ===\n");
    bmp_to_grayscale(parsed, gray, IMAGE_WIDTH * IMAGE_HEIGHT);
    bmp_print_pixels(gray, IMAGE_WIDTH * IMAGE_HEIGHT, 16);

    printf("=== horizontal flip ===\n");
    bmp_flip_horizontal(parsed, flipped, IMAGE_WIDTH, IMAGE_HEIGHT);
    bmp_print_pixels(flipped, IMAGE_WIDTH * IMAGE_HEIGHT, 16);

    printf("=== size check ===\n");
    printf("  actual_bytes=%d theoretical=%d match=%s\n",
           written, bmp_theoretical_size(IMAGE_WIDTH, IMAGE_HEIGHT),
           (written == bmp_theoretical_size(IMAGE_WIDTH, IMAGE_HEIGHT)) ? "yes" : "no");
    printf("  is_multiple_of_512=%s\n", ((written % 512) == 0) ? "yes" : "no");
    printf("  bmp_ops=%d\n", bmp_ops);
    return 0;
}
