#include "tar.h"

int tar_ops = 0;
#include <stdio.h>
#include <string.h>

static void tar_copy_name(char *dst, const char *src)
{
    size_t n = strlen(src);

    if (n > (size_t)TAR_NAME_LEN - 1) {
        n = (size_t)TAR_NAME_LEN - 1;
    }
    memcpy(dst, src, n);
    dst[n] = '\0';
}

static void tar_write_octal(unsigned char *dest, int length, unsigned long value)
{
    int i;

    for (i = length - 2; i >= 0; i--) {
        dest[i] = (unsigned char)('0' + (int)(value & 7UL));
        value >>= 3;
    }
    dest[length - 1] = '\0';
}

static unsigned long tar_read_octal(const unsigned char *source, int length)
{
    unsigned long value = 0UL;
    int i;

    for (i = 0; i < length; i++) {
        char c = (char)source[i];
        if (c == ' ' || c == '\0') {
            continue;
        }
        if (c < '0' || c > '7') {
            break;
        }
        value = value * 8UL + (unsigned long)(c - '0');
    }
    return value;
}

int tar_header_checksum(const unsigned char *block)
{
    int sum = 0;
    int i;

    if (block == NULL) {
        return -1;
    }
    for (i = 0; i < TAR_BLOCK_SIZE; i++) {
        if (i >= TAR_OFF_CHKSUM && i < TAR_OFF_CHKSUM + 8) {
            sum += ' ';
        } else {
            sum += (int)block[i];
        }
    }
    return sum;
}

void tar_read_header(const unsigned char *block, TarHeader *header)
{
    if (block == NULL || header == NULL) {
        return;
    }
    memset(header, 0, sizeof(TarHeader));
    memcpy(header->name, block + TAR_OFF_NAME, TAR_NAME_LEN);
    header->name[TAR_NAME_LEN - 1] = '\0';
    memcpy(header->mode, block + TAR_OFF_MODE, 8);
    header->mode[7] = '\0';
    memcpy(header->uid, block + TAR_OFF_UID, 8);
    header->uid[7] = '\0';
    memcpy(header->gid, block + TAR_OFF_GID, 8);
    header->gid[7] = '\0';
    memcpy(header->size, block + TAR_OFF_SIZE, TAR_SIZE_LEN);
    header->size[TAR_SIZE_LEN - 1] = '\0';
    memcpy(header->mtime, block + TAR_OFF_MTIME, TAR_SIZE_LEN);
    header->mtime[TAR_SIZE_LEN - 1] = '\0';
    memcpy(header->chksum, block + TAR_OFF_CHKSUM, TAR_CHKSUM_LEN);
    header->chksum[TAR_CHKSUM_LEN - 1] = '\0';
    header->typeflag = (char)block[TAR_OFF_TYPEFLAG];
    memcpy(header->magic, block + TAR_OFF_MAGIC, 6);
    header->magic[5] = '\0';
}

void tar_write_header(unsigned char *block, const TarHeader *header)
{
    if (block == NULL || header == NULL) {
        return;
    }
    memset(block, 0, TAR_BLOCK_SIZE);
    memcpy(block + TAR_OFF_NAME, header->name, strlen(header->name));
    memcpy(block + TAR_OFF_MODE, "0000644", 7);
    memcpy(block + TAR_OFF_UID, "0000000", 7);
    memcpy(block + TAR_OFF_GID, "0000000", 7);
    tar_write_octal(block + TAR_OFF_SIZE, TAR_SIZE_LEN,
                    tar_read_octal((const unsigned char *)header->size, TAR_SIZE_LEN));
    tar_write_octal(block + TAR_OFF_MTIME, TAR_SIZE_LEN,
                    tar_read_octal((const unsigned char *)header->mtime, TAR_SIZE_LEN));
    memset(block + TAR_OFF_CHKSUM, ' ', 8);
    block[TAR_OFF_TYPEFLAG] = (unsigned char)header->typeflag;
    memcpy(block + TAR_OFF_MAGIC, "ustar", 5);
    memcpy(block + TAR_OFF_MAGIC + 5, "00", 2);
}

