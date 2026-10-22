#include <stdio.h>
#include <string.h>
#include "tar.h"

static void copy_text(char *dst, size_t cap, const char *src)
{
    size_t n = strlen(src);

    if (n > cap - 1) {
        n = cap - 1;
    }
    memcpy(dst, src, n);
    dst[n] = '\0';
}

int main(void)
{
    TarFile files[3];
    TarFile restored[TAR_MAX_FILES];
    unsigned char archive[4096];
    int archive_len = 0;
    int packed;
    int unpacked;
    int count = 0;
    int i;
    int same = 1;

    memset(files, 0, sizeof files);
    copy_text(files[0].name, sizeof files[0].name, "readme.txt");
    copy_text(files[0].content, sizeof files[0].content, "vitro tar library demo\n");
    files[0].size = (int)strlen(files[0].content);

    copy_text(files[1].name, sizeof files[1].name, "data.bin");
    for (i = 0; i < 100; i++) {
        files[1].content[i] = (char)(i & 0xff);
    }
    files[1].size = 100;

    copy_text(files[2].name, sizeof files[2].name, "empty.txt");
    files[2].size = 0;

    printf("=== pack ===\n");
    packed = tar_pack(files, 3, archive, (int)sizeof archive, &archive_len);
    printf("  tar_pack returned %d bytes\n", packed);
    printf("  archive is a multiple of %d: %s\n", TAR_BLOCK_SIZE,
           ((archive_len % TAR_BLOCK_SIZE) == 0) ? "yes" : "no");

    printf("=== headers ===\n");
    for (i = 0; i < 3; i++) {
        TarHeader header;
        int offset = i * (TAR_BLOCK_SIZE * 2);
        tar_read_header(archive + offset, &header);
        printf("  entry %d\n", i + 1);
        tar_print_header(&header);
        printf("    computed_checksum=%d\n", tar_header_checksum(archive + offset));
    }

    printf("=== first bytes ===\n");
    tar_hex_dump(archive, archive_len, 64);

    printf("=== unpack ===\n");
    unpacked = tar_unpack(archive, archive_len, restored, TAR_MAX_FILES, &count);
    printf("  tar_unpack returned %d files\n", unpacked);
    for (i = 0; i < count; i++) {
        printf("  entry %d name=[%s] size=%d first_byte=%d\n",
               i + 1, restored[i].name, restored[i].size,
               (restored[i].size > 0) ? (int)(unsigned char)restored[i].content[0] : 0);
        if (strcmp(restored[i].name, files[i].name) != 0 ||
            restored[i].size != files[i].size ||
            memcmp(restored[i].content, files[i].content, (size_t)files[i].size) != 0) {
            same = 0;
        }
    }
    printf("  contents_identical=%s\n", same ? "yes" : "no");

    printf("=== corrupted checksum ===\n");
    {
        unsigned char broken[4096];
        TarFile broken_files[TAR_MAX_FILES];
        int broken_count = 0;
        int rc;
        memcpy(broken, archive, (size_t)archive_len);
        broken[TAR_OFF_CHKSUM + 2] = (unsigned char)(broken[TAR_OFF_CHKSUM + 2] ^ 0x01);
        printf("  patched byte %d of the first checksum\n", TAR_OFF_CHKSUM + 2);
        rc = tar_unpack(broken, archive_len, broken_files, TAR_MAX_FILES, &broken_count);
        printf("  tar_unpack returned %d (negative means the error was detected)\n", rc);
    }

    printf("=== summary ===\n");
    printf("  tar_ops=%d\n", tar_ops);
    printf("  files=3 archive_bytes=%d blocks=%d\n",
           archive_len, archive_len / TAR_BLOCK_SIZE);
    return 0;
}
