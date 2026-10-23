#include "bmp.h"

int bmp_ops = 0;
#include <stdio.h>
#include <string.h>

static void put_u16(unsigned char *buf, int value)
{
    buf[0] = (unsigned char)(value & 0xff);
    buf[1] = (unsigned char)((value >> 8) & 0xff);
}

static void put_u32(unsigned char *buf, unsigned long value)
{
    buf[0] = (unsigned char)(value & 0xffUL);
    buf[1] = (unsigned char)((value >> 8) & 0xffUL);
    buf[2] = (unsigned char)((value >> 16) & 0xffUL);
    buf[3] = (unsigned char)((value >> 24) & 0xffUL);
}

static int get_u16(const unsigned char *buf)
{
    return (int)((unsigned int)buf[0] | ((unsigned int)buf[1] << 8));
}

static unsigned long get_u32(const unsigned char *buf)
{
    return (unsigned long)buf[0] | ((unsigned long)buf[1] << 8) |
           ((unsigned long)buf[2] << 16) | ((unsigned long)buf[3] << 24);
}

int bmp_theoretical_size(int width, int height)
{
    int stride;

    if (width <= 0 || height <= 0) {
        return -1;
    }
    stride = ((width * 3) + (BMP_ALIGNMENT - 1)) & ~(BMP_ALIGNMENT - 1);
    return BMP_FILE_HEADER_SIZE + BMP_INFO_HEADER_SIZE + stride * height;
}

int bmp_build(unsigned char *buf, int cap, const BmpPixel *pixels, int width, int height)
{
    int stride;
    int data_size;
    int file_size;
    int row;
    int col;

    if (buf == NULL || pixels == NULL) {
        return -1;
    }
    if (width <= 0 || height <= 0) {
        return -1;
    }
    stride = ((width * 3) + (BMP_ALIGNMENT - 1)) & ~(BMP_ALIGNMENT - 1);
    data_size = stride * height;
    file_size = BMP_FILE_HEADER_SIZE + BMP_INFO_HEADER_SIZE + data_size;
    if (cap < file_size) {
        return -1;
    }
    memset(buf, 0, (size_t)file_size);

    buf[0] = 'B';
    buf[1] = 'M';
    put_u32(buf + 2, (unsigned long)file_size);
    put_u16(buf + 6, 0);
    put_u16(buf + 8, 0);
    put_u32(buf + 10, (unsigned long)(BMP_FILE_HEADER_SIZE + BMP_INFO_HEADER_SIZE));

    put_u32(buf + 14, (unsigned long)BMP_INFO_HEADER_SIZE);
    put_u32(buf + 18, (unsigned long)width);
    put_u32(buf + 22, (unsigned long)height);
    put_u16(buf + 26, 1);
    put_u16(buf + 28, BMP_BPP);
    put_u32(buf + 30, 0UL);
    put_u32(buf + 34, (unsigned long)data_size);
    put_u32(buf + 38, 2835UL);
    put_u32(buf + 42, 2835UL);
    put_u32(buf + 46, 0UL);
    put_u32(buf + 50, 0UL);

    for (row = 0; row < height; row++) {
        int source_row = height - 1 - row;
        unsigned char *line = buf + BMP_FILE_HEADER_SIZE + BMP_INFO_HEADER_SIZE + row * stride;
        for (col = 0; col < width; col++) {
            const BmpPixel *pixel = &pixels[source_row * width + col];
            line[col * 3 + 0] = pixel->b;
            line[col * 3 + 1] = pixel->g;
            line[col * 3 + 2] = pixel->r;
        }
        for (col = width * 3; col < stride; col++) {
            line[col] = 0;
        }
    }
    bmp_ops++;
    return file_size;
}

int bmp_parse(const unsigned char *buf, int length, BmpInfo *info, BmpPixel *pixels, int max_pixels)
{
    int width;
    int height;
    int bpp;
    int offset;
    int stride;
    int row;
    int col;

    if (buf == NULL || info == NULL) {
        return -1;
    }
    if (length < BMP_FILE_HEADER_SIZE + BMP_INFO_HEADER_SIZE) {
        return -2;
    }
    if (buf[0] != 'B' || buf[1] != 'M') {
        return -3;
    }
    if (get_u32(buf + 14) != (unsigned long)BMP_INFO_HEADER_SIZE) {
        return -4;
    }
    width = (int)get_u32(buf + 18);
    height = (int)get_u32(buf + 22);
    bpp = get_u16(buf + 28);
    offset = (int)get_u32(buf + 10);
    if (bpp != BMP_BPP) {
        return -5;
    }
    if (width <= 0 || height <= 0) {
        return -6;
    }
    stride = ((width * 3) + (BMP_ALIGNMENT - 1)) & ~(BMP_ALIGNMENT - 1);
    if (offset + stride * height > length) {
        return -7;
    }
    info->width = width;
    info->height = height;
    info->bits_per_pixel = bpp;
    info->data_offset = offset;
    info->file_size = (int)get_u32(buf + 2);
    info->row_stride = stride;
    if (pixels != NULL) {
        if (max_pixels < width * height) {
            return -8;
        }
        for (row = 0; row < height; row++) {
            int source_row = height - 1 - row;
            const unsigned char *line = buf + offset + row * stride;
            for (col = 0; col < width; col++) {
                BmpPixel *pixel = &pixels[source_row * width + col];
                pixel->b = line[col * 3 + 0];
                pixel->g = line[col * 3 + 1];
                pixel->r = line[col * 3 + 2];
            }
        }
    }
    return 0;
}

int bmp_to_grayscale(const BmpPixel *in, BmpPixel *out, int count)
{
    int i;

    if (in == NULL || out == NULL || count < 0) {
        return -1;
    }
    for (i = 0; i < count; i++) {
        int gray = (int)((in[i].r * 30 + in[i].g * 59 + in[i].b * 11) / 100);
        if (gray < 0) {
            gray = 0;
        }
        if (gray > 255) {
            gray = 255;
        }
        out[i].b = (unsigned char)gray;
        out[i].g = (unsigned char)gray;
        out[i].r = (unsigned char)gray;
    }
    return count;
}

int bmp_flip_horizontal(const BmpPixel *in, BmpPixel *out, int width, int height)
{
    int row;
    int col;

    if (in == NULL || out == NULL || width <= 0 || height <= 0) {
        return -1;
    }
    for (row = 0; row < height; row++) {
        for (col = 0; col < width; col++) {
            out[row * width + col] = in[row * width + (width - 1 - col)];
        }
    }
    return width * height;
}

void bmp_hex_dump(const unsigned char *data, int length, int max_bytes)
{
    int i;
    int limit;

    if (data == NULL) {
        return;
    }
    limit = (length < max_bytes) ? length : max_bytes;
    for (i = 0; i < limit; i += 16) {
        int j;
        printf("  %04x  ", i);
        for (j = 0; j < 16; j++) {
            if (i + j < limit) {
                printf("%02x ", data[i + j]);
            } else {
                printf("   ");
            }
        }
        printf("\n");
    }
}

void bmp_print_pixels(const BmpPixel *pixels, int count, int max_pixels)
{
    int i;
    int limit;

    if (pixels == NULL) {
        return;
    }
    limit = (count < max_pixels) ? count : max_pixels;
    printf("  pixels:");
    for (i = 0; i < limit; i++) {
        printf(" %02x%02x%02x", pixels[i].r, pixels[i].g, pixels[i].b);
    }
    printf("\n");
}
