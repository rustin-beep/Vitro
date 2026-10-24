#ifndef TAR_H
#define TAR_H

#include <stddef.h>

#define TAR_BLOCK_SIZE 512
#define TAR_NAME_LEN 100
#define TAR_MAX_FILES 8
#define TAR_MAX_CONTENT 256

#define TAR_OFF_NAME 0
#define TAR_OFF_MODE 100
#define TAR_OFF_UID 108
#define TAR_OFF_GID 116
#define TAR_OFF_SIZE 124
#define TAR_OFF_MTIME 136
#define TAR_OFF_CHKSUM 148
#define TAR_OFF_TYPEFLAG 156
#define TAR_OFF_MAGIC 157

#define TAR_SIZE_LEN 12
#define TAR_CHKSUM_LEN 9

typedef struct {
    char name[TAR_NAME_LEN];
    char mode[8];
    char uid[8];
    char gid[8];
    char size[12];
    char mtime[12];
    char chksum[9];
    char typeflag;
    char magic[6];
} TarHeader;

typedef struct {
    char name[TAR_NAME_LEN];
    int size;
    char content[TAR_MAX_CONTENT];
} TarFile;

/* packs the files into a tar archive, returns the number of bytes or -1 */
int tar_pack(const TarFile *files, int count, unsigned char *buffer, int capacity, int *out_length);

/* unpacks an archive and verifies every checksum, returns the number of files or -1 */
int tar_unpack(const unsigned char *buffer, int length, TarFile *files, int max_files, int *out_count);

/* checksum of a header block, the checksum field itself is treated as spaces */
int tar_header_checksum(const unsigned char *block);

/* reads the header fields out of a block */
void tar_read_header(const unsigned char *block, TarHeader *header);

/* writes the header fields into a block */
void tar_write_header(unsigned char *block, const TarHeader *header);

void tar_print_header(const TarHeader *header);
void tar_hex_dump(const unsigned char *data, int length, int max_bytes);

extern int tar_ops;

#endif /* TAR_H */
