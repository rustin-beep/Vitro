#include <stdio.h>
#include <string.h>
#include "crypto.h"

#define BUFFER_SIZE 1024

static void show(const char *label, const unsigned char *data, size_t length)
{
    char crc_hex[CRYPTO_HEX_LEN + 1];
    char djb_hex[CRYPTO_HEX_LEN + 1];
    char fnv_hex[CRYPTO_HEX_LEN + 1];
    char adl_hex[CRYPTO_HEX_LEN + 1];

    crypto_to_hex(crypto_crc32(data, length), crc_hex, sizeof crc_hex);
    crypto_to_hex(crypto_djb2(data, length), djb_hex, sizeof djb_hex);
    crypto_to_hex(crypto_fnv1a(data, length), fnv_hex, sizeof fnv_hex);
    crypto_to_hex(crypto_adler32(data, length), adl_hex, sizeof adl_hex);
    printf("  %-22s crc32=%s djb2=%s fnv1a=%s adler32=%s\n", label,
           crc_hex, djb_hex, fnv_hex, adl_hex);
}

int main(void)
{
    static const char *const TEXT = "123456789";
    static const char *const SENTENCE = "the quick brown fox jumps over the lazy dog";
    unsigned char pattern[64];
    unsigned char buffer[BUFFER_SIZE];
    char hex[CRYPTO_HEX_LEN + 1];
    int i;

    printf("=== five inputs ===\n");
    show("empty string", (const unsigned char *)"", 0);
    show("single character", (const unsigned char *)"A", 1);
    show("plain sentence", (const unsigned char *)SENTENCE, strlen(SENTENCE));
    {
        unsigned char with_zero[8] = { 'a', 'b', 0x00, 'c', 'd', 0x00, 0xff, 0x7f };
        show("bytes with zero", with_zero, sizeof with_zero);
    }
    for (i = 0; i < 64; i++) {
        pattern[i] = (unsigned char)((i * 7) & 0xff);
    }
    show("sixty four byte pattern", pattern, sizeof pattern);

    printf("=== crc32 test vector ===\n");
    crypto_to_hex(crypto_crc32((const unsigned char *)TEXT, strlen(TEXT)), hex, sizeof hex);
    printf("  input=\"%s\" value=%s expected=cbf43926 match=%s\n", TEXT, hex,
           (strcmp(hex, "cbf43926") == 0) ? "yes" : "no");

    printf("=== single bit flip detection ===\n");
    {
        unsigned char original[16];
        unsigned char changed[16];
        unsigned int crc_original;
        unsigned int crc_changed;
        memcpy(original, "vitro crypto demo", 16);
        memcpy(changed, original, 16);
        changed[5] = (unsigned char)(changed[5] ^ 0x01);
        crc_original = crypto_crc32(original, 16);
        crc_changed = crypto_crc32(changed, 16);
        crypto_to_hex(crc_original, hex, sizeof hex);
        printf("  original=%s", hex);
        crypto_to_hex(crc_changed, hex, sizeof hex);
        printf(" changed=%s detected=%s\n", hex,
               (crc_original != crc_changed) ? "yes" : "no");
        printf("  bit_flip_helper=%u\n", crypto_flip_bit(0x00ff00ffu, 8));
    }

    printf("=== one kilobyte buffer ===\n");
    for (i = 0; i < BUFFER_SIZE; i++) {
        buffer[i] = (unsigned char)((i * 31 + 17) & 0xff);
    }
    show("1024 byte pattern", buffer, BUFFER_SIZE);

    printf("=== relative work estimate ===\n");
    {
        long crc_work = 0;
        long djb_work = 0;
        long fnv_work = 0;
        long adler_work = 0;
        int pass;
        for (pass = 0; pass < 200; pass++) {
            crc_work += (long)(crypto_crc32(buffer, BUFFER_SIZE) & 0xffu);
            djb_work += (long)(crypto_djb2(buffer, BUFFER_SIZE) & 0xfful);
            fnv_work += (long)(crypto_fnv1a(buffer, BUFFER_SIZE) & 0xfful);
            adler_work += (long)(crypto_adler32(buffer, BUFFER_SIZE) & 0xffu);
        }
        printf("  crc32_units=%ld djb2_units=%ld fnv1a_units=%ld adler32_units=%ld\n",
               crc_work, djb_work, fnv_work, adler_work);
        printf("  relative_to_crc32: djb2=%.2f fnv1a=%.2f adler32=%.2f\n",
               (double)djb_work / (double)crc_work,
               (double)fnv_work / (double)crc_work,
               (double)adler_work / (double)crc_work);
    }
    printf("=== done ===\n");
    return 0;
}