static void tar_store_checksum(unsigned char *block, int checksum)
{
    int i;
    char digits[8];

    digits[0] = '\0';
    for (i = 0; i < 6; i++) {
        digits[i] = (char)('0' + ((checksum >> ((5 - i) * 3)) & 7));
    }
    digits[6] = '\0';
    memcpy(block + TAR_OFF_CHKSUM, digits, 6);
    block[TAR_OFF_CHKSUM + 6] = '\0';
    block[TAR_OFF_CHKSUM + 7] = ' ';
}

int tar_pack(const TarFile *files, int count, unsigned char *buffer, int capacity, int *out_length)
{
    int written = 0;
    int i;

    if (files == NULL || buffer == NULL || count < 0 || out_length == NULL) {
        return -1;
    }
    for (i = 0; i < count; i++) {
        unsigned char block[TAR_BLOCK_SIZE];
        TarHeader header;
        int size = files[i].size;
        int padded;
        int checksum;

        memset(&header, 0, sizeof header);
        tar_copy_name(header.name, files[i].name);
        header.typeflag = '0';
        tar_write_octal((unsigned char *)header.size, TAR_SIZE_LEN, (unsigned long)size);
        tar_write_octal((unsigned char *)header.mtime, TAR_SIZE_LEN, 1700000000UL);
        tar_write_header(block, &header);
        checksum = tar_header_checksum(block);
        tar_store_checksum(block, checksum);

        if (written + TAR_BLOCK_SIZE > capacity) {
            return -2;
        }
        memcpy(buffer + written, block, TAR_BLOCK_SIZE);
        written += TAR_BLOCK_SIZE;

        if (size < 0 || size > TAR_MAX_CONTENT) {
            return -3;
        }
        padded = ((size + TAR_BLOCK_SIZE - 1) / TAR_BLOCK_SIZE) * TAR_BLOCK_SIZE;
        if (written + padded > capacity) {
            return -2;
        }
        memset(buffer + written, 0, (size_t)padded);
        memcpy(buffer + written, files[i].content, (size_t)size);
        written += padded;
        tar_ops++;
    }
    if (written + TAR_BLOCK_SIZE > capacity) {
        return -2;
    }
    memset(buffer + written, 0, TAR_BLOCK_SIZE);
    written += TAR_BLOCK_SIZE;
    *out_length = written;
    return written;
}

int tar_unpack(const unsigned char *buffer, int length, TarFile *files, int max_files, int *out_count)
{
    int offset = 0;
    int count = 0;

    if (buffer == NULL || files == NULL || out_count == NULL) {
        return -1;
    }
    while (offset + TAR_BLOCK_SIZE <= length) {
        TarHeader header;
        unsigned long size;
        int stored;
        int computed;
        int padded;

        if (buffer[offset] == '\0') {
            break;
        }
        tar_read_header(buffer + offset, &header);
        stored = (int)tar_read_octal((const unsigned char *)header.chksum, TAR_CHKSUM_LEN);
        computed = tar_header_checksum(buffer + offset);
        if (stored != computed) {
            printf("  checksum error in header %s: stored=%d computed=%d\n",
                   header.name, stored, computed);
            return -2;
        }
        size = tar_read_octal((const unsigned char *)header.size, TAR_SIZE_LEN);
        if (size > (unsigned long)TAR_MAX_CONTENT) {
            printf("  entry %s is too large\n", header.name);
            return -3;
        }
        offset += TAR_BLOCK_SIZE;
        if (count < max_files) {
            tar_copy_name(files[count].name, header.name);
            files[count].size = (int)size;
            memset(files[count].content, 0, sizeof files[count].content);
            memcpy(files[count].content, buffer + offset, (size_t)size);
            count++;
        }
        padded = (int)(((size + (unsigned long)TAR_BLOCK_SIZE - 1UL) / (unsigned long)TAR_BLOCK_SIZE)
                       * (unsigned long)TAR_BLOCK_SIZE);
        offset += padded;
    }
    *out_count = count;
    return count;
}

void tar_print_header(const TarHeader *header)
{
    if (header == NULL) {
        return;
    }
    printf("    name=[%s] mode=%s uid=%s gid=%s size=%s mtime=%s chksum=%s type=%c magic=%s\n",
           header->name, header->mode, header->uid, header->gid, header->size,
           header->mtime, header->chksum, header->typeflag, header->magic);
}

void tar_hex_dump(const unsigned char *data, int length, int max_bytes)
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
